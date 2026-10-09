// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Decides whether an on-demand profile should be up on the current network.
//
// On Apple the system evaluates `NEOnDemandRule`s that Partout builds from the
// OnDemand module (partout `OnDemandModule+NE.swift`). Every other target has
// no such service, so the app evaluates the same rules itself, in the same
// order: network exceptions first (unless the policy is "any"), then the
// fallback rule. The official WireGuard apps offer the same choices (on Wi-Fi
// with "only/except these SSIDs", on cellular, on Ethernet); this is our own
// implementation of that behaviour.
//
// Flutter-free and dart:io-free.

import 'profile.dart';

/// The kind of network the device is using for its default route.
enum NetworkKind { wifi, mobile, ethernet, other, offline }

/// The network the device is on: its kind and, on Wi-Fi, the SSID when known.
final class NetworkSnapshot {
  const NetworkSnapshot(this.kind, {this.ssid});

  static const NetworkSnapshot offline = NetworkSnapshot(.offline);

  final NetworkKind kind;
  final String? ssid;

  @override
  bool operator ==(Object other) => other is NetworkSnapshot && other.kind == kind && other.ssid == ssid;

  @override
  int get hashCode => Object.hash(kind, ssid);

  /// Plain words for the UI: `Wi-Fi "Home"`, `mobile data`, `Ethernet`.
  String get label => switch (kind) {
        .wifi => ssid == null ? 'Wi-Fi' : 'Wi-Fi "$ssid"',
        .mobile => 'mobile data',
        .ethernet => 'Ethernet',
        .other => 'another network',
        .offline => 'offline',
      };

  @override
  String toString() => ssid == null ? kind.name : '${kind.name}($ssid)';
}

enum OnDemandDecision { connect, disconnect, ignore }

/// Which network kinds this target can tell apart. Partout's Apple code only
/// adds the cellular rule on iOS and the Ethernet rule on macOS/tvOS; a
/// desktop with NetworkManager can tell all three apart.
final class OnDemandSupport {
  const OnDemandSupport({this.mobile = true, this.ethernet = true});

  final bool mobile;
  final bool ethernet;
}

/// The OnDemand module of [profile] when it is active, else null.
TaggedModule? activeOnDemandModule(TunnelProfile profile) {
  for (final module in profile.modules) {
    if (module.type == ModuleType.onDemand && profile.isActive(module.id)) return module;
  }
  return null;
}

/// Evaluates an OnDemand module value (`policy`, `withSSIDs`,
/// `withOtherNetworks`) against [network].
OnDemandDecision evaluateOnDemand(
  Map<String, dynamic> module,
  NetworkSnapshot network, {
  OnDemandSupport support = const OnDemandSupport(),
}) {
  if (network.kind == .offline) return .ignore;
  final policy = module['policy'] as String? ?? 'any';
  final others = <String>{for (final value in (module['withOtherNetworks'] as List?) ?? const <dynamic>[]) '$value'};
  final ssids = <String>{
    for (final entry in ((module['withSSIDs'] as Map?) ?? const <String, dynamic>{}).entries)
      if (entry.value == true) '${entry.key}',
  };

  // `networkRule`: a matching exception disconnects for any/excluding and
  // connects for including.
  final onMatch = policy == 'including' ? OnDemandDecision.connect : OnDemandDecision.disconnect;
  // `globalRule`: everything else connects for any/excluding, disconnects for including.
  final fallback = policy == 'including' ? OnDemandDecision.disconnect : OnDemandDecision.connect;

  if (policy != 'any') {
    if (support.mobile && others.contains('mobile') && network.kind == .mobile) return onMatch;
    if (support.ethernet && others.contains('ethernet') && network.kind == .ethernet) return onMatch;
    if (ssids.isNotEmpty && network.kind == .wifi && network.ssid != null && ssids.contains(network.ssid)) {
      return onMatch;
    }
  }
  return fallback;
}
