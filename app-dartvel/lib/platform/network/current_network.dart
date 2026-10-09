// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The network the device is on, for on-demand rules and "Add current Wi-Fi".
// Dartvel has no API for the network kind or the Wi-Fi name yet (see
// docs/DARTVEL-GAPS.md); Linux reads NetworkManager, other targets answer null.

import '../../domain/on_demand_rules.dart';
import 'current_network_stub.dart' if (dart.library.io) 'current_network_io.dart' as implementation;

export '../../domain/on_demand_rules.dart' show NetworkKind, NetworkSnapshot;

typedef NetworkProbe = Future<NetworkSnapshot?> Function();

abstract final class CurrentNetwork {
  /// Reads the current network; null where this target cannot tell. Tests replace it.
  static NetworkProbe probe = implementation.probeCurrentNetwork;

  /// Whether [probe] can answer on this target at all.
  static bool get isSupported => implementation.currentNetworkSupported;
}
