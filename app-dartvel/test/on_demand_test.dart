// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/dartvel_client/dartvel_client.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/platform/network/current_network.dart';
import 'package:passepartout/platform/network/nmcli_parser.dart';
import 'package:passepartout/platform/vpn_service.dart';
import 'package:passepartout/state/app_state.dart';
import 'package:passepartout/state/on_demand_store.dart';

import 'support/app_harness.dart';

Map<String, dynamic> _module(String policy, {Map<String, bool> ssids = const <String, bool>{}, List<String> others = const <String>[]}) =>
    <String, dynamic>{'id': 'X', 'policy': policy, 'withSSIDs': ssids, 'withOtherNetworks': others};

const NetworkSnapshot _home = NetworkSnapshot(.wifi, ssid: 'Home');
const NetworkSnapshot _cafe = NetworkSnapshot(.wifi, ssid: 'Cafe');
const NetworkSnapshot _mobile = NetworkSnapshot(.mobile);
const NetworkSnapshot _ethernet = NetworkSnapshot(.ethernet);

/// Records connect/disconnect calls instead of opening a tunnel.
class _FakeVpn implements VpnService {
  final List<String> calls = <String>[];

  @override
  bool get canConnect => true;
  @override
  String? get connectUnavailableReason => null;
  @override
  Future<void> connect(TunnelProfile profile, {required void Function(TunnelEvent) onStatus}) async {
    calls.add('connect ${profile.name}');
    onStatus(const TunnelEvent(status: .connected));
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('evaluateOnDemand (Partout NEOnDemandRule order)', () {
    test('any: always connect, exceptions ignored', () {
      final module = _module('any', ssids: <String, bool>{'Home': true}, others: <String>['mobile']);
      for (final network in <NetworkSnapshot>[_home, _cafe, _mobile, _ethernet, const NetworkSnapshot(.other)]) {
        expect(evaluateOnDemand(module, network), OnDemandDecision.connect, reason: '$network');
      }
      expect(evaluateOnDemand(module, NetworkSnapshot.offline), OnDemandDecision.ignore);
    });

    test('excluding: listed networks disconnect, the rest connect', () {
      final module = _module('excluding', ssids: <String, bool>{'Home': true, 'Off': false}, others: <String>['ethernet']);
      expect(evaluateOnDemand(module, _home), OnDemandDecision.disconnect);
      expect(evaluateOnDemand(module, const NetworkSnapshot(.wifi, ssid: 'Off')), OnDemandDecision.connect, reason: 'a switched-off SSID is not an exception');
      expect(evaluateOnDemand(module, _cafe), OnDemandDecision.connect);
      expect(evaluateOnDemand(module, _ethernet), OnDemandDecision.disconnect);
      expect(evaluateOnDemand(module, _mobile), OnDemandDecision.connect);
      expect(evaluateOnDemand(module, const NetworkSnapshot(.wifi)), OnDemandDecision.connect, reason: 'unknown SSID matches no rule');
    });

    test('including: only listed networks connect', () {
      final module = _module('including', ssids: <String, bool>{'Cafe': true}, others: <String>['mobile']);
      expect(evaluateOnDemand(module, _cafe), OnDemandDecision.connect);
      expect(evaluateOnDemand(module, _mobile), OnDemandDecision.connect);
      expect(evaluateOnDemand(module, _home), OnDemandDecision.disconnect);
      expect(evaluateOnDemand(module, _ethernet), OnDemandDecision.disconnect);
    });

    test('a target that cannot tell a kind apart skips its rule, as Partout does', () {
      final module = _module('including', others: <String>['mobile', 'ethernet']);
      const noMobile = OnDemandSupport(mobile: false);
      expect(evaluateOnDemand(module, _mobile, support: noMobile), OnDemandDecision.disconnect);
      expect(evaluateOnDemand(module, _ethernet, support: noMobile), OnDemandDecision.connect);
    });
  });

  group('nmcli parsing', () {
    test('escaped colons in fields', () {
      expect(splitNmcliFields(r'wlan0:wifi:connected:My\:Net'), <String>['wlan0', 'wifi', 'connected', 'My:Net']);
      expect(splitNmcliFields(r'a\\b:c'), <String>[r'a\b', 'c']);
    });

    test('the primary device skips tunnels, bridges and devices that are down', () {
      const output = 'tun0:tun:connected (externally)\n'
          'wg0:wireguard:connected\n'
          'docker0:bridge:connected (externally)\n'
          'enp3s0:ethernet:unavailable\n'
          'wlp2s0:wifi:connected\n'
          'lo:loopback:connected (externally)\n';
      expect(primaryNmcliDevice(output), (device: 'wlp2s0', kind: NetworkKind.wifi));
      expect(primaryNmcliDevice('wwan0:gsm:connected\n'), (device: 'wwan0', kind: NetworkKind.mobile));
      expect(primaryNmcliDevice('eth0:ethernet:connected\nwlan0:wifi:connected\n'), (device: 'eth0', kind: NetworkKind.ethernet));
      expect(primaryNmcliDevice('wlan0:wifi:disconnected\n'), isNull);
    });

    test('the active SSID', () {
      expect(activeNmcliSsid('no:Neighbour\nyes:Home\\:5G\nno:Other\n'), 'Home:5G');
      expect(activeNmcliSsid('no:Neighbour\n'), isNull);
    });
  });

  group('OnDemandStore', () {
    late _FakeVpn vpn;
    late NetworkSnapshot? network;
    late TunnelProfile profile;

    setUp(() async {
      DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
      setUpApp();
      vpn = _FakeVpn();
      VpnService.instance = vpn;
      network = _home;
      CurrentNetwork.probe = () async => network;
      profile = TunnelProfile.empty('Laptop')
          .savingModule(TaggedModule.of(ModuleType.onDemand, _module('excluding', ssids: <String, bool>{'Home': true})));
      await ProfileStore.save(profile);
    });
    tearDown(DVDeviceStorage.reset);

    test('connecting by hand arms the profile; rules then follow the network', () async {
      await TunnelStore.connect(profile);
      expect(OnDemandStore.state.armedProfileId, profile.id);
      expect(vpn.calls, <String>['connect Laptop']);

      // At home (excluded) the rules take it down, but stay armed.
      expect(await OnDemandStore.evaluate(), OnDemandDecision.disconnect);
      expect(vpn.calls.last, 'disconnect');
      expect(OnDemandStore.state.armedProfileId, profile.id);

      // Same network again: nothing happens, so a failure never loops.
      expect(await OnDemandStore.evaluate(), isNull);

      network = _cafe;
      expect(await OnDemandStore.evaluate(), OnDemandDecision.connect);
      expect(vpn.calls.last, 'connect Laptop');
      expect(OnDemandStore.state.armedProfileId, profile.id, reason: 'an automatic connect keeps it armed');
    });

    test('disconnecting by hand disarms', () async {
      await TunnelStore.connect(profile);
      await TunnelStore.disconnect();
      expect(OnDemandStore.state.armedProfileId, isNull);
      network = _cafe;
      expect(await OnDemandStore.evaluate(), isNull);
      expect(vpn.calls, <String>['connect Laptop', 'disconnect']);
    });

    test('a profile without an active on-demand module is never armed', () async {
      final plain = TunnelProfile.empty('Plain').savingModule(TaggedModule.empty(ModuleType.dns));
      await ProfileStore.save(plain);
      await TunnelStore.connect(plain);
      expect(OnDemandStore.state.armedProfileId, isNull);
    });

    test('the armed profile survives a restart', () async {
      await TunnelStore.connect(profile);
      OnDemandStore.init();
      expect(OnDemandStore.state.armedProfileId, isNull);
      await OnDemandStore.load();
      expect(OnDemandStore.state.armedProfileId, profile.id);
    });

    test('nothing happens where the network cannot be read', () async {
      await TunnelStore.connect(profile);
      network = null;
      expect(await OnDemandStore.evaluate(), isNull);
      expect(vpn.calls, <String>['connect Laptop']);
    });
  });
}
