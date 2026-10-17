// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// What the Linux tunnel helper does to the network for one profile, worked
// out from the profile alone: interface addresses, MTU, routes (including
// excluded routes and the default route), DNS and the kill switch. Partout's Linux tun controller creates the tun device and
// configures nothing, so the helper does it.
//
// This file only plans: it returns `ip` argument lists and an nftables
// script. `linux_network.dart` runs them. Keeping the plan pure means every
// command is unit-tested without root.
//
// Routing model (the same idea as wg-quick, our own code):
// - Every tunnel route lives in our own routing table [kRouteTable]; the main
//   table is never edited.
// - Excluded routes are `throw` routes in that table: a lookup that hits one
//   falls through to the main table, so it leaves by the normal network.
// - Traffic to a server endpoint (UDP, its port) is sent to the main table by
//   a rule placed before the tunnel rules, so the encrypted packets never loop
//   into the tunnel. It is a routing rule, not a firewall mark, so the source
//   address is right from the first lookup and roaming keeps working.
// - With a default route in the tunnel, the main table's more specific routes
//   (the local network) still win over the tunnel's default route, but not
//   over the tunnel's own specific routes:
//     5181  not fwmark M  lookup T  suppress_prefixlength 0
//     5182  lookup main  suppress_prefixlength 0
//     5183  not fwmark M  lookup T
//   Without a default route only 5183 is added.
// - Packets with mark [kFirewallMark] skip the tunnel (reserved for per-app
//   split tunnelling, not built yet; see docs/LINUX-NETWORK.md).
//
// Flutter-free and dart:io-free.

import '../../domain/ip_ranges.dart';

/// Our routing table and firewall mark ("DV" = 0x4456).
const int kRouteTable = 0x4456;
const int kFirewallMark = 0x4456;

/// Rule priorities, in order: endpoint bypass, tunnel specifics, main
/// specifics, tunnel default.
const int kPriorityEndpoint = 5180;
const int kPriorityTunnelSpecific = 5181;
const int kPriorityMainSpecific = 5182;
const int kPriorityTunnel = 5183;
const List<int> kRulePriorities = <int>[
  kPriorityEndpoint,
  kPriorityTunnelSpecific,
  kPriorityMainSpecific,
  kPriorityTunnel,
];

/// The nftables table the helper owns (kill switch, marks). Deleting it
/// removes every firewall change the helper made.
const String kNftTable = 'dartvel_vpn';

/// Default MTUs when neither the connection nor an IP module sets one.
const int kWireGuardDefaultMtu = 1420;
const int kOpenVpnDefaultMtu = 1500;

final RegExp _interfaceName = RegExp(r'^[A-Za-z0-9_.-]{1,15}$');

/// Whether [name] is safe to pass to `ip` and nftables as an interface name.
bool isSafeInterfaceName(String name) => _interfaceName.hasMatch(name) && name != '.' && name != '..';

/// One server endpoint the encrypted traffic goes to.
final class TunnelEndpoint {
  const TunnelEndpoint(this.address, this.port);

  /// An IP literal (resolved before connecting).
  final IpAddress address;
  final int port;

  /// `host:port` or `[v6]:port`, as WireGuard writes it.
  static ({String host, int port})? split(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('[')) {
      final close = trimmed.indexOf(']');
      if (close < 0 || close + 2 > trimmed.length || trimmed[close + 1] != ':') return null;
      final port = int.tryParse(trimmed.substring(close + 2));
      if (port == null || port < 1 || port > 65535) return null;
      return (host: trimmed.substring(1, close), port: port);
    }
    final colon = trimmed.lastIndexOf(':');
    if (colon <= 0 || trimmed.indexOf(':') != colon) return null;
    final port = int.tryParse(trimmed.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return (host: trimmed.substring(0, colon), port: port);
  }

  String get joined => address.isIPv4 ? '${address.canonical}:$port' : '[${address.canonical}]:$port';

  @override
  bool operator ==(Object other) =>
      other is TunnelEndpoint && other.address.canonical == address.canonical && other.port == port;

  @override
  int get hashCode => Object.hash(address.canonical, port);
}

/// Everything the helper applies for one profile.
final class LinuxNetworkPlan {
  LinuxNetworkPlan({
    required this.addresses,
    required this.mtu,
    required this.includedV4,
    required this.includedV6,
    required this.excludedV4,
    required this.excludedV6,
    required this.dnsServers,
    required this.searchDomains,
    required this.endpoints,
    required this.killSwitch,
    required this.warnings,
  });

  /// Interface addresses with their prefix as configured.
  final List<IpBlock> addresses;
  final int mtu;

  /// Network-normalised routes through the tunnel (a default route is
  /// `0.0.0.0/0` / `::/0`).
  final List<IpBlock> includedV4;
  final List<IpBlock> includedV6;

  /// Network-normalised routes kept out of the tunnel.
  final List<IpBlock> excludedV4;
  final List<IpBlock> excludedV6;

  final List<IpAddress> dnsServers;
  final List<String> searchDomains;
  final List<TunnelEndpoint> endpoints;

  /// "Enforce tunnel" (`behavior.includesAllNetworks`): block everything that
  /// does not go through the tunnel.
  final bool killSwitch;

  /// What could not be applied, in words for the log.
  final List<String> warnings;

  bool get defaultV4 => includedV4.any((block) => block.isDefault);
  bool get defaultV6 => includedV6.any((block) => block.isDefault);
  bool get hasV4 => includedV4.isNotEmpty;
  bool get hasV6 => includedV6.isNotEmpty;

  /// True when this plan configures the interface at all (it has addresses).
  bool get configuresInterface => addresses.isNotEmpty;

  /// Whether all DNS should go through the tunnel's resolvers (`~.`).
  bool get routesAllDns => defaultV4 || defaultV6;

  /// Builds the plan from a profile's JSON (Partout's schema). Endpoints that
  /// are host names are skipped here: resolve them first with
  /// [withResolvedEndpoints].
  static LinuxNetworkPlan fromProfile(Map<String, dynamic> profile) {
    final active = <String>{...?(profile['activeModulesIds'] as List?)?.map((id) => '$id')};
    final modules = <Map<String, dynamic>>[
      for (final module in (profile['modules'] as List?) ?? const <dynamic>[])
        if (module is Map && module['value'] is Map && active.contains('${(module['value'] as Map)['id']}'))
          <String, dynamic>{'type': module['type'], 'value': (module['value'] as Map).cast<String, dynamic>()},
    ];
    final warnings = <String>[];
    final addresses = <IpBlock>[];
    final includedV4 = <IpBlock>[], includedV6 = <IpBlock>[], excludedV4 = <IpBlock>[], excludedV6 = <IpBlock>[];
    final dnsServers = <IpAddress>[];
    final searchDomains = <String>[];
    final endpoints = <TunnelEndpoint>[];
    int? mtu;
    var defaultMtu = kWireGuardDefaultMtu;

    void addUnique<T>(List<T> list, T value) {
      if (!list.contains(value)) list.add(value);
    }

    void addRoute(Object? destination, {required bool included, bool? familyV4}) {
      IpBlock? block;
      if (destination == null) {
        if (familyV4 == null) return;
        block = IpBlock.tryParse(familyV4 ? '0.0.0.0/0' : '::/0');
      } else {
        block = IpBlock.tryParse('$destination')?.network;
      }
      if (block == null) {
        warnings.add('Skipped route "$destination": not an IP block');
        return;
      }
      final list = block.isIPv4 ? (included ? includedV4 : excludedV4) : (included ? includedV6 : excludedV6);
      addUnique(list, block);
    }

    void addDns(Map<String, dynamic> dns) {
      final protocol = (dns['protocolType'] as Map?)?['type'];
      if (protocol != null && protocol != 'cleartext') {
        warnings.add('DNS over $protocol is not applied on Linux; using its server addresses as plain DNS');
      }
      for (final server in (dns['servers'] as List?) ?? const <dynamic>[]) {
        final address = IpAddress.tryParse('$server');
        if (address == null) {
          warnings.add('Skipped DNS server "$server"');
        } else if (!dnsServers.any((known) => known.canonical == address.canonical)) {
          dnsServers.add(address);
        }
      }
      final domainName = dns['domainName'];
      for (final domain in <Object?>[?domainName, ...?(dns['searchDomains'] as List?)]) {
        final text = '$domain'.trim().toLowerCase();
        if (_dnsName.hasMatch(text)) {
          addUnique(searchDomains, text);
        } else {
          warnings.add('Skipped search domain "$domain"');
        }
      }
    }

    for (final module in modules) {
      final value = module['value'] as Map<String, dynamic>;
      switch (module['type']) {
        case 'WireGuard':
          final configuration = (value['configuration'] as Map?)?.cast<String, dynamic>() ?? const {};
          final interface = (configuration['interface'] as Map?)?.cast<String, dynamic>() ?? const {};
          for (final address in (interface['addresses'] as List?) ?? const <dynamic>[]) {
            final block = IpBlock.tryParse('$address');
            if (block == null) {
              warnings.add('Skipped interface address "$address"');
            } else {
              addUnique(addresses, block);
            }
          }
          final wgMtu = interface['mtu'];
          if (wgMtu is int && wgMtu > 0) mtu ??= wgMtu;
          if (interface['dns'] is Map) addDns((interface['dns'] as Map).cast<String, dynamic>());
          for (final peer in (configuration['peers'] as List?) ?? const <dynamic>[]) {
            if (peer is! Map) continue;
            for (final allowed in (peer['allowedIPs'] as List?) ?? const <dynamic>[]) {
              addRoute(allowed, included: true);
            }
            final endpoint = peer['endpoint'];
            if (endpoint is String) {
              final parts = TunnelEndpoint.split(endpoint);
              final address = parts == null ? null : IpAddress.tryParse(parts.host);
              if (address == null) {
                warnings.add('Endpoint "$endpoint" is not an IP address; it was not resolved before connecting');
              } else {
                addUnique(endpoints, TunnelEndpoint(address, parts!.port));
              }
            }
          }
        case 'OpenVPN':
          defaultMtu = kOpenVpnDefaultMtu;
          warnings.add(
            'OpenVPN on Linux: the server-pushed addresses, routes and DNS are not available to the helper '
            "(Partout's Linux tun controller does not pass them on). Only this profile's IP and DNS modules are applied.",
          );
        case 'IP':
          final ipMtu = value['mtu'];
          if (ipMtu is int && ipMtu > 0) mtu = ipMtu; // an IP module overrides the connection's MTU
          for (final family in <(String, bool)>[('ipv4', true), ('ipv6', false)]) {
            final settings = (value[family.$1] as Map?)?.cast<String, dynamic>();
            if (settings == null) continue;
            for (final subnet in (settings['subnets'] as List?) ?? const <dynamic>[]) {
              final block = IpBlock.tryParse('$subnet');
              if (block != null) addUnique(addresses, block);
            }
            for (final route in (settings['includedRoutes'] as List?) ?? const <dynamic>[]) {
              if (route is Map) addRoute(route['destination'], included: true, familyV4: family.$2);
            }
            for (final route in (settings['excludedRoutes'] as List?) ?? const <dynamic>[]) {
              if (route is Map) addRoute(route['destination'], included: false, familyV4: family.$2);
            }
          }
        case 'DNS':
          addDns(value);
      }
    }

    final behavior = profile['behavior'];
    final killSwitch = behavior is Map && behavior['includesAllNetworks'] == true;

    return LinuxNetworkPlan(
      addresses: addresses,
      mtu: mtu ?? defaultMtu,
      includedV4: includedV4,
      includedV6: includedV6,
      excludedV4: excludedV4,
      excludedV6: excludedV6,
      dnsServers: dnsServers,
      searchDomains: searchDomains,
      endpoints: endpoints,
      killSwitch: killSwitch,
      warnings: warnings,
    );
  }

  /// `ip` commands for the routing policy, run before the engine starts (they
  /// do not depend on the tun device). [cleanupCommands] removes them.
  List<List<String>> policyCommands() {
    final commands = <List<String>>[];
    for (final family in _families) {
      final flag = family.v4 ? '-4' : '-6';
      for (final block in family.excluded) {
        commands.add(<String>[flag, 'route', 'replace', 'throw', '$block', 'table', '$kRouteTable']);
      }
      for (final endpoint in endpoints.where((endpoint) => endpoint.address.isIPv4 == family.v4)) {
        commands.add(<String>[
          flag, 'rule', 'add', 'to', '${endpoint.address.canonical}/${family.v4 ? 32 : 128}', //
          'ipproto', 'udp', 'dport', '${endpoint.port}', 'lookup', 'main', 'priority', '$kPriorityEndpoint',
        ]);
      }
      final notMarked = <String>['not', 'fwmark', '0x${kFirewallMark.toRadixString(16)}'];
      if (family.hasDefault) {
        commands
          ..add(<String>[flag, 'rule', 'add', ...notMarked, 'lookup', '$kRouteTable', 'suppress_prefixlength', '0', //
            'priority', '$kPriorityTunnelSpecific'])
          ..add(<String>[flag, 'rule', 'add', 'lookup', 'main', 'suppress_prefixlength', '0', //
            'priority', '$kPriorityMainSpecific']);
      }
      commands.add(<String>[flag, 'rule', 'add', ...notMarked, 'lookup', '$kRouteTable', 'priority', '$kPriorityTunnel']);
    }
    return commands;
  }

  /// `ip` commands for the tun device once it exists. Run again whenever the
  /// engine replaces the device.
  List<List<String>> linkCommands(String device) {
    if (!isSafeInterfaceName(device)) throw ArgumentError.value(device, 'device', 'unsafe interface name');
    final commands = <List<String>>[
      <String>['link', 'set', 'dev', device, 'mtu', '$mtu'],
      for (final address in addresses)
        <String>[address.isIPv4 ? '-4' : '-6', 'addr', 'replace', '$address', 'dev', device, if (!address.isIPv4) 'nodad'],
      <String>['link', 'set', 'dev', device, 'up'],
    ];
    for (final family in _families) {
      for (final block in family.included) {
        commands.add(<String>[
          family.v4 ? '-4' : '-6', 'route', 'replace', //
          if (block.isDefault) 'default' else '$block', 'dev', device, 'table', '$kRouteTable',
        ]);
      }
    }
    return commands;
  }

  /// The nftables script for this plan, or null when nothing needs the
  /// firewall. [device] is the tun device when it exists. The script replaces
  /// the whole [kNftTable] atomically.
  String? nftScript(String? device) {
    if (device != null && !isSafeInterfaceName(device)) {
      throw ArgumentError.value(device, 'device', 'unsafe interface name');
    }
    final antiSpoof = device != null && configuresInterface;
    if (!killSwitch && !antiSpoof) return null;
    final buffer = StringBuffer()
      ..writeln('table inet $kNftTable')
      ..writeln('delete table inet $kNftTable')
      ..writeln('table inet $kNftTable {');
    if (antiSpoof) {
      // Like wg-quick: nothing outside the tunnel may send to our tunnel address.
      buffer.writeln('  chain preraw {\n    type filter hook prerouting priority raw; policy accept;');
      for (final address in addresses) {
        final family = address.isIPv4 ? 'ip' : 'ip6';
        buffer.writeln('    iifname != "$device" $family daddr ${address.address.canonical} fib saddr type != local drop');
      }
      buffer.writeln('  }');
    }
    if (killSwitch) {
      buffer
        ..writeln('  chain killswitch {\n    type filter hook output priority filter; policy accept;')
        ..writeln('    oifname "lo" accept');
      if (device != null) buffer.writeln('    oifname "$device" accept');
      for (final endpoint in endpoints) {
        final family = endpoint.address.isIPv4 ? 'ip' : 'ip6';
        buffer.writeln('    $family daddr ${endpoint.address.canonical} udp dport ${endpoint.port} accept');
      }
      for (final block in excludedV4) {
        buffer.writeln('    ip daddr $block accept');
      }
      for (final block in excludedV6) {
        buffer.writeln('    ip6 daddr $block accept');
      }
      buffer
        ..writeln('    udp sport 68 udp dport 67 accept')
        ..writeln('    udp sport 546 udp dport 547 accept')
        ..writeln('    icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept')
        ..writeln('    counter reject with icmpx type admin-prohibited\n  }');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  /// `resolvectl` argument lists for [device] (systemd-resolved, per link).
  List<List<String>> resolvectlCommands(String device) {
    if (!isSafeInterfaceName(device)) throw ArgumentError.value(device, 'device', 'unsafe interface name');
    if (dnsServers.isEmpty) return const <List<String>>[];
    return <List<String>>[
      <String>['dns', device, ...dnsServers.map((server) => server.canonical)],
      <String>['domain', device, ...searchDomains, if (routesAllDns) '~.'],
      <String>['default-route', device, routesAllDns ? 'true' : 'false'],
    ];
  }

  /// A resolv.conf for systems without systemd-resolved.
  String? resolvConf() {
    if (dnsServers.isEmpty) return null;
    final buffer = StringBuffer('# Written by the Dartvel VPN tunnel helper; restored when the tunnel stops.\n');
    for (final server in dnsServers.take(3)) {
      buffer.writeln('nameserver ${server.canonical}');
    }
    if (searchDomains.isNotEmpty) buffer.writeln('search ${searchDomains.join(' ')}');
    return buffer.toString();
  }

  Iterable<({bool v4, List<IpBlock> included, List<IpBlock> excluded, bool hasDefault})> get _families sync* {
    if (hasV4 || excludedV4.isNotEmpty) {
      yield (v4: true, included: includedV4, excluded: excludedV4, hasDefault: defaultV4);
    }
    if (hasV6 || excludedV6.isNotEmpty) {
      yield (v4: false, included: includedV6, excluded: excludedV6, hasDefault: defaultV6);
    }
  }
}

final RegExp _dnsName = RegExp(r'^(?=.{1,253}$)([a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9])?\.)*[a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9])?\.?$');

/// [profile] with every WireGuard peer endpoint host name replaced by the
/// address [resolve] returns for it (the first one), so the engine and the
/// routing rules use the same address. Endpoints that are already literals,
/// or that do not resolve, are left as they are.
Future<Map<String, dynamic>> withResolvedEndpoints(
  Map<String, dynamic> profile,
  Future<List<String>> Function(String host) resolve,
) async {
  final copy = _deepCopy(profile) as Map<String, dynamic>;
  for (final module in (copy['modules'] as List?) ?? const <dynamic>[]) {
    if (module is! Map || module['type'] != 'WireGuard') continue;
    final peers = (((module['value'] as Map?)?['configuration'] as Map?)?['peers'] as List?) ?? const <dynamic>[];
    for (final peer in peers) {
      if (peer is! Map || peer['endpoint'] is! String) continue;
      final parts = TunnelEndpoint.split(peer['endpoint'] as String);
      if (parts == null || IpAddress.tryParse(parts.host) != null) continue;
      final addresses = <IpAddress>[
        for (final text in await resolve(parts.host)) ?IpAddress.tryParse(text),
      ];
      if (addresses.isEmpty) continue;
      // Prefer IPv4, as wg-quick's resolver order usually does.
      final chosen = addresses.firstWhere((address) => address.isIPv4, orElse: () => addresses.first);
      peer['endpoint'] = TunnelEndpoint(chosen, parts.port).joined;
    }
  }
  return copy;
}

Object? _deepCopy(Object? value) => switch (value) {
      Map() => <String, dynamic>{for (final entry in value.entries) '${entry.key}': _deepCopy(entry.value)},
      List() => <dynamic>[for (final entry in value) _deepCopy(entry)],
      _ => value,
    };
