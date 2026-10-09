// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Text for Dartvel VPN features that upstream Passepartout does not have, so
// its catalogues (strings.g.dart) have no key for them. English only for now;
// they move into a catalogue when the app gets its own translations.

abstract final class AppStrings {
  // Import and export
  static const String importQrFromImage = 'Import QR code from image';
  static const String importQrNoConfig = 'This QR code does not hold a WireGuard or OpenVPN configuration.';
  static const String exportProfile = 'Export configuration';
  static const String exportAll = 'Export all to zip';
  static const String exportNothing = 'No profile has a WireGuard or OpenVPN connection to export.';
  static String exportedCount(int exported, int skipped) =>
      skipped == 0 ? 'Exported $exported profiles.' : 'Exported $exported profiles; $skipped without a connection were left out.';
  static String importedCount(int imported, List<String> failed) => failed.isEmpty
      ? 'Imported $imported profiles.'
      : 'Imported $imported profiles. Could not import: ${failed.join(', ')}.';
  static const String saveUnavailable = 'Saving files is not available on this device yet.';

  // WireGuard
  static const String excludePrivateIps = 'Exclude private IPs';
  static const String excludePrivateIpsFooter =
      'Keeps local networks (10.x, 172.16-31.x, 192.168.x, link-local and multicast) out of the tunnel, '
      'so printers and routers stay reachable. Private DNS servers of this interface stay in the tunnel.';

  // On-demand
  static const String addCurrentWifi = 'Add current Wi-Fi';
  static const String noCurrentWifi = 'Not connected to a Wi-Fi network with a known name.';
  static String onDemandNow(String network, String decision) => 'On this network ($network) the profile would $decision.';
  static const String onDemandConnect = 'connect';
  static const String onDemandDisconnect = 'disconnect';
  static const String onDemandArmedFooter =
      'When you turn this profile on, the app follows these rules as the network changes. Turning it off by hand stops that until you turn it on again.';

  // Rule groups
  static const String ruleGroups = 'Rule groups';
  static const String ruleGroup = 'Rule group';
  static const String newRuleGroup = 'New rule group';
  static const String addRuleGroup = 'Add rule group';
  static const String noRuleGroups = 'No rule groups';
  static const String ruleGroupsFooter =
      'Rule groups are lists of addresses, subnets and domains to send through the tunnel or keep out of it. '
      'One group can be used by many profiles, so changing server keeps your rules.';
  static const String profileRuleGroupsFooter =
      'The rules of the groups turned on here are added as routes when this profile connects. Domains are looked up when it connects.';
  static const String includedRules = 'Through the tunnel';
  static const String excludedRules = 'Outside the tunnel';
  static const String includedRulesFooter = 'Addresses, subnets (10.0.0.0/8) or domains (example.com) always sent through the tunnel.';
  static const String excludedRulesFooter = 'Addresses, subnets or domains that use your normal connection instead.';
  static const String rulePlaceholder = '10.0.0.0/8 or example.com';
  static String invalidRule(String rule) => '"$rule" is not an IP address, a subnet or a domain.';
  static const String manageRuleGroups = 'Manage rule groups';
  static const String deleteRuleGroup = 'Delete rule group';

  // Search and stats
  static const String search = 'Search';
  static const String searchHint = 'Search name or server';
  static String connectedFor(String duration) => 'connected for $duration';
}
