// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
// Localised text for WireGuard field checks (domain/wireguard_validation.dart),
// using the messages upstream already ships (errors.wireguard.*).

import '../../../domain/wireguard_validation.dart';
import '../../../l10n/strings.g.dart';
import '../../kit.dart';

export '../../../domain/wireguard_validation.dart';

String wireGuardIssueText(WireGuardIssue issue) => switch (issue.kind) {
      .privateKeyRequired => tr(Strings.errorsWireguardInterfacePrivateKeyRequired),
      .privateKeyInvalid => tr(Strings.errorsWireguardInterfacePrivateKeyInvalid),
      .addressInvalid => tr(Strings.errorsWireguardInterfaceAddressInvalid, <Object>[issue.value]),
      .mtuInvalid => tr(Strings.errorsWireguardInterfaceMtuInvalid, <Object>[issue.value]),
      .dnsInvalid => tr(Strings.errorsWireguardInterfaceDnsInvalid, <Object>[issue.value]),
      .publicKeyRequired => tr(Strings.errorsWireguardPeerPublicKeyRequired),
      .publicKeyInvalid => tr(Strings.errorsWireguardPeerPublicKeyInvalid),
      .publicKeyDuplicated => tr(Strings.errorsWireguardPeerPublicKeyDuplicated),
      .preSharedKeyInvalid => tr(Strings.errorsWireguardPeerPreSharedKeyInvalid),
      .allowedIPsInvalid => tr(Strings.errorsWireguardPeerAllowedIpsInvalid, <Object>[issue.value]),
      .endpointInvalid => tr(Strings.errorsWireguardPeerEndpointInvalid, <Object>[issue.value]),
      .keepAliveInvalid => tr(Strings.errorsWireguardPeerPersistentKeepaliveInvalid, <Object>[issue.value]),
    };

/// The localised issue of one field's text, or null when it is valid.
String? wireGuardFieldError(WireGuardIssue? Function(String text) check, String text) {
  final issue = check(text);
  return issue == null ? null : wireGuardIssueText(issue);
}
