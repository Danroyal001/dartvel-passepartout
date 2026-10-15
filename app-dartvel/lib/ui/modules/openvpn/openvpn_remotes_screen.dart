// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'package:flutter/material.dart';
import '../../../domain/profile.dart';
import '../../../l10n/strings.g.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../kit.dart';
import 'openvpn_formatters.dart';

/// The remotes of [module]'s configuration, as `address:proto:port` strings.
List<String> openVPNRemotes(TaggedModule module) {
  final configuration = module.value['configuration'];
  final remotes = configuration is Map ? configuration['remotes'] : null;
  return remotes is List ? remotes.map((remote) => remote.toString()).toList() : <String>[];
}

/// [module] with its configuration's remotes replaced by [remotes]; every
/// other field is kept.
TaggedModule withOpenVPNRemotes(TaggedModule module, List<String> remotes) {
  final raw = module.value['configuration'];
  final configuration = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  configuration['remotes'] = remotes;
  final nextValue = Map<String, dynamic>.from(module.value);
  nextValue['configuration'] = configuration;
  return module.withValue(nextValue);
}

/// Screen for managing remote endpoints of an OpenVPN module.
/// Matches upstream `OpenVPNView+Remotes.swift`. Edits apply to the latest
/// module it reported, starting from [module].
@DVFunctionalWidget()
Widget _openVPNRemotesScreen(
  BuildContext context, {
  required TaggedModule module,
  required ValueChanged<TaggedModule> onChanged,
}) {
  final DVSignal<TaggedModule> current = context.signal<TaggedModule>(module);
  final remotes = openVPNRemotes(current.value);

  void save(List<String> Function(List<String> remotes) change) {
    final updated = withOpenVPNRemotes(current.read(), change(openVPNRemotes(current.read())));
    current.value = updated;
    onChanged(updated);
  }

  return PSScaffold(
    title: tr(Strings.modulesOpenvpnRemotes),
    body: PSForm(
      children: <Widget>[
        PSSection(
          children: <Widget>[
            for (var i = 0; i < remotes.length; i++)
              OpenVPNRemoteRow(
                key: ValueKey<int>(i),
                parsed: ParsedRemote.parse(remotes[i]),
                onChanged: (updated) => save((list) => i < list.length ? (list..[i] = updated.toRaw()) : list),
                onDelete: () => save((list) => i < list.length ? (list..removeAt(i)) : list),
              ),
            PSRow(
              title: tr(Strings.globalActionsAdd),
              leading: const Icon(Icons.add_circle, color: PSColors.active),
              onTap: () => save((list) => list..add('vpn.example.com:UDP:1194')),
            ),
          ],
        ),
      ],
    ),
  );
}

/// One remote: delete button, `host:port` field and socket type menu.
@DVFunctionalWidget()
Widget _openVPNRemoteRow(
  BuildContext context, {
  required ParsedRemote parsed,
  required ValueChanged<ParsedRemote> onChanged,
  required VoidCallback onDelete,
}) {
  void addressChanged(String value) {
    final parts = value.split(':');
    final String address;
    final int port;
    if (parts.length >= 2) {
      address = parts.sublist(0, parts.length - 1).join(':');
      port = int.tryParse(parts.last) ?? parsed.port;
    } else {
      address = value;
      port = parsed.port;
    }
    onChanged(parsed.copyWith(address: address, port: port));
  }

  final theme = Theme.of(context);
  return DVBox.row(
    <Widget>[
      DVIconButton(
        icon: Icons.remove_circle,
        color: PSColors.error,
        label: tr(Strings.globalActionsDelete),
        onPressed: onDelete,
      ),
      Expanded(
        // Borderless and monospaced, as before.
        child: Theme(
          data: theme.copyWith(
            inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
            textTheme: theme.textTheme.copyWith(
              bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
              titleMedium: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          child: Semantics(
            label: tr(Strings.globalNounsEndpoint),
            child: DVText(
              '${parsed.address}:${parsed.port}',
              const DVModifier().input(hint: 'host:port', onChanged: addressChanged),
            ),
          ),
        ),
      ),
      Tooltip(
        message: tr(Strings.globalNounsProtocol),
        excludeFromSemantics: true,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: parsed.socketType,
            items: <DropdownMenuItem<String>>[
              for (final type in ParsedRemote.socketTypes)
                DropdownMenuItem<String>(value: type, child: DVText(type, const DVModifier().fontWeight(.w600))),
            ],
            onChanged: (value) {
              if (value != null) onChanged(parsed.copyWith(socketType: value));
            },
          ),
        ),
      ),
    ],
    spacing: 8,
    crossAlign: .center,
    modifier: const DVModifier().paddingSymmetric(horizontal: 16, vertical: 6),
  );
}
