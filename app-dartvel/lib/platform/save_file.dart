// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Saves an exported file where the person chooses: the system save dialog
// (DV.Platform.dialogs.saveFile), then the bytes are written to that path.

import '../dartvel_client/dartvel_client.dart';
import 'save_file_stub.dart' if (dart.library.io) 'save_file_io.dart' as implementation;

/// Asks where to save [suggestedName] and writes [bytes] there. False when
/// the person cancels. Throws [UnsupportedError] where there is no save
/// dialog on this target.
Future<bool> saveFileAs(String suggestedName, List<int> bytes, {required String filterLabel, required String extension}) async {
  final String? path;
  try {
    path = await DV.Platform.dialogs.saveFile(
      suggestedName: suggestedName,
      filters: <DVFileFilter>[DVFileFilter(label: filterLabel, extensions: <String>[extension])],
    );
  } on Object catch (error) {
    if (error is UnsupportedError || error is StateError) throw UnsupportedError('No save dialog on this target');
    rethrow;
  }
  if (path == null || path.isEmpty) return false;
  await implementation.writeFile(path, bytes);
  return true;
}
