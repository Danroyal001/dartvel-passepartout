// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
import 'dart:io';

import '../../domain/on_demand_rules.dart';
import 'nmcli_parser.dart';

bool get currentNetworkSupported => Platform.isLinux;

Future<String?> _nmcli(List<String> arguments) async {
  try {
    final result = await Process.run('nmcli', arguments, environment: const <String, String>{'LC_ALL': 'C'});
    return result.exitCode == 0 ? '${result.stdout}' : null;
  } on ProcessException {
    return null; // NetworkManager is not installed.
  }
}

Future<NetworkSnapshot?> probeCurrentNetwork() async {
  if (!Platform.isLinux) return null;
  final devices = await _nmcli(const <String>['-t', '-f', 'DEVICE,TYPE,STATE', 'device']);
  if (devices == null) return null;
  final primary = primaryNmcliDevice(devices);
  if (primary == null) return NetworkSnapshot.offline;
  if (primary.kind != NetworkKind.wifi) return NetworkSnapshot(primary.kind);
  final wifi = await _nmcli(<String>['-t', '-f', 'ACTIVE,SSID', 'device', 'wifi', 'list', 'ifname', primary.device, '--rescan', 'no']);
  return NetworkSnapshot(NetworkKind.wifi, ssid: wifi == null ? null : activeNmcliSsid(wifi));
}
