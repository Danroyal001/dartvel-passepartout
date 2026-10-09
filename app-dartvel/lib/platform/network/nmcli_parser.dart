// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Reads NetworkManager's terse output (`nmcli -t`) into a NetworkSnapshot.
// Pure parsing, so it is tested without NetworkManager.

import '../../domain/on_demand_rules.dart';

/// Splits one `nmcli -t` line on unescaped colons and unescapes `\:` and `\\`.
List<String> splitNmcliFields(String line) {
  final fields = <String>[];
  final current = StringBuffer();
  for (var index = 0; index < line.length; index++) {
    final char = line[index];
    if (char == r'\' && index + 1 < line.length) {
      current.write(line[++index]);
    } else if (char == ':') {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  fields.add(current.toString());
  return fields;
}

/// Device types that are the tunnel or local plumbing, never "the network".
const Set<String> _virtualTypes = <String>{'loopback', 'tun', 'wireguard', 'bridge', 'veth', 'dummy', 'vpn', 'ip-tunnel', 'macvlan'};

NetworkKind _kindOf(String type) => switch (type) {
      'wifi' => NetworkKind.wifi,
      'ethernet' => NetworkKind.ethernet,
      'gsm' || 'cdma' || 'modem' || 'wwan' => NetworkKind.mobile,
      _ => NetworkKind.other,
    };

/// The device the device uses for its network, from
/// `nmcli -t -f DEVICE,TYPE,STATE device` (NetworkManager lists devices in
/// priority order). Tunnels and bridges are skipped. Null when none is up.
({String device, NetworkKind kind})? primaryNmcliDevice(String deviceOutput) {
  for (final line in deviceOutput.split('\n')) {
    if (line.trim().isEmpty) continue;
    final fields = splitNmcliFields(line);
    if (fields.length < 3) continue;
    final type = fields[1];
    final state = fields[2];
    if (_virtualTypes.contains(type) || !state.startsWith('connected')) continue;
    if (state.contains('externally')) continue; // e.g. a tun the helper made
    return (device: fields[0], kind: _kindOf(type));
  }
  return null;
}

/// The SSID marked active in `nmcli -t -f ACTIVE,SSID device wifi list`.
String? activeNmcliSsid(String wifiOutput) {
  for (final line in wifiOutput.split('\n')) {
    final fields = splitNmcliFields(line);
    if (fields.length >= 2 && fields[0] == 'yes' && fields[1].isNotEmpty) return fields.sublist(1).join(':');
  }
  return null;
}
