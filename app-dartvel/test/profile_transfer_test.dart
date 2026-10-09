// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
// Zip export and import through the real Partout engine. Run with
// PARTOUT_LIBRARY and LD_LIBRARY_PATH set (docs/BUILD.md).

import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/dartvel_client/dartvel_client.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/domain/tunnel_archive.dart';
import 'package:passepartout/platform/vpn_service.dart';
import 'package:passepartout/platform/vpn_service_native.dart';
import 'package:passepartout/state/app_state.dart';
import 'package:passepartout/ui/screens/profile_transfer.dart';

import 'support/app_harness.dart';

bool get _hasEngine {
  final path = io.Platform.environment['PARTOUT_LIBRARY'];
  return path != null && io.File(path).existsSync();
}

void main() {
  setUp(() {
    DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
    setUpApp();
    if (_hasEngine) VpnService.instance = PartoutVpnService();
  });
  tearDown(DVDeviceStorage.reset);

  test('export all to zip, then import the zip, gives the same connections', () async {
    final wireGuard = await ProfileStore.importText(io.File('test/fixtures/sample.conf').readAsStringSync(), name: 'Home');
    final openVpn = await ProfileStore.importText(io.File('test/fixtures/sample.ovpn').readAsStringSync(), name: 'Office');
    await ProfileStore.save(TunnelProfile.empty('No connection').savingModule(TaggedModule.empty(ModuleType.dns)));

    final archive = await exportAllProfilesArchive(ProfileStore.state.profiles);
    expect(archive.exported, 2);
    expect(archive.skipped, 1);
    final files = readTunnelArchive(archive.bytes);
    expect(files.map((f) => f.name), unorderedEquals(<String>['Home', 'Office']));
    expect(files.firstWhere((f) => f.name == 'Home').text, contains('[Interface]'));

    for (final profile in ProfileStore.state.profiles.toList()) {
      await ProfileStore.remove(profile.id);
    }
    final result = await importTunnelArchive(archive.bytes);
    expect(result.imported, 2);
    expect(result.failed, isEmpty);
    final home = ProfileStore.state.profiles.firstWhere((p) => p.name == 'Home');
    // The DNS settings get a fresh id on every import; everything else is the same.
    Map<String, dynamic> withoutIds(TunnelProfile profile) {
      final configuration = jsonDecode(jsonEncode(profile.activeConnection!.value['configuration'])) as Map<String, dynamic>;
      (configuration['interface']['dns'] as Map?)?.remove('id');
      return configuration;
    }

    expect(withoutIds(home), withoutIds(wireGuard));
    final office = ProfileStore.state.profiles.firstWhere((p) => p.name == 'Office');
    expect(office.activeConnection!.type, openVpn.activeConnection!.type);
  }, skip: _hasEngine ? false : 'PARTOUT_LIBRARY not set');

  test('a broken file inside a zip does not stop the others', () async {
    final bytes = writeTunnelArchive(<({String name, String extension, String text})>[
      (name: 'Good', extension: 'conf', text: io.File('test/fixtures/sample.conf').readAsStringSync()),
      (name: 'Broken', extension: 'conf', text: 'not a configuration'),
    ]);
    final result = await importTunnelArchive(bytes);
    expect(result.imported, 1);
    expect(result.failed, <String>['Broken']);
  }, skip: _hasEngine ? false : 'PARTOUT_LIBRARY not set');
}
