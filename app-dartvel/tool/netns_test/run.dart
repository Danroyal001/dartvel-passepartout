// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
//
// Real WireGuard tunnel test in network namespaces. Nothing on the host's own
// interfaces, routes, rules, firewall or DNS changes: both ends live in their
// own namespace, joined by a veth pair created inside them, and the host's
// rules and nftables tables are compared before and after.
//
// Needs root (or sudo), iproute2, wireguard-tools (`wg`, server side), the
// engine (docs/BUILD.md) and the helper built with
// `dart run tool/tunnel_helper/build.dart`. The server end uses the kernel
// WireGuard module when there is one, otherwise wireguard-go (WG_GO, or
// `wireguard-go` on PATH).
//
//   dart run tool/netns_test/run.dart [HELPER_DIR]
//
// The profile the helper gets is built in this process by the real engine and
// written straight to the helper's stdin: no profile or key file is created.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/domain/rule_groups.dart';
import 'package:passepartout/domain/tunnel_status.dart';
import 'package:passepartout/platform/tunnel/linux_network_plan.dart';
import 'package:passepartout/platform/tunnel/tunnel_protocol.dart';
import 'package:passepartout/platform/vpn_service_native.dart';

const _srv = 'ppnet-srv';
const _cli = 'ppnet-cli';
final _sudo = Platform.environment['USER'] == 'root' || _uid() == 0 ? <String>[] : <String>['sudo'];
final _verbose = Platform.environment['NETNS_VERBOSE'] == '1';
var _failures = 0;
Process? _wireguardGo;

int _uid() {
  final status = File('/proc/self/status').readAsLinesSync().firstWhere((l) => l.startsWith('Uid:'));
  return int.parse(status.split(RegExp(r'\s+'))[1]);
}

Future<void> main(List<String> args) async {
  final helperDir = args.isNotEmpty ? args.first : 'build/tunnel-helper';
  final helper = '${File('$helperDir/partout-tunnel').absolute.path}';
  if (!File(helper).existsSync()) {
    stderr.writeln('No helper at $helper. Build it: dart run tool/tunnel_helper/build.dart');
    exitCode = 2;
    return;
  }
  for (final tool in ['ip', 'nft', 'wg', 'ping']) {
    if ((await Process.run('which', [tool])).exitCode != 0) {
      stderr.writeln('Missing tool: $tool (iproute2, nftables, wireguard-tools, iputils-ping)');
      exitCode = 2;
      return;
    }
  }
  final hostBefore = await _hostSnapshot();
  try {
    await _teardown();
    final serverPublic = await _setUp();
    final engine = PartoutVpnService();
    final clientKey = await engine.generateWireGuardKey();
    final clientPublic = await engine.wireGuardPublicKey(clientKey);
    await _configureServer(clientPublic);
    final base = await engine.importProfile('''
[Interface]
PrivateKey = $clientKey
Address = 10.200.0.2/32

[Peer]
PublicKey = $serverPublic
AllowedIPs = 10.200.0.0/24
Endpoint = 10.99.0.1:51820
PersistentKeepalive = 5
''', 'netns');

    // 1. A plain tunnel: handshake, addresses and routes set by the helper,
    //    traffic through WireGuard, and everything undone on stop.
    stdout.writeln('== plain');
    final plain = await _Helper.start(helper, base);
    _check('connected', await plain.connected);
    _check('tun device has the profile address', (await _ns(_cli, ['ip', '-br', 'addr'])).contains('10.200.0.2'));
    _check('ping through the tunnel', await _ping('10.200.0.1'));
    final transfer = await _ns(_srv, ['wg', 'show', 'wg0', 'transfer']);
    _check('server counted encrypted traffic', RegExp(r'\s[1-9]\d*\s+[1-9]\d*').hasMatch(transfer), transfer.trim());
    await Future<void>.delayed(const Duration(seconds: 2));
    _check('helper reported data counts', plain.events.any((e) => e is HelperData && e.received > 0));
    await plain.stop();
    _check('helper reported the network restored', plain.events.contains(const HelperNetworkRestored()));
    _check('no tunnel rules left', !(await _rules()).contains('lookup $kRouteTable'));
    _check('tun device removed', !(await _ns(_cli, ['ip', '-br', 'link'])).contains('tun'));

    // 2. Rule groups: an excluded address leaves by the normal network.
    stdout.writeln('== excluded route');
    final group = RuleGroup.create('netns').copyWith(excluded: const ['10.200.0.3/32']);
    final routes = await ruleRoutes(<RuleGroup>[group], resolve: (_) async => <String>[]);
    final excluded = await _Helper.start(helper, applyRuleRoutes(base, routes));
    _check('connected', await excluded.connected);
    _check('ping through the tunnel', await _ping('10.200.0.1'));
    final routeExcluded = await _ns(_cli, ['ip', 'route', 'get', '10.200.0.3']);
    _check('excluded address does not use the tunnel', !routeExcluded.contains('dev tun'), routeExcluded.trim());
    final routeIncluded = await _ns(_cli, ['ip', 'route', 'get', '10.200.0.1']);
    _check('tunnel address uses the tunnel', routeIncluded.contains('dev tun'), routeIncluded.trim());
    await excluded.stop();

    // 3. Kill switch: traffic outside the tunnel is dropped while connected,
    //    stays dropped when the helper is killed (fails closed), and
    //    `--cleanup` (what the app runs then) lets it through again.
    stdout.writeln('== kill switch and --cleanup');
    _check('outside traffic flows without the kill switch', await _ping('10.99.0.1'));
    final guarded = await _Helper.start(helper, base.withBehavior(includesAllNetworks: true));
    _check('connected', await guarded.connected);
    _check('nftables table present', (await _ns(_cli, ['nft', 'list', 'tables'])).contains(kNftTable));
    _check('ping through the tunnel', await _ping('10.200.0.1'));
    _check('outside traffic dropped', !await _ping('10.99.0.1'));
    await guarded.kill();
    _check('killed helper did not restore', !guarded.events.contains(const HelperNetworkRestored()));
    _check('kill switch still blocks after the helper died', !await _ping('10.99.0.1'));
    final cleanup = await _ns(_cli, [helper, '--cleanup']);
    _check('--cleanup reported the network restored', cleanup.contains(const HelperNetworkRestored().encode()));
    _check('nftables table removed', !(await _ns(_cli, ['nft', 'list', 'tables'])).contains(kNftTable));
    _check('no tunnel rules left', !(await _rules()).contains('lookup $kRouteTable'));
    _check('outside traffic flows again', await _ping('10.99.0.1'));
  } catch (error) {
    _check('test run completed', false, '$error');
  } finally {
    await _teardown();
    final hostAfter = await _hostSnapshot();
    _check('host rules, routes and nftables tables unchanged', hostAfter == hostBefore);
    stdout.writeln(_failures == 0 ? 'ALL PASSED' : '$_failures FAILED');
    if (_failures > 0) exitCode = 1;
  }
}

void _check(String what, bool ok, [String? detail]) {
  if (!ok) _failures++;
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $what${!ok && detail != null ? '  ($detail)' : ''}');
}

/// Runs a command as root, inside [namespace] when given; returns stdout.
Future<String> _root(List<String> command, {String? namespace, String? input, bool check = true}) async {
  final full = [..._sudo, if (namespace != null) ...['ip', 'netns', 'exec', namespace], ...command];
  final process = await Process.start(full.first, full.skip(1).toList());
  if (input != null) process.stdin.write(input);
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  if (check && code != 0) throw StateError('${command.join(' ')} failed ($code): ${await err}');
  return out;
}

Future<String> _ns(String namespace, List<String> command) => _root(command, namespace: namespace, check: false);
Future<String> _rules() async => '${await _ns(_cli, ['ip', '-4', 'rule'])}${await _ns(_cli, ['ip', '-6', 'rule'])}';

Future<bool> _ping(String address) async {
  final full = [..._sudo, 'ip', 'netns', 'exec', _cli, 'ping', '-c', '2', '-W', '2', address];
  final result = await Process.run(full.first, full.skip(1).toList());
  return result.exitCode == 0;
}

Future<String> _hostSnapshot() async => [
  await _root(['ip', '-4', 'rule'], check: false),
  await _root(['ip', '-6', 'rule'], check: false),
  await _root(['ip', 'route'], check: false),
  await _root(['nft', 'list', 'tables'], check: false),
].join('\n');

/// Namespaces, the veth link and a dead-end default route on the client; the
/// server's WireGuard device. Returns the server's public key.
Future<String> _setUp() async {
  await _root(['ip', 'netns', 'add', _srv]);
  await _root(['ip', 'netns', 'add', _cli]);
  // An empty resolv.conf for the client namespace, so nothing can reach the host's.
  await _root(['mkdir', '-p', '/etc/netns/$_cli']);
  await _root(['tee', '/etc/netns/$_cli/resolv.conf'], input: '# netns test\n');
  await _root(['ip', '-n', _srv, 'link', 'add', 'veth-s', 'type', 'veth', 'peer', 'name', 'veth-c', 'netns', _cli]);
  await _root(['ip', '-n', _srv, 'addr', 'add', '10.99.0.1/24', 'dev', 'veth-s']);
  await _root(['ip', '-n', _cli, 'addr', 'add', '10.99.0.2/24', 'dev', 'veth-c']);
  for (final ns in [_srv, _cli]) {
    await _root(['ip', '-n', ns, 'link', 'set', 'lo', 'up']);
  }
  await _root(['ip', '-n', _srv, 'link', 'set', 'veth-s', 'up']);
  await _root(['ip', '-n', _cli, 'link', 'set', 'veth-c', 'up']);
  // Partout waits for a usable network (a default route) before it connects.
  // The default route goes to a dummy device, a dead end: only the tunnel can
  // reach 10.200.0.0/24, so a ping that answers went through WireGuard.
  // (A veth pair with both ends in the client namespace and nobody at the
  // gateway address: some kernels have no dummy device type.)
  await _root(['ip', '-n', _cli, 'link', 'add', 'dead0', 'type', 'veth', 'peer', 'name', 'dead1']);
  await _root(['ip', '-n', _cli, 'addr', 'add', '10.98.0.2/24', 'dev', 'dead0']);
  await _root(['ip', '-n', _cli, 'link', 'set', 'dead0', 'up']);
  await _root(['ip', '-n', _cli, 'link', 'set', 'dead1', 'up']);
  await _root(['ip', '-n', _cli, 'route', 'add', 'default', 'via', '10.98.0.1', 'dev', 'dead0']);

  final kernel = await Process.run(_sudo.isEmpty ? 'ip' : 'sudo', [
    ..._sudo.skip(1), if (_sudo.isNotEmpty) 'ip', '-n', _srv, 'link', 'add', 'wg0', 'type', 'wireguard',
  ]);
  if (kernel.exitCode != 0) {
    final wireguardGo = Platform.environment['WG_GO'] ?? 'wireguard-go';
    stdout.writeln('server: no kernel WireGuard, using $wireguardGo');
    final command = [..._sudo, 'ip', 'netns', 'exec', _srv, wireguardGo, '-f', 'wg0'];
    _wireguardGo = await Process.start(command.first, command.skip(1).toList());
    // Configured through its control socket, which appears after the device.
    for (var i = 0; i < 50 && !File('/var/run/wireguard/wg0.sock').existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } else {
    stdout.writeln('server: kernel WireGuard');
  }
  final serverKey = (await _root(['wg', 'genkey'])).trim();
  _serverKey = serverKey;
  return (await _root(['wg', 'pubkey'], input: '$serverKey\n')).trim();
}

String? _serverKey;

Future<void> _configureServer(String clientPublic) async {
  // The private key goes to wg on stdin, never into a file.
  await _root([
    'wg', 'set', 'wg0', 'private-key', '/dev/stdin', 'listen-port', '51820',
    'peer', clientPublic, 'allowed-ips', '10.200.0.2/32',
  ], namespace: _srv, input: '$_serverKey\n');
  await _root(['ip', '-n', _srv, 'addr', 'add', '10.200.0.1/24', 'dev', 'wg0']);
  await _root(['ip', '-n', _srv, 'link', 'set', 'wg0', 'up']);
}

Future<void> _teardown() async {
  if (_wireguardGo case final process?) {
    process.kill();
    await process.exitCode;
  }
  _wireguardGo = null;
  await _root(['ip', 'netns', 'pids', _cli], check: false).then((pids) async {
    for (final pid in pids.split('\n').where((p) => p.trim().isNotEmpty)) {
      await _root(['kill', '-9', pid.trim()], check: false);
    }
  });
  await _root(['ip', 'netns', 'del', _srv], check: false);
  await _root(['ip', 'netns', 'del', _cli], check: false);
  await _root(['rm', '-rf', '/etc/netns/$_cli'], check: false);
}

/// One helper run inside the client namespace, profile on stdin.
class _Helper {
  _Helper._(this._process);
  final Process _process;
  final events = <HelperEvent>[];
  final _connected = Completer<bool>();
  final _done = Completer<void>();

  Future<bool> get connected => _connected.future.timeout(const Duration(seconds: 30), onTimeout: () => false);

  static Future<_Helper> start(String helper, TunnelProfile profile) async {
    final command = [..._sudo, 'ip', 'netns', 'exec', _cli, helper, '--stdin'];
    final run = _Helper._(await Process.start(command.first, command.skip(1).toList()));
    run._process.stdin.writeln(profile.encode());
    await run._process.stdin.flush();
    run._process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      try {
        final event = parseTunnelLine(line);
        run.events.add(event);
        if (_verbose) stdout.writeln('   < $line');
        if (event == const HelperStatus(TunnelStatus.connected) && !run._connected.isCompleted) {
          run._connected.complete(true);
        }
        if (event is HelperError) stdout.writeln('   helper error: ${event.code}');
      } on FormatException {
        stdout.writeln('   invalid helper line');
      }
    }, onDone: () {
      if (!run._connected.isCompleted) run._connected.complete(false);
      run._done.complete();
    });
    run._process.stderr.drain<void>();
    return run;
  }

  /// Asks the helper to stop, the way the app does.
  Future<void> stop() async {
    _process.stdin.writeln('stop');
    await _process.stdin.flush();
    await _done.future.timeout(const Duration(seconds: 20));
    await _process.exitCode;
  }

  /// SIGKILL: no chance to undo anything, like a crash.
  Future<void> kill() async {
    final pids = await _root(['ip', 'netns', 'pids', _cli], check: false);
    for (final pid in pids.split('\n').where((p) => p.trim().isNotEmpty)) {
      final exe = await _root(['readlink', '/proc/${pid.trim()}/exe'], check: false);
      if (exe.contains('partout-tunnel')) await _root(['kill', '-9', pid.trim()], check: false);
    }
    await _done.future.timeout(const Duration(seconds: 20));
  }
}
