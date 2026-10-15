// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Runs a LinuxNetworkPlan in the privileged tunnel helper and undoes it.
//
// Lifecycle:
//   1. [LinuxNetworkController.start] removes anything a crashed run left
//      behind, records what it is about to change in a state file under
//      /run/dartvel-vpn (one per network namespace), then adds the routing
//      rules and the firewall table. The kill switch is therefore in place
//      before the engine sends its first packet.
//   2. [onDevice] configures the tun device each time the engine creates one:
//      MTU, addresses, link up, routes, DNS.
//   3. [stop] removes every rule, route, firewall table and DNS setting it
//      made, and deletes the state file. If the helper is
//      killed before that, the next start (or `partout-tunnel --cleanup`)
//      does it from the state file. Until then the kill switch keeps blocking:
//      a crash fails closed.
//
// Nothing outside our own table, rules and nftables table is edited, except
// DNS (per link with systemd-resolved, or /etc/resolv.conf with a backup),
// which is restored on stop.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'linux_network_plan.dart';

/// Runs one program. Injected so tests can record commands.
typedef CommandRunner = Future<ProcessResult> Function(String executable, List<String> arguments, {String? input});

Future<ProcessResult> runCommand(String executable, List<String> arguments, {String? input}) async {
  if (input == null) return Process.run(executable, arguments);
  final process = await Process.start(executable, arguments);
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(input);
  await process.stdin.close();
  final code = await process.exitCode;
  return ProcessResult(process.pid, code, await out, await err);
}

/// Finds a system tool in the fixed system directories only (never PATH:
/// this code runs as root).
String? systemTool(String name) {
  for (final dir in const <String>['/usr/sbin', '/usr/bin', '/sbin', '/bin']) {
    final path = '$dir/$name';
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// How DNS is applied.
enum DnsMethod { resolved, resolvConf, none }

/// Filesystem locations, overridable for tests.
final class LinuxPaths {
  const LinuxPaths({
    this.stateDir = '/run/dartvel-vpn',
    this.proc = '/proc',
    this.resolvConf = '/etc/resolv.conf',
    this.resolvedSocket = '/run/systemd/resolve/io.systemd.Resolve',
  });
  final String stateDir;
  final String proc;
  final String resolvConf;
  final String resolvedSocket;
}

final class LinuxNetworkController {
  LinuxNetworkController(
    this.plan, {
    this.run = runCommand,
    this.paths = const LinuxPaths(),
    void Function(String message)? log,
    String? ipTool,
    String? nftTool,
    String? resolvectlTool,
  })  : log = log ?? ((_) {}),
        _ip = ipTool ?? systemTool('ip') ?? '/usr/sbin/ip',
        _nft = nftTool ?? systemTool('nft'),
        _resolvectl = resolvectlTool ?? systemTool('resolvectl');

  final LinuxNetworkPlan plan;
  final CommandRunner run;
  final LinuxPaths paths;
  final void Function(String message) log;
  final String _ip;
  final String? _nft;
  final String? _resolvectl;

  String? _device;
  int? _deviceIndex;
  DnsMethod _dns = DnsMethod.none;
  late final Map<String, Object?> _state = <String, Object?>{'version': 1};

  /// The tun device currently configured.
  String? get device => _device;

  /// The network namespace id, e.g. `4026531840`.
  String namespaceId() => _namespaceId('self');

  String _namespaceId(String process) {
    try {
      final target = Link('${paths.proc}/$process/ns/net').targetSync(); // net:[4026531840]
      return RegExp(r'\d+').firstMatch(target)?.group(0) ?? 'unknown';
    } on FileSystemException {
      return 'unknown';
    }
  }

  File get _stateFile => File('${paths.stateDir}/state-${namespaceId()}.json');

  /// Applies everything that does not depend on the tun device.
  Future<void> start() async {
    await cleanupStale(run: run, paths: paths, log: log, ipTool: _ip, nftTool: _nft, resolvectlTool: _resolvectl);
    for (final warning in plan.warnings) {
      log('Network: $warning');
    }
    if (plan.killSwitch && _nft == null) throw StateError('nftables (nft) is required for the kill switch');
    _dns = _chooseDns();
    _state['dns'] = _dns.name;
    if (_dns == DnsMethod.resolvConf && plan.dnsServers.isNotEmpty) {
      _state['resolvConfBackup'] = await _readResolvConf();
    }
    await _saveState();
    for (final command in plan.policyCommands()) {
      await _ipRun(command);
    }
    await _applyFirewall();
    log('Network: routing policy applied (table $kRouteTable${plan.killSwitch ? ', kill switch on' : ''})');
  }

  /// Configures [name] (the engine's tun device). Safe to call again with a
  /// new device after the engine reconnects.
  Future<void> onDevice(String name) async {
    if (!isSafeInterfaceName(name)) throw ArgumentError.value(name, 'name', 'unsafe interface name');
    final index = _interfaceIndex(name);
    if (name == _device && index == _deviceIndex) return;
    _device = name;
    _deviceIndex = index;
    _state['device'] = name;
    await _saveState();
    if (!plan.configuresInterface) {
      log('Network: $name has no addresses in this profile; it is left as the engine made it');
      await _applyFirewall();
      return;
    }
    for (final command in plan.linkCommands(name)) {
      await _ipRun(command);
    }
    await _applyFirewall();
    await _applyDns(name);
    log('Network: $name configured (${plan.addresses.length} addresses, '
        '${plan.includedV4.length + plan.includedV6.length} routes, '
        '${plan.excludedV4.length + plan.excludedV6.length} excluded, MTU ${plan.mtu})');
  }

  /// Removes everything [start] and [onDevice] did.
  Future<void> stop() async {
    await cleanupStale(run: run, paths: paths, log: log, ipTool: _ip, nftTool: _nft, resolvectlTool: _resolvectl);
    log('Network: restored');
  }

  /// Undoes a previous run in this network namespace: from its state file
  /// when there is one, and by our fixed rule priorities, table, nftables
  /// table and cgroup names in any case. Safe to run when nothing is left.
  static Future<void> cleanupStale({
    CommandRunner run = runCommand,
    LinuxPaths paths = const LinuxPaths(),
    void Function(String message)? log,
    String? ipTool,
    String? nftTool,
    String? resolvectlTool,
  }) async {
    final say = log ?? (_) {};
    final ip = ipTool ?? systemTool('ip') ?? '/usr/sbin/ip';
    final nft = nftTool ?? systemTool('nft');
    final resolvectl = resolvectlTool ?? systemTool('resolvectl');
    final probe = LinuxNetworkController(
      LinuxNetworkPlan.fromProfile(const <String, dynamic>{}),
      run: run,
      paths: paths,
      ipTool: ip,
      nftTool: nft,
      resolvectlTool: resolvectl,
    );
    final file = probe._stateFile;
    Map<String, dynamic> state = const <String, dynamic>{};
    if (file.existsSync()) {
      try {
        state = (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
      } on Object {
        say('Network: unreadable state file ${file.path}; cleaning by name');
      }
    }

    // Rules by priority, then our table.
    for (final family in const <String>['-4', '-6']) {
      for (final priority in kRulePriorities) {
        for (var attempt = 0; attempt < 64; attempt++) {
          final result = await run(ip, <String>[family, 'rule', 'del', 'priority', '$priority']);
          if (result.exitCode != 0) break;
        }
      }
      await run(ip, <String>[family, 'route', 'flush', 'table', '$kRouteTable']);
    }
    if (nft != null) {
      await run(nft, <String>['delete', 'table', 'inet', kNftTable]);
    }

    // DNS.
    final device = state['device'];
    if (state['dns'] == DnsMethod.resolved.name && device is String && isSafeInterfaceName(device) && resolvectl != null) {
      if (Directory('/sys/class/net/$device').existsSync()) await run(resolvectl, <String>['revert', device]);
    }
    final backup = state['resolvConfBackup'];
    if (backup is String) {
      try {
        // Truncate and write in place: /etc/resolv.conf may be a bind mount
        // (network namespaces) that cannot be replaced by rename.
        File(paths.resolvConf).writeAsStringSync(backup, flush: true);
      } on FileSystemException catch (error) {
        say('Network: could not restore ${paths.resolvConf}: ${error.message}');
      }
    }

    if (file.existsSync()) file.deleteSync();
  }

  // --- internals -----------------------------------------------------------

  Future<void> _ipRun(List<String> arguments) async {
    final result = await run(_ip, arguments);
    if (result.exitCode != 0) {
      throw StateError('ip ${arguments.join(' ')} failed: ${'${result.stderr}'.trim()}');
    }
  }

  Future<void> _applyFirewall() async {
    final script = plan.nftScript(_device);
    if (script == null || _nft == null) return;
    final result = await run(_nft, <String>['-f', '-'], input: script);
    if (result.exitCode != 0) {
      throw StateError('nft failed: ${'${result.stderr}'.trim()}');
    }
  }

  DnsMethod _chooseDns() {
    if (plan.dnsServers.isEmpty) return DnsMethod.none;
    final initial = namespaceId() == _namespaceId('1');
    // systemd-resolved belongs to the initial network namespace. From any
    // other namespace a per-link setting would land on whatever host link has
    // the same index, so it is never used there.
    if (initial && _resolvectl != null && File(paths.resolvedSocket).existsSync()) return DnsMethod.resolved;
    if (_resolvConfIsOwnMount() || (initial && !File(paths.resolvedSocket).existsSync())) {
      return DnsMethod.resolvConf;
    }
    log('Network: DNS not applied: no systemd-resolved here and ${paths.resolvConf} is shared with the host');
    return DnsMethod.none;
  }

  bool _resolvConfIsOwnMount() {
    try {
      for (final line in File('${paths.proc}/self/mountinfo').readAsLinesSync()) {
        final fields = line.split(' ');
        if (fields.length > 4 && fields[4] == paths.resolvConf) return true;
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  Future<String> _readResolvConf() async {
    try {
      return await File(paths.resolvConf).readAsString();
    } on FileSystemException {
      return '';
    }
  }

  Future<void> _applyDns(String device) async {
    switch (_dns) {
      case DnsMethod.resolved:
        for (final command in plan.resolvectlCommands(device)) {
          final result = await run(_resolvectl!, command);
          if (result.exitCode != 0) log('Network: resolvectl ${command.first} failed: ${'${result.stderr}'.trim()}');
        }
      case DnsMethod.resolvConf:
        final text = plan.resolvConf();
        if (text != null) File(paths.resolvConf).writeAsStringSync(text, flush: true);
      case DnsMethod.none:
        break;
    }
  }

  int? _interfaceIndex(String name) {
    try {
      return int.tryParse(File('/sys/class/net/$name/ifindex').readAsStringSync().trim());
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _saveState() async {
    final dir = Directory(paths.stateDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      await run('/bin/chmod', <String>['700', dir.path]);
    }
    _stateFile.writeAsStringSync(jsonEncode(_state), flush: true);
  }
}
