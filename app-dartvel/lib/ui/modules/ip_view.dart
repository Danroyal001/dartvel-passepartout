// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// IP module editor: upstream IPView.swift, IPView+Route.swift and
// IPModule.Builder (PartoutCore IPModule+Extensions.swift). Writes `IPModule`
// with `IPSettings`, `Route` and `Subnet` of openapi.yaml.

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../dartvel_client/dartvel_client.dart';
import '../kit.dart';
import 'common/addresses.dart';
import 'common/module_builder_cache.dart';
import 'module_view.dart';

/// `IPSettings` as a module map, always with its three required lists.
Map<String, dynamic> _settings(Object? raw) {
  final value = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  return <String, dynamic>{
    ...value,
    'subnets': <dynamic>[...?(value['subnets'] as List?)],
    'includedRoutes': <dynamic>[...?(value['includedRoutes'] as List?)],
    'excludedRoutes': <dynamic>[...?(value['excludedRoutes'] as List?)],
  };
}

/// `IPSettings.nilIfEmpty`.
Map<String, dynamic>? _nilIfEmpty(Map<String, dynamic>? settings) {
  if (settings == null) return null;
  final empty = (settings['subnets'] as List).isEmpty &&
      (settings['includedRoutes'] as List).isEmpty &&
      (settings['excludedRoutes'] as List).isEmpty;
  return empty ? null : settings;
}

/// `IPModule.Builder`, plus IPView's `subnets` text state and the MTU text.
final class IpBuilder {
  IpBuilder({this.ipv4, this.ipv6, this.mtu = ''});

  factory IpBuilder.fromModule(Map<String, dynamic> value) {
    final builder = IpBuilder(
      ipv4: value['ipv4'] == null ? null : _settings(value['ipv4']),
      ipv6: value['ipv6'] == null ? null : _settings(value['ipv6']),
      mtu: value['mtu'] == null ? '' : '${value['mtu']}',
    );
    // IPView.loadSubnets(): the first subnet of each family.
    for (final family in AddressFamily.values) {
      final subnets = builder.settings(family)?['subnets'] as List?;
      if (subnets != null && subnets.isNotEmpty) builder.subnetText[family] = '${subnets.first}';
    }
    return builder;
  }

  Map<String, dynamic>? ipv4;
  Map<String, dynamic>? ipv6;
  String mtu;
  final Map<AddressFamily, String> subnetText = <AddressFamily, String>{};

  Map<String, dynamic>? settings(AddressFamily family) => family == .v4 ? ipv4 : ipv6;

  void _setSettings(AddressFamily family, Map<String, dynamic>? value) {
    if (family == .v4) {
      ipv4 = value;
    } else {
      ipv6 = value;
    }
  }

  /// IPView.saveSubnets(): `ipvX?.with(subnet:) ?? IPSettings(subnet:)`.
  void setSubnet(AddressFamily family, String text) {
    subnetText[family] = text;
    final subnet = ParsedSubnet.parse(text);
    final next = _settings(settings(family));
    next['subnets'] = <dynamic>[?subnet?.rawValue];
    _setSettings(family, next);
  }

  /// `IPSettings.include(_:)` / `exclude(_:)`, creating the settings if missing.
  void addRoute(AddressFamily family, Map<String, dynamic> route, {required bool included}) {
    final next = _settings(settings(family));
    final key = included ? 'includedRoutes' : 'excludedRoutes';
    next[key] = <dynamic>[...next[key] as List, route];
    _setSettings(family, next);
  }

  /// `removeIncluded(at:)` / `removeExcluded(at:)`.
  void removeRoute(AddressFamily family, int index, {required bool included}) {
    final next = _settings(settings(family));
    final key = included ? 'includedRoutes' : 'excludedRoutes';
    next[key] = <dynamic>[...next[key] as List]..removeAt(index);
    _setSettings(family, next);
  }

  /// `build()`: empty settings are omitted; an MTU that is not a number is omitted.
  Map<String, Object?> get changes => <String, Object?>{
        'ipv4': _nilIfEmpty(ipv4),
        'ipv6': _nilIfEmpty(ipv6),
        'mtu': swiftInt(mtu),
      };
}

final ModuleBuilderCache<IpBuilder> ipBuilders = ModuleBuilderCache<IpBuilder>(IpBuilder.fromModule);

/// RouteView.parseAndSubmit(): the route JSON, or null when upstream would
/// ignore the OK (destination not a subnet of [family], gateway of another family).
Map<String, dynamic>? parseRoute(AddressFamily family,
    {required bool isDefault, required String destination, required String gateway}) {
  if (isDefault) return <String, dynamic>{};
  final subnet = ParsedSubnet.parse(destination);
  if (subnet == null) return null;
  final gatewayAddress = ParsedAddress.parse(gateway);
  if (subnet.family != family) return null;
  if (gatewayAddress != null && gatewayAddress.family != family) return null;
  return <String, dynamic>{
    'destination': subnet.rawValue,
    'gateway': ?gatewayAddress?.rawValue,
  };
}

/// IP module sections.
List<Widget> ipSections(BuildContext context, ModuleViewArgs args) {
  final builder = ipBuilders.resolve(args.module);
  void edit(void Function(IpBuilder) change) {
    change(builder);
    args.onChanged(ipBuilders.write(args.module, builder, builder.changes));
  }

  Future<void> presentRoute(AddressFamily family, {required bool included}) async {
    final route = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => RouteDialog(
        family: family,
        title: tr(included ? Strings.modulesIpRoutesInclude : Strings.modulesIpRoutesExclude),
      ),
    );
    if (route != null) edit((b) => b.addRoute(family, route, included: included));
  }

  List<Widget> routeSection(AddressFamily family, {required bool included}) {
    final routes = (builder.settings(family)?[included ? 'includedRoutes' : 'excludedRoutes'] as List?) ?? const <dynamic>[];
    return <Widget>[
      PSSection(
        key: ValueKey<String>('ip/${family.name}/${included ? 'included' : 'excluded'}'),
        children: <Widget>[
          for (var i = 0; i < routes.length; i++)
            RouteRow(
              description: routeDescription(Map<String, dynamic>.from(routes[i] as Map)),
              onRemove: () => edit((b) => b.removeRoute(family, i, included: included)),
            ),
          PSRow(
            title: tr(included ? Strings.modulesIpRoutesInclude : Strings.modulesIpRoutesExclude),
            onTap: () => presentRoute(family, included: included),
          ),
        ],
      ),
    ];
  }

  return <Widget>[
    for (final family in AddressFamily.values) ...<Widget>[
      PSSection(
        header: family.label,
        footer: tr(Strings.modulesIpAddressFooter),
        children: <Widget>[
          PSTextRow(
            key: ValueKey<String>('ip/${family.name}/address'),
            label: tr(Strings.globalNounsAddress),
            value: builder.subnetText[family] ?? '',
            placeholder: family.destinationPlaceholder,
            onChanged: (value) => edit((b) => b.setSubnet(family, value)),
          ),
        ],
      ),
      ...routeSection(family, included: true),
      ...routeSection(family, included: false),
    ],
    PSSection(
      header: tr(Strings.globalNounsInterface),
      children: <Widget>[
        PSTextRow(
          key: const ValueKey<String>('ip/mtu'),
          label: 'MTU',
          value: builder.mtu,
          placeholder: '1500',
          onChanged: (value) => edit((b) => b.mtu = value),
        ),
      ],
    ),
  ];
}

/// `ThemeRemovableItemRow(isEditing: true)` around `ThemeCopiableText`.
@DVFunctionalWidget()
Widget _routeRow(BuildContext context, {required String description, required VoidCallback onRemove}) => DVBox.row(
      <Widget>[
        PSIconAction(
          icon: Icons.remove_circle,
          color: PSColors.error,
          label: tr(Strings.globalActionsDelete),
          onPressed: onRemove,
        ),
        Expanded(
          child: PSRow(
            title: description,
            trailing: PSIconAction(
              icon: Icons.copy,
              size: 18,
              label: AppStrings.copy,
              onPressed: () => copyToClipboard(context, description),
            ),
          ),
        ),
      ],
      spacing: 0,
      crossAlign: .center,
    );

/// IPView.RouteView, presented modally: Default toggle, destination and
/// gateway; OK submits only what upstream accepts.
@DVFunctionalWidget()
Widget _routeDialog(BuildContext context, {required AddressFamily family, required String title}) {
  final DVSignal<String> destination = context.signal<String>('');
  final DVSignal<String> gateway = context.signal<String>('');
  final DVSignal<bool> isDefault = context.signal<bool>(false);
  void submit() {
    final route = parseRoute(
      family,
      isDefault: isDefault.read(),
      destination: destination.read(),
      gateway: gateway.read(),
    );
    if (route != null) Navigator.of(context).pop(route);
  }

  return AlertDialog(
    title: DVText(title),
    contentPadding: const .symmetric(vertical: 12),
    content: DVBox(
      DVBox.list(
        <Widget>[
          PSToggleRow(
            title: tr(Strings.globalNounsDefault),
            value: isDefault.value,
            onChanged: (value) => isDefault.value = value,
          ),
          if (!isDefault.value) ...<Widget>[
            PSTextRow(
              key: const ValueKey<String>('route/destination'),
              label: tr(Strings.globalNounsDestination),
              value: destination.value,
              placeholder: family.destinationPlaceholder,
              onChanged: (value) => destination.value = value,
            ),
            PSTextRow(
              key: const ValueKey<String>('route/gateway'),
              label: tr(Strings.globalNounsGateway),
              value: gateway.value,
              placeholder: family.addressPlaceholder,
              onChanged: (value) => gateway.value = value,
              onSubmitted: (_) => submit(),
            ),
          ],
        ],
        spacing: 0,
      ),
      const DVModifier().width(420),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: DVText(tr(Strings.globalActionsCancel))),
      TextButton(onPressed: submit, child: DVText(tr(Strings.globalNounsOk))),
    ],
  );
}
