// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/domain/wireguard_validation.dart';

const String _key = 'muwialz9E36nXp9qgbGIxwMrH+5Ovr8d7cutH8JHdvE=';
const String _otherKey = '4hBza7JtPKZFKwqtEmDR0iZyru1kqpQta/DRduMbHQw=';

void main() {
  test('keys are 32 bytes of base64', () {
    expect(isWireGuardKey(_key), isTrue);
    expect(isWireGuardKey(' $_key '), isTrue);
    expect(isWireGuardKey(_key.substring(1)), isFalse);
    expect(isWireGuardKey('${_key.substring(0, 43)}!'), isFalse);
    expect(isWireGuardKey('AAAA'), isFalse);
    expect(WireGuardValidation.privateKey(''), const WireGuardIssue(.privateKeyRequired));
    expect(WireGuardValidation.privateKey('nope'), const WireGuardIssue(.privateKeyInvalid));
    expect(WireGuardValidation.publicKey(''), const WireGuardIssue(.publicKeyRequired));
    expect(WireGuardValidation.preSharedKey(''), isNull);
    expect(WireGuardValidation.preSharedKey('short'), const WireGuardIssue(.preSharedKeyInvalid));
  });

  test('address lists name the first bad entry', () {
    expect(WireGuardValidation.addresses('10.8.0.6/24, fd00::1/64'), isNull);
    expect(WireGuardValidation.addresses('10.8.0.6/24, 10.8.0.300'), const WireGuardIssue(.addressInvalid, '10.8.0.300'));
    expect(WireGuardValidation.allowedIPs('0.0.0.0/0,::/0'), isNull);
    expect(WireGuardValidation.allowedIPs('0.0.0.0/0, everything'), const WireGuardIssue(.allowedIPsInvalid, 'everything'));
    expect(WireGuardValidation.dnsServers('1.1.1.1, 2606:4700::1111'), isNull);
    expect(WireGuardValidation.dnsServers('1.1.1.1/32'), const WireGuardIssue(.dnsInvalid, '1.1.1.1/32'));
  });

  test('endpoints are host:port or [IPv6]:port', () {
    for (final good in <String>['', 'vpn.example.com:51820', '203.0.113.1:1', '[2001:db8::1]:51820', 'host-1:65535']) {
      expect(WireGuardValidation.endpoint(good), isNull, reason: good);
    }
    for (final bad in <String>['vpn.example.com', ':51820', 'vpn.example.com:0', 'vpn.example.com:65536', '2001:db8::1:51820', '[1.2.3.4]:80', 'bad host:1', 'host:12ab']) {
      expect(WireGuardValidation.endpoint(bad)?.kind, WireGuardIssueKind.endpointInvalid, reason: bad);
    }
  });

  test('numbers are in range', () {
    expect(WireGuardValidation.mtu(''), isNull);
    expect(WireGuardValidation.mtu('1420'), isNull);
    expect(WireGuardValidation.mtu('575'), const WireGuardIssue(.mtuInvalid, '575'));
    expect(WireGuardValidation.keepAlive('0'), isNull);
    expect(WireGuardValidation.keepAlive('65536'), const WireGuardIssue(.keepAliveInvalid, '65536'));
    expect(WireGuardValidation.keepAlive('x'), const WireGuardIssue(.keepAliveInvalid, 'x'));
  });

  test('a whole configuration reports each field by its editor section', () {
    final issues = WireGuardValidation.configuration(<String, dynamic>{
      'interface': <String, dynamic>{
        'privateKey': _otherKey,
        'addresses': <dynamic>['10.0.0.2/32'],
        'mtu': 100,
        'dns': <String, dynamic>{'servers': <dynamic>['1.1.1.1', 'dns.example']},
      },
      'peers': <dynamic>[
        <String, dynamic>{'publicKey': _key, 'allowedIPs': <dynamic>['0.0.0.0/0'], 'endpoint': 'fe80::1:51820'},
        <String, dynamic>{'publicKey': _key, 'allowedIPs': <dynamic>['x'], 'keepAlive': 25},
      ],
    });
    expect(issues.keys, unorderedEquals(<String>['mtu', 'dns-servers', 'peer-2-public-key', 'peer-2-allowed-ips']));
    expect(issues['peer-2-public-key'], const WireGuardIssue(.publicKeyDuplicated));
    expect(WireGuardValidation.configuration(null), isEmpty);
  });
}
