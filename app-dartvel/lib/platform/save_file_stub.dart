// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

/// The browser has no file paths to write to.
Future<void> writeFile(String path, List<int> bytes) async => throw UnsupportedError('No file system on this target');
