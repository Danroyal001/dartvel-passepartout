// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/domain/ip_ranges.dart';

void main() {
  group('IpAddress', () {
    test('parses IPv4 and IPv6 literals strictly', () {
      expect(IpAddress.tryParse('10.0.0.1')!.isIPv4, isTrue);
      expect(IpAddress.tryParse('2001:db8::1')!.isIPv4, isFalse);
      expect(IpAddress.tryParse('::')!.canonical, '::');
      expect(IpAddress.tryParse('::ffff:1.2.3.4')!.canonical, '::ffff:102:304');
      expect(IpAddress.tryParse('2001:0DB8:0000:0000:0000:0000:0000:0001')!.canonical, '2001:db8::1');
      expect(IpAddress.tryParse('1:0:0:2:0:0:0:3')!.canonical, '1:0:0:2::3');
      for (final bad in <String>['', '256.1.1.1', '1.2.3', '1.2.3.4.5', 'example.com', '1::2::3', 'fe80::1%eth0', '12345::', '1:2:3:4:5:6:7:8:9', ':::']) {
        expect(IpAddress.tryParse(bad), isNull, reason: bad);
      }
    });

    test('blocks carry a prefix that fits the family', () {
      expect(IpBlock.tryParse('10.1.2.3')!.toString(), '10.1.2.3/32');
      expect(IpBlock.tryParse(' fd00::1/64 ')!.toString(), 'fd00::1/64');
      expect(IpBlock.tryParse('10.0.0.0/33'), isNull);
      expect(IpBlock.tryParse('::/129'), isNull);
      expect(IpBlock.tryParse('10.0.0.0/'), isNull);
      expect(IpBlock.tryParse('10.0.0.0/-1'), isNull);
    });
  });

  group('IPv4 arithmetic', () {
    test('ranges and minimal CIDR covers', () {
      expect(ipv4Range('10.1.2.3/8'), (first: 0x0a000000, last: 0x0affffff));
      expect(ipv4RangeToCidrs((first: 0, last: 0xffffffff)), <String>['0.0.0.0/0']);
      expect(ipv4RangeToCidrs((first: 0x0a000001, last: 0x0a000006)), <String>['10.0.0.1/32', '10.0.0.2/31', '10.0.0.4/31', '10.0.0.6/32']);
      expect(subtractIpv4('10.0.0.0/8', <String>['10.0.0.0/9']), <String>['10.128.0.0/9']);
      expect(subtractIpv4('10.0.0.0/8', <String>['192.168.0.0/16']), <String>['10.0.0.0/8']);
    });

    test('public blocks and private blocks tile the whole space exactly', () {
      final ranges = <Ipv4Range>[
        ...publicIpv4Blocks.map((block) => ipv4Range(block)!),
        ...privateIpv4Blocks.map((block) => ipv4Range(block)!),
      ]..sort((a, b) => a.first.compareTo(b.first));
      var next = 0;
      for (final range in ranges) {
        expect(range.first, next, reason: 'no gap or overlap at $range');
        next = range.last + 1;
      }
      expect(next, 1 << 32);
      // Minimal: no two neighbouring blocks could merge into their parent.
      for (var i = 0; i + 1 < publicIpv4Blocks.length; i++) {
        final a = ipv4Range(publicIpv4Blocks[i])!, b = ipv4Range(publicIpv4Blocks[i + 1])!;
        final size = a.last - a.first + 1;
        final mergeable = b.first == a.last + 1 && b.last - b.first + 1 == size && a.first % (size * 2) == 0;
        expect(mergeable, isFalse, reason: '${publicIpv4Blocks[i]} + ${publicIpv4Blocks[i + 1]}');
      }
    });

    test('private address detection', () {
      for (final address in <String>['10.64.0.1', '192.168.1.1', '172.20.0.1', '169.254.1.1', '127.0.0.1', '239.1.1.1']) {
        expect(isPrivateIpv4(address), isTrue, reason: address);
      }
      for (final address in <String>['1.1.1.1', '172.32.0.1', '100.64.0.1', '::1', 'nonsense']) {
        expect(isPrivateIpv4(address), isFalse, reason: address);
      }
    });
  });

  group('PrivateIpExclusion', () {
    const allTraffic = <String>['0.0.0.0/0', '::/0'];

    test('only offered when the peer takes all IPv4 traffic', () {
      expect(PrivateIpExclusion.isAvailable(allTraffic), isTrue);
      expect(PrivateIpExclusion.isAvailable(<String>['10.0.0.0/24']), isFalse);
      expect(PrivateIpExclusion.isOn(allTraffic), isFalse);
    });

    test('turning it on replaces 0.0.0.0/0, keeps IPv6 and re-adds private DNS', () {
      final excluded = PrivateIpExclusion.excluding(allTraffic, dnsServers: <String>['10.64.0.1', '1.1.1.1', 'fd00::53']);
      expect(excluded, isNot(contains('0.0.0.0/0')));
      expect(excluded, contains('::/0'));
      expect(excluded, containsAll(publicIpv4Blocks));
      expect(excluded.last, '10.64.0.1/32', reason: 'the private resolver stays in the tunnel');
      expect(excluded.where((entry) => entry.startsWith('1.1.1.1')), isEmpty, reason: 'a public resolver is covered already');
      expect(PrivateIpExclusion.isOn(excluded), isTrue);
      expect(PrivateIpExclusion.isAvailable(excluded), isTrue);
      expect(PrivateIpExclusion.excluding(excluded), same(excluded), reason: 'idempotent');
    });

    test('turning it off restores the original list in order', () {
      const original = <String>['0.0.0.0/0', '::/0', '203.0.113.7/32'];
      const dns = <String>['10.64.0.1'];
      final excluded = PrivateIpExclusion.excluding(original, dnsServers: dns);
      expect(PrivateIpExclusion.including(excluded, dnsServers: dns), original);
      expect(PrivateIpExclusion.including(original), same(original), reason: 'nothing to undo');
    });
  });
}
