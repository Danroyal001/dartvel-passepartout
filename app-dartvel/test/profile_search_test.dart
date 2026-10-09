// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/state/app_state.dart';

TunnelProfile _wireGuard(String name, String endpoint) => TunnelProfile.empty(name).savingModule(TaggedModule.of(ModuleType.wireGuard, <String, dynamic>{
      'id': newUniqueId(),
      'configuration': <String, dynamic>{
        'interface': <String, dynamic>{'privateKey': '', 'addresses': <dynamic>[]},
        'peers': <dynamic>[<String, dynamic>{'publicKey': 'k', 'allowedIPs': <dynamic>[], 'endpoint': endpoint}],
      },
    }));

TunnelProfile _openVpn(String name, String remote) => TunnelProfile.empty(name).savingModule(TaggedModule.of(ModuleType.openVPN, <String, dynamic>{
      'id': newUniqueId(),
      'configuration': <String, dynamic>{'remotes': <dynamic>[remote]},
    }));

void main() {
  final profiles = <TunnelProfile>[
    _wireGuard('Germany 12', 'de-fra-12.example.net:51820'),
    _wireGuard('Germany 3', 'de-ber-3.example.net:51820'),
    _openVpn('Office', 'vpn.office.example:UDP:1194'),
  ];

  List<String> search(String query) => ProfilesState(profiles: profiles, search: query).filtered.map((p) => p.name).toList();

  test('search matches name, module type and server; every word must match', () {
    expect(search(''), <String>['Germany 12', 'Germany 3', 'Office']);
    expect(search('fra'), <String>['Germany 12'], reason: 'server address');
    expect(search('wireguard'), <String>['Germany 12', 'Germany 3'], reason: 'module type');
    expect(search('germany ber'), <String>['Germany 3'], reason: 'all words');
    expect(search('  OFFICE   udp '), <String>['Office']);
    expect(search('germany office'), isEmpty);
  });
}
