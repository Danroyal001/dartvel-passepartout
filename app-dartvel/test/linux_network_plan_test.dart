// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/platform/tunnel/linux_network_plan.dart';

Map<String, dynamic> _profile({
  List<String> allowed = const ['10.200.0.0/24'],
  List<String> addresses = const ['10.200.0.2/32', 'fd00::2/128'],
  String endpoint = '10.96.0.1:51820',
  bool killSwitch = false,
  List<String> excluded = const [],
  Map<String, dynamic>? dns,
  int? mtu,
}) =>
    <String, dynamic>{
      'id': 'p',
      'name': 'p',
      'activeModulesIds': ['wg', 'ip'],
      'behavior': {'disconnectsOnSleep': false, 'includesAllNetworks': killSwitch},
      'modules': [
        {
          'type': 'WireGuard',
          'value': {
            'id': 'wg',
            'configuration': {
              'interface': {'privateKey': 'k', 'addresses': addresses, 'dns': ?dns, 'mtu': ?mtu},
              'peers': [
                {'publicKey': 'p', 'endpoint': endpoint, 'allowedIPs': allowed},
              ],
            },
          },
        },
        {
          'type': 'IP',
          'value': {
            'id': 'ip',
            'ipv4': {
              'subnets': [],
              'includedRoutes': [],
              'excludedRoutes': [for (final route in excluded) {'destination': route}],
            },
          },
        },
        // Inactive: ignored.
        {
          'type': 'IP',
          'value': {
            'id': 'off',
            'ipv4': {
              'subnets': [],
              'includedRoutes': [
                {'destination': '1.2.3.0/24'},
              ],
              'excludedRoutes': [],
            },
          },
        },
      ],
    };

Matcher has(List<String> command) => anyElement(equals(command));

void main() {
  test('split tunnel: addresses, MTU default, routes in our table only', () {
    final plan = LinuxNetworkPlan.fromProfile(_profile());
    expect(plan.addresses.map((block) => '$block'), ['10.200.0.2/32', 'fd00::2/128']);
    expect(plan.mtu, kWireGuardDefaultMtu);
    expect(plan.includedV4.map((block) => '$block'), ['10.200.0.0/24']);
    expect(plan.defaultV4, isFalse);
    expect(plan.policyCommands(), [
      ['-4', 'rule', 'add', 'to', '10.96.0.1/32', 'ipproto', 'udp', 'dport', '51820', 'lookup', 'main', 'priority', '5180'],
      ['-4', 'rule', 'add', 'not', 'fwmark', '0x4456', 'lookup', '17494', 'priority', '5183'],
    ]);
    final link = plan.linkCommands('tun0');
    expect(link.first, ['link', 'set', 'dev', 'tun0', 'mtu', '1420']);
    expect(link, has(['-6', 'addr', 'replace', 'fd00::2/128', 'dev', 'tun0', 'nodad']));
    expect(link, has(['-4', 'route', 'replace', '10.200.0.0/24', 'dev', 'tun0', 'table', '17494']));
    // No kill switch: only the anti-spoofing chain once the device exists.
    expect(plan.nftScript(null), isNull);
    expect(plan.nftScript('tun0'), contains('iifname != "tun0" ip daddr 10.200.0.2 fib saddr type != local drop'));
    expect(plan.nftScript('tun0'), isNot(contains('killswitch')));
  });

  test('default route: wg-quick style rules, excluded routes throw, host bits cleared', () {
    final plan = LinuxNetworkPlan.fromProfile(
      _profile(allowed: ['0.0.0.0/0', '::/0'], excluded: ['10.97.0.5/32', '192.168.1.7/24'], mtu: 1380),
    );
    expect(plan.defaultV4 && plan.defaultV6, isTrue);
    expect(plan.mtu, 1380);
    final commands = plan.policyCommands();
    expect(commands, has(['-4', 'route', 'replace', 'throw', '10.97.0.5/32', 'table', '17494']));
    expect(commands, has(['-4', 'route', 'replace', 'throw', '192.168.1.0/24', 'table', '17494']));
    expect(commands, has(['-4', 'rule', 'add', 'not', 'fwmark', '0x4456', 'lookup', '17494', 'suppress_prefixlength', '0', 'priority', '5181']));
    expect(commands, has(['-4', 'rule', 'add', 'lookup', 'main', 'suppress_prefixlength', '0', 'priority', '5182']));
    expect(commands, has(['-6', 'rule', 'add', 'not', 'fwmark', '0x4456', 'lookup', '17494', 'priority', '5183']));
    expect(plan.linkCommands('tun0'), has(['-4', 'route', 'replace', 'default', 'dev', 'tun0', 'table', '17494']));
    expect(plan.linkCommands('tun0'), has(['-6', 'route', 'replace', 'default', 'dev', 'tun0', 'table', '17494']));
  });

  test('kill switch allows only the tunnel, endpoint, excluded routes, DHCP and NDP', () {
    final plan = LinuxNetworkPlan.fromProfile(_profile(allowed: ['0.0.0.0/0'], excluded: ['10.97.0.5/32'], killSwitch: true));
    final script = plan.nftScript('tun0')!;
    expect(script, startsWith('table inet dartvel_vpn\ndelete table inet dartvel_vpn\n'));
    expect(script, contains('oifname "tun0" accept'));
    expect(script, contains('ip daddr 10.96.0.1 udp dport 51820 accept'));
    expect(script, contains('ip daddr 10.97.0.5/32 accept'));
    expect(script, contains('counter reject with icmpx type admin-prohibited'));
    // Before the engine opens the device everything but the endpoint is blocked.
    expect(plan.nftScript(null), isNot(contains('oifname "tun')));
  });

  test('DNS: resolved per link with ~. for a full tunnel, resolv.conf fallback', () {
    final plan = LinuxNetworkPlan.fromProfile(_profile(
      allowed: ['0.0.0.0/0'],
      dns: {
        'id': 'd',
        'protocolType': {'type': 'cleartext'},
        'servers': ['10.200.0.1', 'bad'],
        'searchDomains': ['Example.LAN'],
      },
    ));
    expect(plan.resolvectlCommands('tun0'), [
      ['dns', 'tun0', '10.200.0.1'],
      ['domain', 'tun0', 'example.lan', '~.'],
      ['default-route', 'tun0', 'true'],
    ]);
    expect(plan.resolvConf(), contains('nameserver 10.200.0.1\nsearch example.lan\n'));
    expect(plan.warnings.single, contains('"bad"'));
  });

  test('unsafe interface names are refused', () {
    final plan = LinuxNetworkPlan.fromProfile(_profile());
    expect(() => plan.linkCommands('tun0; rm'), throwsArgumentError);
    expect(() => plan.nftScript('a"b'), throwsArgumentError);
  });

  test('endpoint host names are resolved into the engine copy', () async {
    final source = _profile(endpoint: 'vpn.example.com:51820');
    final resolved = await withResolvedEndpoints(source, (host) async => ['2001:db8::1', '198.51.100.7']);
    final peers = resolved['modules'][0]['value']['configuration']['peers'] as List;
    expect(peers.single['endpoint'], '198.51.100.7:51820');
    expect((source['modules'] as List)[0]['value']['configuration']['peers'][0]['endpoint'], 'vpn.example.com:51820');
    expect(LinuxNetworkPlan.fromProfile(resolved).endpoints.single.joined, '198.51.100.7:51820');
    expect(TunnelEndpoint.split('[2001:db8::1]:443'), (host: '2001:db8::1', port: 443));
  });

  test('OpenVPN profiles warn that pushed settings are not applied', () {
    final plan = LinuxNetworkPlan.fromProfile({
      'activeModulesIds': ['o'],
      'modules': [
        {'type': 'OpenVPN', 'value': {'id': 'o'}},
      ],
    });
    expect(plan.configuresInterface, isFalse);
    expect(plan.mtu, kOpenVpnDefaultMtu);
    expect(plan.warnings.single, contains('OpenVPN'));
  });
}
