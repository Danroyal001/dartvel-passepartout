// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Field checks for the WireGuard editor, shown next to the field as it is
// typed. The rules follow wg-quick's format and the messages upstream already
// carries (errors.wireguard.*). Our own code; no WireGuard code is copied.
//
// Flutter-free: tests and the import screen use it directly.

import 'dart:convert';

import 'ip_ranges.dart';

/// What is wrong with one field. [value] is the offending entry, for `{0}`.
enum WireGuardIssueKind {
  privateKeyRequired,
  privateKeyInvalid,
  addressInvalid,
  mtuInvalid,
  dnsInvalid,
  publicKeyRequired,
  publicKeyInvalid,
  publicKeyDuplicated,
  preSharedKeyInvalid,
  allowedIPsInvalid,
  endpointInvalid,
  keepAliveInvalid,
}

final class WireGuardIssue {
  const WireGuardIssue(this.kind, [this.value = '']);

  final WireGuardIssueKind kind;
  final String value;

  @override
  bool operator ==(Object other) => other is WireGuardIssue && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'WireGuardIssue(${kind.name}, $value)';
}

/// A WireGuard key: 32 bytes in standard base64 (44 characters).
bool isWireGuardKey(String text) {
  final trimmed = text.trim();
  if (trimmed.length != 44 || !trimmed.endsWith('=')) return false;
  try {
    return base64.decode(trimmed).length == 32;
  } on FormatException {
    return false;
  }
}

List<String> _entries(String text) =>
    text.split(',').map((entry) => entry.trim()).where((entry) => entry.isNotEmpty).toList();

abstract final class WireGuardValidation {
  static WireGuardIssue? privateKey(String text) {
    if (text.trim().isEmpty) return const WireGuardIssue(.privateKeyRequired);
    return isWireGuardKey(text) ? null : const WireGuardIssue(.privateKeyInvalid);
  }

  /// Interface addresses: IPs, optionally with a prefix.
  static WireGuardIssue? addresses(String text) {
    for (final entry in _entries(text)) {
      if (IpBlock.tryParse(entry) == null) return WireGuardIssue(.addressInvalid, entry);
    }
    return null;
  }

  /// DNS servers: plain IP addresses.
  static WireGuardIssue? dnsServers(String text) {
    for (final entry in _entries(text)) {
      if (!isIpAddress(entry)) return WireGuardIssue(.dnsInvalid, entry);
    }
    return null;
  }

  /// MTU: empty, or 576...65535.
  static WireGuardIssue? mtu(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    return (value == null || value < 576 || value > 65535) ? WireGuardIssue(.mtuInvalid, trimmed) : null;
  }

  static WireGuardIssue? publicKey(String text) {
    if (text.trim().isEmpty) return const WireGuardIssue(.publicKeyRequired);
    return isWireGuardKey(text) ? null : const WireGuardIssue(.publicKeyInvalid);
  }

  /// Pre-shared key: empty, or a key.
  static WireGuardIssue? preSharedKey(String text) =>
      text.trim().isEmpty || isWireGuardKey(text) ? null : const WireGuardIssue(.preSharedKeyInvalid);

  static WireGuardIssue? allowedIPs(String text) {
    for (final entry in _entries(text)) {
      if (IpBlock.tryParse(entry) == null) return WireGuardIssue(.allowedIPsInvalid, entry);
    }
    return null;
  }

  /// Endpoint: empty, `host:port` or `[ipv6]:port`, port 1...65535.
  static WireGuardIssue? endpoint(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final issue = WireGuardIssue(.endpointInvalid, trimmed);
    final String host;
    final String port;
    if (trimmed.startsWith('[')) {
      final close = trimmed.indexOf(']:');
      if (close < 0) return issue;
      host = trimmed.substring(1, close);
      port = trimmed.substring(close + 2);
      final address = IpAddress.tryParse(host);
      if (address == null || address.isIPv4) return issue;
    } else {
      final colon = trimmed.lastIndexOf(':');
      if (colon <= 0) return issue;
      host = trimmed.substring(0, colon);
      port = trimmed.substring(colon + 1);
      if (host.contains(':')) return issue; // IPv6 without brackets
      if (!RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(host)) return issue;
    }
    final portValue = int.tryParse(port);
    if (!RegExp(r'^\d{1,5}$').hasMatch(port) || portValue == null || portValue < 1 || portValue > 65535) return issue;
    return null;
  }

  /// Persistent keep-alive: empty, or 0...65535.
  static WireGuardIssue? keepAlive(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    return (value == null || value < 0 || value > 65535) ? WireGuardIssue(.keepAliveInvalid, trimmed) : null;
  }

  /// Every issue in a `WireGuard.Configuration` JSON value, field by field,
  /// keyed by the editor's section name (`private-key`, `peer-1-endpoint`...).
  static Map<String, WireGuardIssue> configuration(Map<String, dynamic>? configuration) {
    final issues = <String, WireGuardIssue>{};
    if (configuration == null) return issues;
    void check(String section, WireGuardIssue? issue) {
      if (issue != null) issues[section] = issue;
    }

    String joined(Object? value) => value is List ? value.map((entry) => '$entry').join(',') : '';
    final interface = (configuration['interface'] as Map?) ?? const <String, dynamic>{};
    check('private-key', privateKey('${interface['privateKey'] ?? ''}'));
    check('addresses', addresses(joined(interface['addresses'])));
    check('mtu', mtu('${interface['mtu'] ?? ''}'));
    final dns = interface['dns'];
    if (dns is Map) check('dns-servers', dnsServers(joined(dns['servers'])));
    final peers = (configuration['peers'] as List?) ?? const <dynamic>[];
    final seenKeys = <String>{};
    for (var index = 0; index < peers.length; index++) {
      final peer = (peers[index] as Map?) ?? const <String, dynamic>{};
      final prefix = 'peer-${index + 1}';
      final key = '${peer['publicKey'] ?? ''}'.trim();
      final keyIssue = publicKey(key);
      if (keyIssue == null && !seenKeys.add(key)) {
        check('$prefix-public-key', const WireGuardIssue(.publicKeyDuplicated));
      } else {
        check('$prefix-public-key', keyIssue);
      }
      check('$prefix-preshared-key', preSharedKey('${peer['preSharedKey'] ?? ''}'));
      check('$prefix-endpoint', endpoint(_endpointText('${peer['endpoint'] ?? ''}')));
      check('$prefix-allowed-ips', allowedIPs(joined(peer['allowedIPs'])));
      check('$prefix-keep-alive', keepAlive('${peer['keepAlive'] ?? ''}'));
    }
    return issues;
  }

  /// The engine stores IPv6 endpoints without brackets (`fe80::1:51820`);
  /// the editor shows wg-quick's `[fe80::1]:51820`.
  static String _endpointText(String raw) {
    final separator = raw.lastIndexOf(':');
    if (raw.startsWith('[') || separator < 0) return raw;
    final host = raw.substring(0, separator);
    return host.contains(':') ? '[$host]${raw.substring(separator)}' : raw;
  }
}
