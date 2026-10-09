// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Zip archives of tunnel configurations, as the official WireGuard apps import
// and export them: one wg-quick `.conf` (or OpenVPN `.ovpn`) file per tunnel,
// named after the tunnel. Our own code over the `archive` package; no
// WireGuard code is copied.

import 'dart:convert';

import 'package:archive/archive.dart';

/// Limits that keep a hostile archive from exhausting memory.
abstract final class TunnelArchiveLimits {
  static const int maxEntries = 1000;
  static const int maxEntryBytes = 1024 * 1024;
  static const int maxTotalBytes = 32 * 1024 * 1024;
}

/// The file extensions read from an archive, as profile importers accept them.
const Set<String> tunnelConfigExtensions = <String>{'conf', 'ovpn'};

/// One configuration found in an archive.
typedef ArchivedConfig = ({String name, String text});

String _baseName(String path) => path.split('/').last.split(r'\').last;

String? _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? null : name.substring(dot + 1).toLowerCase();
}

bool isTunnelArchiveName(String fileName) => _extension(fileName) == 'zip';

/// Reads every `.conf`/`.ovpn` file in [zipBytes], in archive order. Folders,
/// macOS resource forks and other files are skipped. Throws [FormatException]
/// when the bytes are not a zip or break [TunnelArchiveLimits].
List<ArchivedConfig> readTunnelArchive(List<int> zipBytes) {
  // Every zip starts with a local file header or, when empty, the end record.
  final isZip = zipBytes.length >= 4 &&
      zipBytes[0] == 0x50 &&
      zipBytes[1] == 0x4b &&
      ((zipBytes[2] == 3 && zipBytes[3] == 4) || (zipBytes[2] == 5 && zipBytes[3] == 6));
  if (!isZip) throw const FormatException('Not a zip archive');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes);
  } on Object {
    throw const FormatException('Not a zip archive');
  }
  final configs = <ArchivedConfig>[];
  var total = 0;
  var seen = 0;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (++seen > TunnelArchiveLimits.maxEntries) throw const FormatException('The archive has too many files');
    final path = file.name;
    final name = _baseName(path);
    if (path.startsWith('__MACOSX/') || name.startsWith('.')) continue;
    final extension = _extension(name);
    if (extension == null || !tunnelConfigExtensions.contains(extension)) continue;
    if (file.size > TunnelArchiveLimits.maxEntryBytes) throw FormatException('$name: file too large');
    total += file.size;
    if (total > TunnelArchiveLimits.maxTotalBytes) throw const FormatException('The archive is too large');
    final bytes = file.content as List<int>;
    if (bytes.length > TunnelArchiveLimits.maxEntryBytes) throw FormatException('$name: file too large');
    configs.add((name: name.substring(0, name.length - extension.length - 1), text: utf8.decode(bytes, allowMalformed: true)));
  }
  return configs;
}

/// A file name for [name]: letters, digits and `_=+.-` kept, others become
/// `_`, at most 64 characters. Never empty.
String tunnelFileStem(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_=+.\-]'), '_').replaceAll(RegExp(r'^\.+'), '');
  final stem = cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  return stem.isEmpty ? 'tunnel' : stem;
}

/// Writes [configs] (file stem without extension → text, with the extension
/// given per entry) to a zip. Stems that collide get ` 2`, ` 3`... suffixes
/// in the WireGuard style (`name-2`).
List<int> writeTunnelArchive(List<({String name, String extension, String text})> configs) {
  final archive = Archive();
  final used = <String>{};
  for (final config in configs) {
    final stem = tunnelFileStem(config.name);
    var fileName = '$stem.${config.extension}';
    var counter = 2;
    while (!used.add(fileName.toLowerCase())) {
      fileName = '$stem-${counter++}.${config.extension}';
    }
    final bytes = utf8.encode(config.text);
    archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}
