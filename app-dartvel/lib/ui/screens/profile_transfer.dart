// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Import and export of profiles beyond single files, as the official WireGuard
// apps offer them: zip archives of .conf/.ovpn files (import and export), a
// QR code (camera on phones, an image file everywhere), and one profile's
// configuration exported as wg-quick .conf or OpenVPN .ovpn. Our own code.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../domain/profile.dart';
import '../../domain/qr_import.dart';
import '../../domain/tunnel_archive.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../platform/save_file.dart';
import '../../platform/vpn_service.dart';
import '../../state/app_state.dart';
import '../kit.dart';

/// Imports every configuration in [zipBytes]; returns how many were imported
/// and the names that failed. One bad file does not stop the others.
Future<({int imported, List<String> failed})> importTunnelArchive(List<int> zipBytes) async {
  var imported = 0;
  final failed = <String>[];
  for (final config in readTunnelArchive(zipBytes)) {
    try {
      await ProfileStore.importText(config.text, name: config.name);
      imported++;
    } on Object {
      failed.add(config.name);
    }
  }
  return (imported: imported, failed: failed);
}

/// The text of [profile]'s active connection as its native file (`.conf` for
/// WireGuard, `.ovpn` for OpenVPN), or null when it has none.
Future<({String extension, String text})?> exportedConnection(TunnelProfile profile) async {
  final connection = profile.activeConnection;
  if (connection == null || connection.value['configuration'] == null) return null;
  final text = await VpnService.instance.exportModule(connection);
  return (extension: connection.type == ModuleType.wireGuard ? 'conf' : 'ovpn', text: text);
}

/// Builds the zip of every profile with a connection. [skipped] counts the others.
Future<({List<int> bytes, int exported, int skipped})> exportAllProfilesArchive(List<TunnelProfile> profiles) async {
  final entries = <({String name, String extension, String text})>[];
  var skipped = 0;
  for (final profile in profiles) {
    final exported = await exportedConnection(profile);
    if (exported == null) {
      skipped++;
    } else {
      entries.add((name: profile.name, extension: exported.extension, text: exported.text));
    }
  }
  return (bytes: writeTunnelArchive(entries), exported: entries.length, skipped: skipped);
}

void _tell(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}

/// "Import from file" with zip support: each picked .zip is unpacked, other
/// files are imported as one profile each.
Future<void> importPickedFiles(BuildContext context, List<DVPickedFile> files) => runGuarded(context, () async {
      var imported = 0;
      final failed = <String>[];
      for (final file in files) {
        final bytes = await file.readBytes();
        if (isTunnelArchiveName(file.name)) {
          if (bytes.length > TunnelArchiveLimits.maxTotalBytes) throw FormatException('${file.name}: file too large');
          final result = await importTunnelArchive(bytes);
          imported += result.imported;
          failed.addAll(result.failed);
          continue;
        }
        if (bytes.length > 1024 * 1024) throw FormatException('${file.name}: file too large');
        final name = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
        await ProfileStore.importText(utf8.decode(bytes, allowMalformed: true), name: name);
        imported++;
      }
      if (files.length > 1 || files.any((file) => isTunnelArchiveName(file.name))) {
        if (context.mounted) _tell(context, AppStrings.importedCount(imported, failed));
      }
    }, title: tr(Strings.globalActionsImport));

bool get _hasCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// "Import QR": the camera on phones, an image file elsewhere (or when the
/// camera is not available), then the decoded text is imported.
Future<void> importQrCode(BuildContext context) => runGuarded(context, () async {
      List<int>? bytes;
      if (_hasCamera) {
        try {
          bytes = await DV.Platform.camera.takePhoto();
        } on StateError {
          bytes = null; // No camera binding on this build: fall back to a file.
        }
      }
      if (bytes == null) {
        final picked = await DV.Platform.fileStorage.pick(type: 'image');
        if (picked.isEmpty) return;
        bytes = await picked.first.readBytes();
      }
      if (bytes.isEmpty) return;
      final text = decodeQrImage(bytes);
      if (!looksLikeTunnelConfig(text)) throw const FormatException(AppStrings.importQrNoConfig);
      await ProfileStore.importText(text, name: tr(Strings.placeholdersProfileImportedName));
    }, title: tr(Strings.viewsAppToolbarImportQrTitle));

/// Exports [profile]'s connection to a file the person chooses.
Future<void> exportProfileFile(BuildContext context, TunnelProfile profile) => runGuarded(context, () async {
      final exported = await exportedConnection(profile);
      if (exported == null) throw const FormatException(AppStrings.exportNothing);
      try {
        await saveFileAs(
          '${tunnelFileStem(profile.name)}.${exported.extension}',
          utf8.encode(exported.text),
          filterLabel: exported.extension == 'conf' ? 'WireGuard' : 'OpenVPN',
          extension: exported.extension,
        );
      } on UnsupportedError {
        // No save dialog (a phone, the browser): hand the text to the share sheet.
        await DV.Platform.share.shareText(exported.text);
      }
    }, title: AppStrings.exportProfile);

/// Exports every profile with a connection to one zip.
Future<void> exportAllProfiles(BuildContext context) => runGuarded(context, () async {
      final archive = await exportAllProfilesArchive(ProfileStore.state.profiles);
      if (archive.exported == 0) throw const FormatException(AppStrings.exportNothing);
      try {
        final saved = await saveFileAs('dartvel-vpn-tunnels.zip', archive.bytes, filterLabel: 'Zip', extension: 'zip');
        if (saved && context.mounted) _tell(context, AppStrings.exportedCount(archive.exported, archive.skipped));
      } on UnsupportedError {
        throw const FormatException(AppStrings.saveUnavailable);
      }
    }, title: AppStrings.exportAll);
