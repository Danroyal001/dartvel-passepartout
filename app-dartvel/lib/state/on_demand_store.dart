// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// On-demand activation where the system does not do it (everything but
// Apple): the app watches the network and brings the armed profile up or down
// by its OnDemand module's rules (domain/on_demand_rules.dart).
//
// As on Apple and in the WireGuard apps, connecting a profile that has an
// active OnDemand module arms it; turning it off by hand disarms it, so the
// app never fights the person. The app only acts when the network changes (or
// right after arming), so a failed connection is not retried in a loop.

import 'dart:async';
import 'dart:convert';

import '../dartvel_client/dartvel_client.dart';
import '../domain/on_demand_rules.dart';
import '../domain/profile.dart';
import '../platform/network/current_network.dart';
import 'app_log.dart';
import 'app_state.dart';

export '../domain/on_demand_rules.dart';

class const OnDemandState({
  final String? armedProfileId,
  final NetworkSnapshot? network,
  final OnDemandDecision? lastDecision,
});

const String _onDemandKey = 'on-demand.json';

abstract final class OnDemandStore {
  static OnDemandState get state {
    try {
      return DV.global<OnDemandState>();
    } on StateError {
      return const OnDemandState(); // init() not called (a test, the server)
    }
  }

  static void _set(OnDemandState next) => DV.global<OnDemandState>(next);

  static Timer? _timer;
  static bool _evaluating = false;

  /// Which network kinds this target tells apart.
  static OnDemandSupport support = const OnDemandSupport();

  static void init() {
    stop();
    DV.global<OnDemandState>(const OnDemandState());
  }

  static Future<void> load() async {
    try {
      final disk = DV.Platform.fileStorage;
      if (await disk.exists(_onDemandKey)) {
        final json = jsonDecode(utf8.decode(await disk.get(_onDemandKey)));
        _set(OnDemandState(armedProfileId: json is Map ? json['armedProfileId'] as String? : null));
      }
    } on Object catch (error) {
      AppLog.warning('Unable to read on-demand state: $error');
    }
  }

  /// Arms [profileId] (or disarms with null). The next evaluation acts on the
  /// current network even if it has not changed.
  static Future<void> arm(String? profileId) async {
    if (profileId == state.armedProfileId && state.network == null) return;
    _set(OnDemandState(armedProfileId: profileId));
    try {
      await DV.Platform.fileStorage.put(
        _onDemandKey,
        utf8.encode(jsonEncode(<String, dynamic>{'armedProfileId': profileId})),
        contentType: 'application/json',
      );
    } on Object catch (error) {
      AppLog.warning('Unable to save on-demand state: $error');
    }
  }

  /// Called when the person connects [profile] by hand.
  static Future<void> userConnected(TunnelProfile profile) =>
      arm(activeOnDemandModule(profile) == null ? null : profile.id);

  /// Called when the person disconnects by hand.
  static Future<void> userDisconnected() => arm(null);

  /// Polls the network every [interval] where the target can read it.
  static void start({Duration interval = const Duration(seconds: 10)}) {
    stop();
    if (!CurrentNetwork.isSupported) return;
    _timer = Timer.periodic(interval, (_) => evaluate());
    unawaited(evaluate());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One pass: read the network and, when it changed since the last pass,
  /// apply the armed profile's rules. Returns the decision taken, if any.
  static Future<OnDemandDecision?> evaluate() async {
    if (_evaluating) return null;
    _evaluating = true;
    try {
      final armedId = state.armedProfileId;
      if (armedId == null) return null;
      final profile = ProfileStore.state.byId(armedId);
      final module = profile == null ? null : activeOnDemandModule(profile);
      if (profile == null || module == null) {
        if (ProfileStore.state.isReady) await arm(null);
        return null;
      }
      final network = await CurrentNetwork.probe();
      if (network == null || network == state.network) return null;
      final decision = evaluateOnDemand(module.value, network, support: support);
      _set(OnDemandState(armedProfileId: armedId, network: network, lastDecision: decision));
      final tunnel = TunnelStore.state;
      final isUp = tunnel.activeProfileId == armedId && tunnel.status != .disconnected;
      switch (decision) {
        case .connect when !isUp:
          AppLog.info('On-demand: connecting ${profile.name} on ${network.kind.name}');
          await TunnelStore.connect(profile, automatic: true);
        case .disconnect when isUp:
          AppLog.info('On-demand: disconnecting ${profile.name} on ${network.kind.name}');
          await TunnelStore.disconnect(automatic: true);
        default:
          break;
      }
      return decision;
    } on Object catch (error) {
      AppLog.warning('On-demand: $error');
      return null;
    } finally {
      _evaluating = false;
    }
  }
}
