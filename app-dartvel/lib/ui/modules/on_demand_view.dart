// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// On-demand module editor: upstream OnDemandView.swift + OnDemandModule.Builder
// (PartoutCore OnDemandModule+Extensions.swift). Writes `OnDemandModule`.
//
// Upstream shows the Mobile and "Ethernet (Mac/TV)" toggles on every
// platform, so this does too. Upstream fills a new SSID row with the current
// Wi-Fi name (CoreLocation); there is no Dartvel API for that yet, so a new
// row starts empty (see docs/DARTVEL-GAPS.md). Where the app can read the
// network itself (Linux, through NetworkManager) an "Add current Wi-Fi" row
// and a line saying what the rules do on the current network follow, as the
// WireGuard apps show; there the app also applies the rules
// (state/on_demand_store.dart).

import 'package:flutter/material.dart';

import '../../domain/on_demand_rules.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../platform/network/current_network.dart';
import '../../dartvel_client/dartvel_client.dart';
import '../kit.dart';
import 'common/editable_list_section.dart';
import 'common/module_builder_cache.dart';
import 'module_view.dart';

/// `OnDemandModule.Policy`, in upstream's picker order (paid builds).
const List<String> onDemandPolicies = <String>['any', 'excluding', 'including'];

String onDemandPolicyLabel(String policy) => switch (policy) {
      'excluding' => tr(Strings.entitiesOnDemandPolicyExcluding),
      'including' => tr(Strings.entitiesOnDemandPolicyIncluding),
      _ => tr(Strings.entitiesOnDemandPolicyAny),
    };

/// One Wi-Fi row: SSID and whether it is on.
typedef SsidEntry = ({String name, bool on});

/// `OnDemandModule.Builder`, with `withSSIDs` kept as ordered rows.
final class OnDemandBuilder {
  OnDemandBuilder({this.policy = 'any', List<ListItem<SsidEntry>>? ssids, List<String>? otherNetworks})
      : ssids = ssids ?? <ListItem<SsidEntry>>[],
        otherNetworks = otherNetworks ?? <String>[];

  factory OnDemandBuilder.fromModule(Map<String, dynamic> value) => OnDemandBuilder(
        policy: value['policy'] as String? ?? 'any',
        ssids: <ListItem<SsidEntry>>[
          for (final entry in ((value['withSSIDs'] as Map?) ?? const <String, dynamic>{}).entries)
            ListItem<SsidEntry>((name: '${entry.key}', on: entry.value == true)),
        ],
        otherNetworks: <String>[for (final network in (value['withOtherNetworks'] as List?) ?? const <dynamic>[]) '$network'],
      );

  String policy;
  List<ListItem<SsidEntry>> ssids;
  List<String> otherNetworks;

  bool _has(String network) => otherNetworks.contains(network);

  void _set(String network, bool value) {
    otherNetworks = <String>[...otherNetworks.where((other) => other != network), if (value) network];
  }

  bool get withMobileNetwork => _has('mobile');
  set withMobileNetwork(bool value) => _set('mobile', value);

  bool get withEthernetNetwork => _has('ethernet');
  set withEthernetNetwork(bool value) => _set('ethernet', value);

  /// `allSSIDs` setter: SSIDs that are new become off; a row renamed to an
  /// SSID already listed takes that SSID's state.
  void setSSIDs(List<ListItem<SsidEntry>> rows) {
    final previous = <int, SsidEntry>{for (final row in ssids) row.id: row.value};
    final next = <ListItem<SsidEntry>>[];
    for (final row in rows) {
      final before = previous[row.id];
      if (before != null && before.name != row.value.name) {
        final existing = ssids.where((other) => other.id != row.id && other.value.name == row.value.name).firstOrNull;
        next.add(row.copyWith((name: row.value.name, on: existing?.value.on ?? false)));
      } else {
        next.add(row);
      }
    }
    ssids = next;
  }

  /// `isSSIDOn(_:)` setter: `withSSIDs[ssid] = value`.
  void setSSIDOn(String name, bool value) {
    ssids = <ListItem<SsidEntry>>[
      for (final row in ssids) row.value.name == name ? row.copyWith((name: name, on: value)) : row,
    ];
  }

  /// `withSSIDs` as written: one key per SSID, first row wins.
  Map<String, bool> get withSSIDs {
    final map = <String, bool>{};
    for (final row in ssids) {
      map.putIfAbsent(row.value.name, () => row.value.on);
    }
    return map;
  }

  /// Adds [name] as an enabled SSID, or enables it when it is listed.
  void addSSID(String name) {
    if (ssids.any((row) => row.value.name == name)) {
      setSSIDOn(name, true);
    } else {
      ssids = <ListItem<SsidEntry>>[...ssids, ListItem<SsidEntry>((name: name, on: true))];
    }
  }

  /// `build()`.
  Map<String, Object?> get changes => <String, Object?>{
        'policy': policy,
        'withSSIDs': withSSIDs,
        'withOtherNetworks': <String>[...otherNetworks],
      };
}

final ModuleBuilderCache<OnDemandBuilder> onDemandBuilders = ModuleBuilderCache<OnDemandBuilder>(OnDemandBuilder.fromModule);

/// Upstream's `policyFooterDescription`.
String onDemandPolicyFooter(String policy) => tr(Strings.modulesOnDemandPolicyFooter, <Object>[
      switch (policy) {
        'including' => tr(Strings.modulesOnDemandPolicyFooterIncluding),
        'excluding' => tr(Strings.modulesOnDemandPolicyFooterExcluding),
        _ => tr(Strings.modulesOnDemandPolicyFooterAny),
      },
    ]);

/// On-demand module sections.
List<Widget> onDemandSections(BuildContext context, ModuleViewArgs args) {
  final builder = onDemandBuilders.resolve(args.module);
  void edit(void Function(OnDemandBuilder) change) {
    change(builder);
    args.onChanged(onDemandBuilders.write(args.module, builder, builder.changes));
  }

  return <Widget>[
    PSSection(
      footer: onDemandPolicyFooter(builder.policy),
      children: <Widget>[
        pickerRow<String>(
          title: tr(Strings.modulesOnDemandPolicy),
          value: builder.policy,
          options: onDemandPolicies,
          label: onDemandPolicyLabel,
          onChanged: (value) => edit((b) => b.policy = value),
        ),
      ],
    ),
    if (builder.policy != 'any') ...<Widget>[
      PSSection(
        header: tr(Strings.globalNounsNetworks),
        footer: tr(Strings.modulesOnDemandNetworksFooter),
        children: <Widget>[
          PSToggleRow(
            title: tr(Strings.modulesOnDemandMobile),
            value: builder.withMobileNetwork,
            onChanged: (value) => edit((b) => b.withMobileNetwork = value),
          ),
          PSToggleRow(
            title: '${tr(Strings.modulesOnDemandEthernet)} (Mac/TV)',
            value: builder.withEthernetNetwork,
            onChanged: (value) => edit((b) => b.withEthernetNetwork = value),
          ),
        ],
      ),
      editableListSection<SsidEntry>(
        key: const ValueKey<String>('onDemand/ssids'),
        header: 'Wi-Fi',
        addTitle: tr(Strings.modulesOnDemandSsidAdd),
        items: builder.ssids,
        emptyValue: () => (name: '', on: false),
        isEmptyValue: (value) => value.name.isEmpty,
        onChanged: (rows) => edit((b) => b.setSSIDs(rows)),
        itemBuilder: (context, item, setValue) => DVBox.row(
          <Widget>[
            Expanded(
              child: ListItemTextField(
                key: ValueKey<String>('onDemand/ssids/${item.id}'),
                value: item.value.name,
                placeholder: tr(Strings.placeholdersOnDemandSsid),
                semanticLabel: 'Wi-Fi',
                onChanged: (name) => setValue((name: name, on: item.value.on)),
              ),
            ),
            Tooltip(
              message: item.value.name.isEmpty ? 'Wi-Fi' : item.value.name,
              excludeFromSemantics: true,
              child: Semantics(
                label: item.value.name.isEmpty ? 'Wi-Fi' : item.value.name,
                child: Switch.adaptive(
                  key: ValueKey<String>('onDemand/ssids/${item.id}/on'),
                  value: builder.withSSIDs[item.value.name] ?? false,
                  onChanged: (value) => edit((b) => b.setSSIDOn(item.value.name, value)),
                ),
              ),
            ),
          ],
          spacing: 0,
          crossAlign: .center,
        ),
      ),
    ],
    if (CurrentNetwork.isSupported)
      OnDemandCurrentNetworkSection(
        module: Map<String, dynamic>.from(builder.changes),
        showsAddWifi: builder.policy != 'any',
        onAddWifi: (ssid) => edit((b) => b.addSSID(ssid)),
      ),
  ];
}

/// "Add current Wi-Fi" and what the rules do on the network the device is
/// on. The network is probed once, when the section first shows.
@DVFunctionalWidget()
Widget _onDemandCurrentNetworkSection(
  BuildContext context, {
  required Map<String, dynamic> module,
  required bool showsAddWifi,
  required ValueChanged<String> onAddWifi,
}) {
  final DVSignal<NetworkSnapshot?> probed = context.signal<NetworkSnapshot?>(null);
  runOnce(context, () {
    CurrentNetwork.probe().then((network) {
      if (context.mounted) probed.value = network;
    });
  });
  final network = probed.value;
  final ssid = network?.kind == .wifi ? network?.ssid : null;
  final decision = network == null ? null : evaluateOnDemand(module, network);
  final String? now = switch (decision) {
    .connect => AppStrings.onDemandNow(network!.label, AppStrings.onDemandConnect),
    .disconnect => AppStrings.onDemandNow(network!.label, AppStrings.onDemandDisconnect),
    _ => null,
  };
  return PSSection(
    footer: <String>[?now, AppStrings.onDemandArmedFooter].join('\n\n'),
    children: <Widget>[
      if (showsAddWifi)
        PSRow(
          title: AppStrings.addCurrentWifi,
          subtitle: ssid ?? AppStrings.noCurrentWifi,
          onTap: ssid == null ? null : () => onAddWifi(ssid),
        ),
    ],
  );
}
