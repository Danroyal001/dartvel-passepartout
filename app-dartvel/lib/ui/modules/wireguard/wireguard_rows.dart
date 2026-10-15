// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
// WireGuard-only rows: "N entries" previews and `ThemeCopiableText` for the
// public key derived from the private key. Long-content rows and their pages
// are the kit's `PSLongContentRow` / `PSLongContentPage`.

import 'package:flutter/material.dart';

import '../../../l10n/strings.g.dart';
import '../../../platform/vpn_service.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../kit.dart';

/// Upstream `Int.localizedEntries`: nil for 0, "1 entry", "{0} entries".
String? localizedEntries(int count) => switch (count) {
      0 => null,
      1 => tr(Strings.globalNounsEntriesOne),
      _ => tr(Strings.globalNounsEntriesN, <Object>[count]),
    };

/// Upstream `String.asNumberOfEntries`: the number of comma-separated entries.
String? asNumberOfEntries(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return localizedEntries(1 + ','.allMatches(trimmed).length);
}

/// `ThemeCopiableText(publicKey, value: keyGenerator.publicKey(for: privateKey))`:
/// the public key derived from [privateKey] by the engine; empty when invalid.
/// Derived again whenever [privateKey] changes; a late answer for a key that
/// has since changed is dropped.
@DVFunctionalWidget()
Widget _wireGuardPublicKeyRow(BuildContext context, {required String privateKey}) {
  final DVSignal<String> publicKey = context.signal<String>('');
  // Which private key the shown (or pending) public key is for. Read without
  // subscribing: it only decides whether to derive.
  final DVSignal<String?> derivedFrom = context.signal<String?>(null);
  if (derivedFrom.read() != privateKey) {
    derivedFrom.value = privateKey;
    // After this build: the result is set on the signal, never during build.
    Future<void>.microtask(() async {
      var derived = '';
      if (privateKey.isNotEmpty) {
        try {
          derived = await VpnService.instance.wireGuardPublicKey(privateKey);
        } on Object {
          derived = '';
        }
      }
      if (context.mounted && derivedFrom.read() == privateKey) publicKey.value = derived;
    });
  }
  final shown = publicKey.value;
  return PSRow(
    title: tr(Strings.globalNounsPublicKey),
    subtitle: shown.isEmpty ? null : shown,
    monospaced: true,
    onTap: shown.isEmpty ? null : () => copyToClipboard(context, shown),
    trailing: shown.isEmpty ? null : Icon(Icons.copy, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}
