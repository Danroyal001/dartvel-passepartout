// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// IP addresses and CIDR blocks, written for the WireGuard editor's checks and
// for "Exclude private IPs" (an idea from the official WireGuard Android app;
// the code and the range arithmetic here are our own, no WireGuard code).
//
// Flutter-free and dart:io-free: the web build, the tunnel helper and backend
// functions all import it.

/// A parsed IP address: 4 bytes (IPv4) or 16 bytes (IPv6).
final class IpAddress {
  const IpAddress._(this.bytes);

  final List<int> bytes;

  bool get isIPv4 => bytes.length == 4;

  /// Strict IP literal parse: dotted-quad IPv4 or IPv6 (no host names, no zone).
  static IpAddress? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.contains(':')) {
      final bytes = _parseIpv4(trimmed);
      return bytes == null ? null : IpAddress._(bytes);
    }
    final bytes = _parseIpv6(trimmed);
    return bytes == null ? null : IpAddress._(bytes);
  }

  static List<int>? _parseIpv4(String text) {
    final parts = text.split('.');
    if (parts.length != 4) return null;
    final bytes = <int>[];
    for (final part in parts) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(part)) return null;
      final value = int.parse(part);
      if (value > 255) return null;
      bytes.add(value);
    }
    return bytes;
  }

  static List<int>? _parseIpv6(String text) {
    if (text.contains('%') || ':::'.allMatches(text).isNotEmpty) return null;
    final halves = text.split('::');
    if (halves.length > 2) return null;
    List<int>? groups(String part) {
      if (part.isEmpty) return <int>[];
      final result = <int>[];
      final pieces = part.split(':');
      for (var index = 0; index < pieces.length; index++) {
        final piece = pieces[index];
        if (index == pieces.length - 1 && piece.contains('.')) {
          final ipv4 = _parseIpv4(piece);
          if (ipv4 == null) return null;
          result
            ..add((ipv4[0] << 8) | ipv4[1])
            ..add((ipv4[2] << 8) | ipv4[3]);
        } else {
          if (!RegExp(r'^[0-9a-fA-F]{1,4}$').hasMatch(piece)) return null;
          result.add(int.parse(piece, radix: 16));
        }
      }
      return result;
    }

    final head = groups(halves[0]);
    final tail = halves.length == 2 ? groups(halves[1]) : <int>[];
    if (head == null || tail == null) return null;
    final List<int> all;
    if (halves.length == 2) {
      final missing = 8 - head.length - tail.length;
      if (missing < 1) return null;
      all = <int>[...head, for (var i = 0; i < missing; i++) 0, ...tail];
    } else {
      if (head.length != 8) return null;
      all = head;
    }
    return <int>[
      for (final group in all) ...<int>[group >> 8, group & 0xff],
    ];
  }

  /// IPv4 dotted quad; IPv6 lower-case with the longest zero run compressed.
  String get canonical {
    if (isIPv4) return bytes.join('.');
    final groups = <int>[for (var i = 0; i < 16; i += 2) (bytes[i] << 8) | bytes[i + 1]];
    var bestStart = -1, bestLength = 0;
    for (var i = 0; i < 8;) {
      if (groups[i] != 0) {
        i++;
        continue;
      }
      var j = i;
      while (j < 8 && groups[j] == 0) {
        j++;
      }
      if (j - i > bestLength && j - i > 1) {
        bestStart = i;
        bestLength = j - i;
      }
      i = j;
    }
    String hex(Iterable<int> values) => values.map((value) => value.toRadixString(16)).join(':');
    if (bestStart < 0) return hex(groups);
    return '${hex(groups.take(bestStart))}::${hex(groups.skip(bestStart + bestLength))}';
  }
}

/// A parsed IP address with an optional prefix length: `10.0.0.1/32`, `::/0`.
final class IpBlock {
  const IpBlock._(this.address, this.prefixLength);

  /// Parses `addr` or `addr/prefix`. Null when either part is invalid.
  static IpBlock? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final slash = trimmed.indexOf('/');
    final address = IpAddress.tryParse(slash < 0 ? trimmed : trimmed.substring(0, slash));
    if (address == null) return null;
    final maxPrefix = address.isIPv4 ? 32 : 128;
    var prefix = maxPrefix;
    if (slash >= 0) {
      final prefixText = trimmed.substring(slash + 1);
      if (!RegExp(r'^\d{1,3}$').hasMatch(prefixText)) return null;
      prefix = int.parse(prefixText);
      if (prefix > maxPrefix) return null;
    }
    return IpBlock._(address, prefix);
  }

  final IpAddress address;
  final int prefixLength;

  bool get isIPv4 => address.isIPv4;

  @override
  String toString() => '${address.canonical}/$prefixLength';
}

/// Whether [text] is a plain IP address literal.
bool isIpAddress(String text) => IpAddress.tryParse(text) != null;

/// An inclusive IPv4 range as 32-bit integers.
typedef Ipv4Range = ({int first, int last});

int _ipv4ToInt(IpAddress address) => address.bytes.fold<int>(0, (value, byte) => (value << 8) | byte);

String _intToIpv4(int value) =>
    <int>[(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff].join('.');

/// The IPv4 range a CIDR block covers, or null when it is not IPv4.
Ipv4Range? ipv4Range(String cidr) {
  final block = IpBlock.tryParse(cidr);
  if (block == null || !block.isIPv4) return null;
  final size = 1 << (32 - block.prefixLength);
  final first = _ipv4ToInt(block.address) & ~(size - 1) & 0xffffffff;
  return (first: first, last: first + size - 1);
}

/// The smallest list of CIDR blocks covering exactly [range].
List<String> ipv4RangeToCidrs(Ipv4Range range) {
  final cidrs = <String>[];
  var start = range.first;
  while (start <= range.last) {
    // Largest block aligned at start that does not pass the end.
    var size = start == 0 ? 1 << 32 : start & -start;
    while (start + size - 1 > range.last) {
      size >>= 1;
    }
    final prefix = 32 - size.bitLength + 1;
    cidrs.add('${_intToIpv4(start)}/$prefix');
    start += size;
  }
  return cidrs;
}

/// [universe] minus [excluded], as the smallest list of CIDR blocks.
List<String> subtractIpv4(String universe, List<String> excluded) {
  final whole = ipv4Range(universe)!;
  final holes = excluded.map(ipv4Range).whereType<Ipv4Range>().toList()
    ..sort((a, b) => a.first.compareTo(b.first));
  final result = <String>[];
  var cursor = whole.first;
  for (final hole in holes) {
    if (hole.last < cursor || hole.first > whole.last) continue;
    if (hole.first > cursor) result.addAll(ipv4RangeToCidrs((first: cursor, last: hole.first - 1)));
    if (hole.last + 1 > cursor) cursor = hole.last + 1;
  }
  if (cursor <= whole.last) result.addAll(ipv4RangeToCidrs((first: cursor, last: whole.last)));
  return result;
}

/// The IPv4 blocks "Exclude private IPs" keeps out of the tunnel: the
/// RFC 1918 private ranges, loopback, link-local (RFC 3927) and multicast plus
/// the reserved class E space (224.0.0.0/3), so printers, routers and local
/// discovery keep working on the local network.
const List<String> privateIpv4Blocks = <String>[
  '10.0.0.0/8',
  '127.0.0.0/8',
  '169.254.0.0/16',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '224.0.0.0/3',
];

/// Every IPv4 address except [privateIpv4Blocks], as CIDR blocks.
final List<String> publicIpv4Blocks = List<String>.unmodifiable(subtractIpv4('0.0.0.0/0', privateIpv4Blocks));

/// Whether [address] (an IPv4 literal) falls in [privateIpv4Blocks].
bool isPrivateIpv4(String address) {
  final range = ipv4Range(address);
  if (range == null) return false;
  return privateIpv4Blocks.map(ipv4Range).whereType<Ipv4Range>().any((block) => range.first >= block.first && range.last <= block.last);
}

/// The canonical spelling of a CIDR entry (`10.0.0.1` → `10.0.0.1/32`), or
/// the trimmed text when it does not parse.
String canonicalCidr(String text) => IpBlock.tryParse(text)?.toString() ?? text.trim();

/// "Exclude private IPs" for a peer's AllowedIPs.
///
/// Turning it on replaces `0.0.0.0/0` with [publicIpv4Blocks] and adds the
/// interface's private IPv4 DNS servers back as /32 (a provider's resolver at
/// 10.x must still go through the tunnel). Turning it off restores
/// `0.0.0.0/0` where the first public block was. Other entries (`::/0`,
/// specific subnets) are kept in order.
abstract final class PrivateIpExclusion {
  static const String _allIpv4 = '0.0.0.0/0';

  static Set<String> _public() => publicIpv4Blocks.toSet();

  static List<String> _dnsHosts(List<String> dnsServers) => <String>[
        for (final server in dnsServers)
          if (isPrivateIpv4(server)) canonicalCidr(server),
      ];

  /// Whether the toggle applies: the peer sends all IPv4 traffic, or the
  /// toggle is already on.
  static bool isAvailable(List<String> allowedIPs) =>
      allowedIPs.map(canonicalCidr).contains(_allIpv4) || isOn(allowedIPs);

  /// Whether every public block is listed (and 0.0.0.0/0 is not).
  static bool isOn(List<String> allowedIPs) {
    final listed = allowedIPs.map(canonicalCidr).toSet();
    return !listed.contains(_allIpv4) && listed.containsAll(_public());
  }

  static List<String> excluding(List<String> allowedIPs, {List<String> dnsServers = const <String>[]}) {
    if (isOn(allowedIPs)) return allowedIPs;
    final result = <String>[];
    for (final entry in allowedIPs) {
      if (canonicalCidr(entry) == _allIpv4) {
        result.addAll(publicIpv4Blocks);
      } else {
        result.add(entry);
      }
    }
    final present = result.map(canonicalCidr).toSet();
    for (final host in _dnsHosts(dnsServers)) {
      if (present.add(host)) result.add(host);
    }
    return result;
  }

  static List<String> including(List<String> allowedIPs, {List<String> dnsServers = const <String>[]}) {
    if (!isOn(allowedIPs)) return allowedIPs;
    final public = _public();
    final dnsHosts = _dnsHosts(dnsServers).toSet();
    final result = <String>[];
    var restored = false;
    for (final entry in allowedIPs) {
      final canonical = canonicalCidr(entry);
      if (public.contains(canonical)) {
        if (!restored) result.add(_allIpv4);
        restored = true;
      } else if (!dnsHosts.contains(canonical)) {
        result.add(entry);
      }
    }
    return result;
  }
}
