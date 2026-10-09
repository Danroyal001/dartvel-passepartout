// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/domain/tunnel_archive.dart';

List<int> _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('export then import round-trips names, extensions and text', () {
    final bytes = writeTunnelArchive(<({String name, String extension, String text})>[
      (name: 'Home', extension: 'conf', text: '[Interface]\nPrivateKey = a\n'),
      (name: 'Office VPN/2', extension: 'ovpn', text: 'client\n'),
      (name: 'home', extension: 'conf', text: 'second'),
    ]);
    final read = readTunnelArchive(bytes);
    expect(read.map((c) => c.name), <String>['Home', 'Office_VPN_2', 'home-2']);
    expect(read.first.text, '[Interface]\nPrivateKey = a\n');
    expect(read[1].text, 'client\n');
  });

  test('import skips folders, macOS metadata, hidden and other files', () {
    final read = readTunnelArchive(_zip(<String, String>{
      'tunnels/wg0.conf': 'a',
      '__MACOSX/tunnels/._wg0.conf': 'junk',
      'tunnels/.hidden.conf': 'junk',
      'README.txt': 'junk',
      'Paris.OVPN': 'b',
    }));
    expect(read, <ArchivedConfig>[(name: 'wg0', text: 'a'), (name: 'Paris', text: 'b')]);
  });

  test('not a zip, or too many files, is refused', () {
    expect(() => readTunnelArchive(utf8.encode('[Interface]')), throwsFormatException);
    final many = <String, String>{for (var i = 0; i <= TunnelArchiveLimits.maxEntries; i++) 't$i.conf': 'x'};
    expect(() => readTunnelArchive(_zip(many)), throwsFormatException);
  });

  test('file stems are safe and never empty', () {
    expect(tunnelFileStem('  ../../etc/passwd '), '_.._etc_passwd');
    expect(tunnelFileStem('...'), 'tunnel');
    expect(tunnelFileStem('x' * 100), hasLength(64));
    expect(isTunnelArchiveName('Backup.ZIP'), isTrue);
    expect(isTunnelArchiveName('wg0.conf'), isFalse);
  });
}
