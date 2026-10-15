// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../domain/profile.dart';
import '../../../l10n/app_strings.dart';
import '../../../l10n/strings.g.dart';
import '../../../platform/vpn_service.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../kit.dart';

/// Shows an import dialog allowing the user to paste .ovpn configuration text
/// or load from a local file path.
/// Matches upstream `OpenVPNView+Import.swift` / `ModuleImportSection`.
Future<void> showOpenVPNImportDialog(
  BuildContext context, {
  required ValueChanged<TaggedModule> onImported,
  TaggedModule? currentModule,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => OpenVPNImportDialog(
      onImported: onImported,
      currentModule: currentModule,
    ),
  );
}

/// [base] (a new OpenVPN module when null) with the configuration,
/// credentials and interactive flag of [imported]; the module keeps its id
/// and every other field.
TaggedModule mergeImportedOpenVPN(TaggedModule? base, TaggedModule imported) {
  final module = base ?? TaggedModule.empty(ModuleType.openVPN);
  final nextValue = Map<String, dynamic>.from(module.value);
  for (final key in const <String>['configuration', 'credentials', 'requiresInteractiveCredentials']) {
    if (imported.value[key] != null) nextValue[key] = imported.value[key];
  }
  return module.withValue(nextValue);
}

/// The text of the file at [path], or null when there is no such file.
// Outside the widget: the widget generator does not carry `dart:io` over.
Future<String?> readConfigurationFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

/// The dialog [showOpenVPNImportDialog] presents: a file path to load, the
/// configuration text (pasted, typed or loaded), and Import.
@DVFunctionalWidget()
Widget _openVPNImportDialog(
  BuildContext context, {
  required ValueChanged<TaggedModule> onImported,
  TaggedModule? currentModule,
}) {
  final DVSignal<String> path = context.signal<String>('');
  final DVSignal<String> text = context.signal<String>('');
  final DVSignal<bool> loading = context.signal<bool>(false);
  final title = tr(Strings.modulesGeneralRowsImportFromFile);

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final pasted = data?.text;
    if (pasted != null && context.mounted) text.value = pasted;
  }

  Future<void> loadFile() async {
    final filePath = path.read().trim();
    if (filePath.isEmpty) return;
    try {
      final content = await readConfigurationFile(filePath);
      if (content != null) {
        if (context.mounted) text.value = content;
      } else if (context.mounted) {
        await showErrorAlert(context, title: title, message: AppStrings.fileNotFound(filePath));
      }
    } on Object catch (error) {
      if (context.mounted) await showErrorAlert(context, title: title, message: error.toString());
    }
  }

  Future<void> importText() async {
    final configuration = text.read().trim();
    if (configuration.isEmpty) return;
    loading.value = true;
    try {
      final imported = await VpnService.instance.importModule(configuration);
      if (!context.mounted) return;
      onImported(mergeImportedOpenVPN(currentModule, imported));
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (context.mounted) {
        loading.value = false;
        await showErrorAlert(context, title: title, message: error.toString());
      }
    }
  }

  final theme = Theme.of(context);
  final isLoading = loading.value;
  return AlertDialog(
    title: DVText(title),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: DVBox.list(
          <Widget>[
            DVBox.row(
              <Widget>[
                Expanded(
                  child: DVText(
                    path.value,
                    const DVModifier().input(
                      label: AppStrings.filePath,
                      hint: '/path/to/profile.ovpn',
                      onChanged: (value) => path.value = value,
                      onSubmitted: loadFile,
                    ),
                  ),
                ),
                TextButton(onPressed: loadFile, child: const DVText(AppStrings.loadFile)),
              ],
              spacing: 8,
              crossAlign: .center,
            ),
            DVBox.row(
              <Widget>[
                Expanded(
                  child: DVText(
                    AppStrings.openVPNConfigurationText,
                    const DVModifier().color(theme.colorScheme.onSurfaceVariant).fontSize(12).fontWeight(.w500),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.paste, size: 16),
                  label: const DVText(AppStrings.paste),
                  onPressed: paste,
                ),
              ],
              crossAlign: .center,
              modifier: const DVModifier().paddingOnly(top: 12),
            ),
            // Outlined and monospaced, as a configuration file reads.
            Theme(
              data: theme.copyWith(
                inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
                textTheme: theme.textTheme.copyWith(
                  bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace', fontSize: 13),
                  titleMedium: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              child: Semantics(
                label: AppStrings.openVPNConfigurationText,
                child: DVText(
                  text.value,
                  const DVModifier().input(
                    hint: 'client\nremote vpn.example.com 1194 udp\n...',
                    multiline: true,
                    onChanged: (value) => text.value = value,
                  ),
                ),
              ),
            ),
          ],
          spacing: 4,
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: isLoading ? null : () => Navigator.of(context).pop(),
        child: DVText(tr(Strings.globalActionsCancel)),
      ),
      FilledButton(
        onPressed: isLoading ? null : importText,
        child: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  semanticsLabel: tr(Strings.globalActionsImport),
                ),
              )
            : DVText(tr(Strings.globalActionsImport)),
      ),
    ],
  );
}
