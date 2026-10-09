// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
import 'dart:io';

/// Written with owner-only permissions where the OS has them: exports carry
/// private keys.
Future<void> writeFile(String path, List<int> bytes) async {
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  if (Platform.isLinux || Platform.isMacOS) await Process.run('chmod', <String>['600', path]);
}
