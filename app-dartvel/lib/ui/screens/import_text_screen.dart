// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// "/import-text": paste a profile (upstream `.importProfileText` modal,
// `ThemeTextInputView`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../l10n/strings.g.dart';
import '../../state/app_state.dart';
import '../kit.dart';
import 'text_focus.dart';

@DVFunctionalWidget()
Widget _importTextScreen(BuildContext context) {
  final DVSignal<String> text = context.signal<String>('');
  final DVSignal<bool> busy = context.signal<bool>(false);
  // The paste box has the focus as the page opens (it used to autofocus).
  runOnce(context, () => focusFirstTextField(context));
  final valid = text.value.trim().isNotEmpty;
  final isBusy = busy.value;
  final theme = Theme.of(context);

  Future<void> submit() async {
    final pasted = text.read();
    if (pasted.trim().isEmpty || busy.read()) return;
    busy.value = true;
    await runGuarded(context, () async {
      await ProfileStore.importText(pasted, name: tr(Strings.placeholdersProfileImportedName));
      if (DV.Navigation.canGoBack) {
        DV.Navigation.back();
      } else {
        DV.Navigation.navigate(DVRoutes.index);
      }
    }, title: tr(Strings.globalActionsImport));
    if (context.mounted) busy.value = false;
  }

  const InputBorder rounded = OutlineInputBorder(borderRadius: .all(.circular(10)), borderSide: BorderSide.none);
  return CallbackShortcuts(
    // Ctrl/Cmd+Enter submits; plain Enter is a newline in a profile.
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
      const SingleActivator(LogicalKeyboardKey.enter, meta: true): submit,
    },
    child: PSScaffold(
      title: tr(Strings.viewsAppToolbarImportTextTitle),
      actions: <Widget>[
        if (isBusy)
          DVBox(
            const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const DVModifier().padding(12),
          )
        else
          TextButton(onPressed: valid ? submit : null, child: DVText(tr(Strings.globalActionsImport))),
      ],
      // Centred across, top-aligned down, as PSForm: centring the scroll view
      // itself left the box floating mid-screen.
      body: DVBox.scrollableList(<Widget>[
        DVBox(
          DVBox.list(<Widget>[
            DVText(tr(Strings.viewsAppToolbarImportTextCaption)),
            // A filled, borderless, monospaced box, as upstream's text input.
            Theme(
              data: theme.copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: rounded,
                  enabledBorder: rounded,
                  focusedBorder: rounded,
                ),
                textTheme: theme.textTheme.copyWith(
                  bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              child: DVText(
                text.value,
                const DVModifier().input(
                  label: tr(Strings.viewsAppToolbarImportTextTitle),
                  hint: '[Interface]\nPrivateKey = …\n\n— or —\n\nclient\nremote vpn.example.com 1194',
                  multiline: true,
                  onChanged: (value) => text.value = value,
                ),
              ),
            ),
          ], spacing: 12),
          const DVModifier().maxWidth(720).centered(),
        ),
      ], modifier: const DVModifier().padding(16)),
    ),
  );
}
