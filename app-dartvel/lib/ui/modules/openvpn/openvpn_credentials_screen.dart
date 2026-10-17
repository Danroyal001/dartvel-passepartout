// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter/material.dart';
import '../../../domain/profile.dart';
import '../../../l10n/strings.g.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../kit.dart';
import 'openvpn_formatters.dart';

/// Screen for editing OpenVPN credentials and interactive OTP settings.
/// Matches upstream `OpenVPNCredentialsGroup`. Edits apply to the latest
/// module it reported, starting from [module].
@DVFunctionalWidget()
Widget _openVPNCredentialsScreen(
  BuildContext context, {
  required TaggedModule module,
  required ValueChanged<TaggedModule> onChanged,
}) {
  final DVSignal<TaggedModule> current = context.signal<TaggedModule>(module);
  final shown = current.value;
  final rawCredentials = shown.value['credentials'];
  final creds = rawCredentials is Map ? Map<String, dynamic>.from(rawCredentials) : <String, dynamic>{};
  final isInteractive = shown.value['requiresInteractiveCredentials'] == true;
  final otpMethod = (creds['otpMethod'] as String?)?.toLowerCase() ?? 'none';
  final approachDescription = formatOtpApproach(otpMethod);

  void update({String? username, String? password, String? otpMethod, bool? isInteractive}) {
    final latest = current.read();
    final raw = latest.value['credentials'];
    final next = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (username != null) next['username'] = username;
    if (password != null) next['password'] = password;
    if (otpMethod != null) next['otpMethod'] = otpMethod;
    final nextValue = Map<String, dynamic>.from(latest.value);
    nextValue['credentials'] = next;
    if (isInteractive != null) nextValue['requiresInteractiveCredentials'] = isInteractive;
    final updated = latest.withValue(nextValue);
    current.value = updated;
    onChanged(updated);
  }

  return PSScaffold(
    title: tr(Strings.modulesOpenvpnCredentials),
    body: PSForm(
      children: <Widget>[
        PSSection(
          footer: tr(Strings.modulesOpenvpnCredentialsInteractiveFooter),
          children: <Widget>[
            PSToggleRow(
              title: tr(Strings.modulesOpenvpnCredentialsInteractive),
              value: isInteractive,
              onChanged: (value) => update(isInteractive: value),
            ),
            if (isInteractive)
              pickerRow<String>(
                title: 'OTP',
                value: otpMethod,
                options: const <String>['none', 'append', 'encode'],
                label: formatOtpMethod,
                onChanged: (method) => update(otpMethod: method),
              ),
          ],
        ),
        if (isInteractive && approachDescription.isNotEmpty)
          DVText(
            approachDescription,
            const DVModifier().color(PSColors.secondary(context)).fontSize(12).paddingSymmetric(horizontal: 32, vertical: 4),
          ),
        PSSection(
          children: <Widget>[
            PSTextRow(
              label: tr(Strings.globalNounsUsername),
              value: (creds['username'] as String?) ?? '',
              placeholder: tr(Strings.placeholdersUsername),
              onChanged: (value) => update(username: value),
            ),
            PSTextRow(
              label: tr(Strings.globalNounsPassword),
              value: (creds['password'] as String?) ?? '',
              placeholder: tr(Strings.placeholdersSecret),
              obscure: true,
              onChanged: (value) => update(password: value),
            ),
          ],
        ),
      ],
    ),
  );
}
