// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
// Port of upstream `WireGuardView` and `WireGuardView.ConfigurationView`
// (app-apple/Sources/AppLibraryMain/Views/Modules/WireGuard).

import 'package:flutter/material.dart';

import '../../domain/ip_ranges.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../platform/vpn_service.dart';
import '../kit.dart';
import 'module_view.dart';
import 'wireguard/wireguard_configuration.dart';
import 'wireguard/wireguard_import.dart';
import 'wireguard/wireguard_issues.dart';
import 'wireguard/wireguard_rows.dart';

/// Upstream `Strings.Unlocalized.Placeholders` for MTU and keep-alive.
const String _mtuPlaceholder = '1500';
const String _keepAlivePlaceholder = '30';

/// WireGuard module sections: the import button, then (when the module has a
/// configuration) interface, addresses/MTU, DNS, one section per peer and
/// "Add peer", in upstream's order.
List<Widget> wireGuardSections(BuildContext context, ModuleViewArgs args) {
  final configuration = WireGuardConfiguration(module: args.module);
  return <Widget>[
    WireGuardImportSection(args: args),
    if (configuration.hasConfiguration) ..._configurationSections(context, args, configuration),
  ];
}

/// The page of one long-content field (`ThemeLongContentLink`'s editor), at
/// `/profiles/<id>/modules/<moduleId>/<section>`: `private-key`, `addresses`,
/// `dns-servers`, `dns-domains`, and `peer-<n>-public-key`,
/// `peer-<n>-preshared-key`, `peer-<n>-endpoint`, `peer-<n>-allowed-ips`
/// (n counts from 1, as "Peer #n" does).
Widget? wireGuardSubpage(BuildContext context, ModuleViewArgs args, String section) {
  final field = _WireGuardField.parse(args, section);
  if (field == null) return null;
  final check = field.check;
  return PSLongContentPage(
    title: field.title,
    text: field.text,
    keyboardType: field.keyboardType,
    onChanged: field.onChanged,
    validate: check == null ? null : (text) => wireGuardFieldError(check, text),
  );
}

/// One field edited on its own page: what its row shows and its page edits.
class const _WireGuardField({
  required final String section,
  required final String title,
  required final String text,
  required final ValueChanged<String> onChanged,
  final String? Function(String text)? preview,
  final TextInputType? keyboardType,
  final WireGuardIssue? Function(String text)? check,
}) {
  /// The field [section] names in [args]' module, or null when there is none.
  static _WireGuardField? parse(ModuleViewArgs args, String section) {
    final configuration = WireGuardConfiguration(module: args.module);
    if (!configuration.hasConfiguration) return null;
    for (final field in _interfaceFields(args, configuration)) {
      if (field.section == section) return field;
    }
    final match = RegExp(r'^peer-(\d+)-').firstMatch(section);
    final peerNumber = match == null ? null : int.tryParse(match.group(1)!);
    final peers = configuration.peers;
    if (peerNumber == null || peerNumber < 1 || peerNumber > peers.length) return null;
    for (final field in _peerFields(args, peers[peerNumber - 1], peerNumber - 1)) {
      if (field.section == section) return field;
    }
    return null;
  }

  /// The row, flagged with [issues]' entry for this field (checks that need
  /// the whole configuration, such as duplicate peer keys, are in there).
  Widget row(ModuleViewArgs args, Map<String, WireGuardIssue> issues) {
    final issue = issues[section];
    return PSLongContentRow(
      title: title,
      text: text,
      preview: preview,
      error: issue == null ? null : wireGuardIssueText(issue),
      onTap: () => pushModuleSection(args, section),
    );
  }
}

/// Edits go to the draft's current module: the args a page holds are rebuilt
/// on every draft change, so [ModuleViewArgs.module] is always the latest.
WireGuardConfiguration _current(ModuleViewArgs args) => WireGuardConfiguration(module: args.module);

List<_WireGuardField> _interfaceFields(ModuleViewArgs args, WireGuardConfiguration configuration) => <_WireGuardField>[
      _WireGuardField(
        section: 'private-key',
        title: tr(Strings.globalNounsPrivateKey),
        text: configuration.privateKey,
        check: WireGuardValidation.privateKey,
        onChanged: (text) => args.onChanged(_current(args).withPrivateKey(text)),
      ),
      _WireGuardField(
        section: 'addresses',
        title: tr(Strings.globalNounsAddresses),
        text: configuration.addressesText,
        preview: asNumberOfEntries,
        check: WireGuardValidation.addresses,
        keyboardType: TextInputType.url,
        onChanged: (text) => args.onChanged(_current(args).withAddresses(text)),
      ),
      _WireGuardField(
        section: 'dns-servers',
        title: tr(Strings.globalNounsServers),
        text: configuration.dnsServersText,
        preview: asNumberOfEntries,
        check: WireGuardValidation.dnsServers,
        keyboardType: TextInputType.url,
        onChanged: (text) => args.onChanged(_current(args).withDnsServers(text)),
      ),
      _WireGuardField(
        section: 'dns-domains',
        title: tr(Strings.entitiesDnsSearchDomains),
        text: configuration.dnsDomainsText,
        preview: asNumberOfEntries,
        onChanged: (text) => args.onChanged(_current(args).withDnsDomains(text)),
      ),
    ];

List<_WireGuardField> _peerFields(ModuleViewArgs args, WireGuardPeer peer, int index) {
  void edit(WireGuardPeer Function(WireGuardPeer peer) change) {
    final current = _current(args);
    if (index >= current.peers.length) return;
    args.onChanged(current.withPeer(index, change(current.peers[index])));
  }

  final prefix = 'peer-${index + 1}';
  return <_WireGuardField>[
    _WireGuardField(
      section: '$prefix-public-key',
      title: tr(Strings.globalNounsPublicKey),
      text: peer.publicKey,
      check: WireGuardValidation.publicKey,
      onChanged: (text) => edit((peer) => peer.withPublicKey(text)),
    ),
    _WireGuardField(
      section: '$prefix-preshared-key',
      title: tr(Strings.modulesWireguardPresharedKey),
      text: peer.preSharedKey,
      check: WireGuardValidation.preSharedKey,
      onChanged: (text) => edit((peer) => peer.withPreSharedKey(text)),
    ),
    _WireGuardField(
      section: '$prefix-endpoint',
      title: tr(Strings.globalNounsEndpoint),
      text: peer.endpoint,
      check: WireGuardValidation.endpoint,
      onChanged: (text) => edit((peer) => peer.withEndpoint(text)),
    ),
    _WireGuardField(
      section: '$prefix-allowed-ips',
      title: tr(Strings.modulesWireguardAllowedIps),
      text: peer.allowedIPsText,
      preview: asNumberOfEntries,
      check: WireGuardValidation.allowedIPs,
      keyboardType: TextInputType.url,
      onChanged: (text) => edit((peer) => peer.withAllowedIPs(text)),
    ),
  ];
}

List<Widget> _configurationSections(BuildContext context, ModuleViewArgs args, WireGuardConfiguration configuration) {
  final peers = configuration.peers;
  final interfaceFields = _interfaceFields(args, configuration);
  final issues = WireGuardValidation.configuration(configuration.rawConfiguration);
  return <Widget>[
    // privateKeySection
    PSSection(header: tr(Strings.modulesWireguardInterface), children: <Widget>[
      interfaceFields[0].row(args, issues),
      WireGuardPublicKeyRow(privateKey: configuration.privateKey),
      PSRow(
        title: tr(Strings.modulesWireguardPrivateKeyGenerate),
        onTap: () => runGuarded(context, () async {
          final privateKey = await VpnService.instance.generateWireGuardKey();
          args.onChanged(_current(args).withPrivateKey(privateKey));
        }),
      ),
    ]),
    // interfaceSection
    PSSection(children: <Widget>[
      interfaceFields[1].row(args, issues),
      PSTextRow(
        label: 'MTU',
        value: configuration.mtuText,
        placeholder: _mtuPlaceholder,
        keyboardType: TextInputType.number,
        error: issues['mtu'] == null ? null : wireGuardIssueText(issues['mtu']!),
        onChanged: (text) => args.onChanged(_current(args).withMtu(text)),
      ),
    ]),
    // dnsSection
    PSSection(header: 'DNS', footer: tr(Strings.modulesWireguardInterfaceDnsFooter), children: <Widget>[
      interfaceFields[2].row(args, issues),
      interfaceFields[3].row(args, issues),
    ]),
    // peerSections
    for (var index = 0; index < peers.length; index++) _peerSection(args, peers[index], index, issues),
    // addPeerButton
    PSSection(children: <Widget>[
      Opacity(
        opacity: configuration.canAddPeer ? 1 : 0.4,
        child: PSRow(
          title: tr(Strings.modulesWireguardPeerAdd),
          onTap: configuration.canAddPeer ? () => args.onChanged(_current(args).addingPeer()) : null,
        ),
      ),
    ]),
  ];
}

Widget _peerSection(
  ModuleViewArgs args,
  WireGuardPeer peer,
  int index,
  Map<String, WireGuardIssue> issues,
) {
  final keepAliveIssue = issues['peer-${index + 1}-keep-alive'];
  final canExclude = PrivateIpExclusion.isAvailable(peer.allowedIPs);
  return PSSection(
      key: ValueKey<String>('wireguard-peer-$index'),
      header: tr(Strings.modulesWireguardPeer, <Object>[index + 1]),
      footer: canExclude ? AppStrings.excludePrivateIpsFooter : null,
      children: <Widget>[
        for (final field in _peerFields(args, peer, index)) field.row(args, issues),
        if (canExclude)
          PSToggleRow(
            key: ValueKey<String>('wireguard-peer-$index-exclude-private'),
            title: AppStrings.excludePrivateIps,
            value: PrivateIpExclusion.isOn(peer.allowedIPs),
            onChanged: (on) {
              final current = _current(args);
              if (index >= current.peers.length) return;
              final allowed = current.peers[index].allowedIPs;
              final dns = current.dnsServers;
              final next = on
                  ? PrivateIpExclusion.excluding(allowed, dnsServers: dns)
                  : PrivateIpExclusion.including(allowed, dnsServers: dns);
              args.onChanged(current.withPeer(index, current.peers[index].withAllowedIPs(next.join(wireGuardListSeparator))));
            },
          ),
        PSTextRow(
          label: tr(Strings.globalNounsKeepAlive),
          value: peer.keepAliveText,
          placeholder: _keepAlivePlaceholder,
          keyboardType: TextInputType.number,
          error: keepAliveIssue == null ? null : wireGuardIssueText(keepAliveIssue),
          onChanged: (text) {
            final current = _current(args);
            args.onChanged(current.withPeer(index, current.peers[index].withKeepAlive(text)));
          },
        ),
        PSRow(
          title: tr(Strings.modulesWireguardPeerDelete),
          destructive: true,
          onTap: () => args.onChanged(_current(args).removingPeer(index)),
        ),
      ],
    );
}
