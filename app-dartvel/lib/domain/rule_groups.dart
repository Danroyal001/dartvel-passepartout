// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Rule groups: named, reusable sets of split-tunnel rules that live apart from
// profiles, so one set of "send these through the tunnel / keep these out"
// rules can be attached to many profiles and survives switching servers.
// The idea comes from the TunnlTo desktop app; this is our own design and
// code (TunnlTo's source is not used).
//
// A rule is an IP address, a CIDR block or a domain name. When a profile is
// connected, its attached groups become routes in an IP module of the copy of
// the profile handed to the engine; the saved profile never changes. Domains
// are resolved once, at connect time.
//
// Flutter-free and dart:io-free.

import 'ip_ranges.dart';
import 'profile.dart';

/// Where a profile stores the ids of the groups attached to it:
/// `userInfo.dartvel.ruleGroupIds` (openapi.yaml allows any `userInfo`).
const String _userInfoNamespace = 'dartvel';
const String _ruleGroupIdsKey = 'ruleGroupIds';

/// One reusable group of rules.
final class RuleGroup {
  const RuleGroup({
    required this.id,
    required this.name,
    this.included = const <String>[],
    this.excluded = const <String>[],
  });

  factory RuleGroup.create(String name) => RuleGroup(id: newUniqueId(), name: name);

  factory RuleGroup.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String || json['name'] is! String) throw const FormatException('Invalid rule group');
    List<String> strings(Object? value) => value is List ? value.map((entry) => '$entry').toList() : const <String>[];
    return RuleGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      included: strings(json['included']),
      excluded: strings(json['excluded']),
    );
  }

  final String id;
  final String name;

  /// Sent through the tunnel even when the connection would not route them.
  final List<String> included;

  /// Kept out of the tunnel (they use the normal network).
  final List<String> excluded;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'included': included,
        'excluded': excluded,
      };

  RuleGroup copyWith({String? name, List<String>? included, List<String>? excluded}) => RuleGroup(
        id: id,
        name: name ?? this.name,
        included: included ?? this.included,
        excluded: excluded ?? this.excluded,
      );

  /// "3 included, 1 excluded".
  String get summary => '${included.length} included, ${excluded.length} excluded';

  /// The first entry that is neither an IP/CIDR nor a domain name, or null.
  String? get firstInvalidRule {
    for (final rule in <String>[...included, ...excluded]) {
      if (RuleTarget.parse(rule) == null) return rule;
    }
    return null;
  }
}

/// What one rule names: an IP block, or a domain to resolve.
final class RuleTarget {
  const RuleTarget._({this.block, this.domain});

  final IpBlock? block;
  final String? domain;

  static final RegExp _domainPattern =
      RegExp(r'^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\.?$');

  /// Null when [rule] is neither.
  static RuleTarget? parse(String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return null;
    final block = IpBlock.tryParse(trimmed);
    if (block != null) return RuleTarget._(block: block);
    if (_domainPattern.hasMatch(trimmed)) return RuleTarget._(domain: trimmed.toLowerCase());
    return null;
  }
}

/// Resolves a domain to its IP addresses (literals). Injected so tests and
/// the web target need no network.
typedef DomainResolver = Future<List<String>> Function(String domain);

extension ProfileRuleGroups on TunnelProfile {
  /// The ids of the rule groups attached to this profile, in order.
  List<String> get ruleGroupIds {
    final userInfo = json['userInfo'];
    final namespace = userInfo is Map ? userInfo[_userInfoNamespace] : null;
    final ids = namespace is Map ? namespace[_ruleGroupIdsKey] : null;
    return ids is List ? ids.map((id) => '$id').toList() : const <String>[];
  }

  /// A copy with [ids] attached (an empty list removes the key). Other
  /// `userInfo` content is kept.
  TunnelProfile withRuleGroupIds(List<String> ids) {
    final userInfo = <String, dynamic>{...?(json['userInfo'] as Map?)?.cast<String, dynamic>()};
    final namespace = <String, dynamic>{...?(userInfo[_userInfoNamespace] as Map?)?.cast<String, dynamic>()};
    if (ids.isEmpty) {
      namespace.remove(_ruleGroupIdsKey);
    } else {
      namespace[_ruleGroupIdsKey] = ids.toSet().toList();
    }
    if (namespace.isEmpty) {
      userInfo.remove(_userInfoNamespace);
    } else {
      userInfo[_userInfoNamespace] = namespace;
    }
    final next = <String, dynamic>{...json};
    if (userInfo.isEmpty) {
      next.remove('userInfo');
    } else {
      next['userInfo'] = userInfo;
    }
    return TunnelProfile(json: next);
  }

  TunnelProfile togglingRuleGroup(String id) {
    final ids = ruleGroupIds;
    return withRuleGroupIds(ids.contains(id) ? (ids..remove(id)) : <String>[...ids, id]);
  }
}

/// The routes the attached groups add, split by family.
typedef RuleRoutes = ({List<String> includedV4, List<String> excludedV4, List<String> includedV6, List<String> excludedV6});

/// Turns [groups]' rules into routes. Domains go through [resolve]; one that
/// fails to resolve is skipped and reported through [onSkipped].
Future<RuleRoutes> ruleRoutes(
  List<RuleGroup> groups, {
  required DomainResolver resolve,
  void Function(String rule, Object reason)? onSkipped,
}) async {
  final includedV4 = <String>[], excludedV4 = <String>[], includedV6 = <String>[], excludedV6 = <String>[];
  void add(IpBlock block, bool included) {
    final list = block.isIPv4 ? (included ? includedV4 : excludedV4) : (included ? includedV6 : excludedV6);
    final text = block.toString();
    if (!list.contains(text)) list.add(text);
  }

  Future<void> collect(String rule, bool included) async {
    final target = RuleTarget.parse(rule);
    if (target == null) {
      onSkipped?.call(rule, 'not an IP, subnet or domain');
      return;
    }
    if (target.block != null) {
      add(target.block!, included);
      return;
    }
    try {
      for (final address in await resolve(target.domain!)) {
        final block = IpBlock.tryParse(address);
        if (block != null) add(block, included);
      }
    } on Object catch (error) {
      onSkipped?.call(rule, error);
    }
  }

  for (final group in groups) {
    for (final rule in group.included) {
      await collect(rule, true);
    }
    for (final rule in group.excluded) {
      await collect(rule, false);
    }
  }
  return (includedV4: includedV4, excludedV4: excludedV4, includedV6: includedV6, excludedV6: excludedV6);
}

/// The profile to hand the engine: [profile] with [routes] merged into its
/// active IP module, or into a new active IP module when it has none.
/// [profile] itself is not changed; with no routes it is returned as is.
TunnelProfile applyRuleRoutes(TunnelProfile profile, RuleRoutes routes) {
  final hasRoutes = routes.includedV4.isNotEmpty ||
      routes.excludedV4.isNotEmpty ||
      routes.includedV6.isNotEmpty ||
      routes.excludedV6.isNotEmpty;
  if (!hasRoutes) return profile;

  TaggedModule? ipModule;
  for (final module in profile.modules) {
    if (module.type == ModuleType.ip && profile.isActive(module.id)) {
      ipModule = module;
      break;
    }
  }
  final value = ipModule?.value ?? <String, dynamic>{'id': newUniqueId()};

  Map<String, dynamic>? merge(Object? settings, List<String> included, List<String> excluded) {
    if (settings == null && included.isEmpty && excluded.isEmpty) return null;
    final current = <String, dynamic>{...?(settings as Map?)?.cast<String, dynamic>()};
    List<dynamic> withRoutes(String key, List<String> destinations) {
      final routes = <dynamic>[...?(current[key] as List?)];
      final present = <String>{
        for (final route in routes)
          if (route is Map && route['destination'] is String) canonicalCidr(route['destination'] as String),
      };
      for (final destination in destinations) {
        if (present.add(destination)) routes.add(<String, dynamic>{'destination': destination});
      }
      return routes;
    }

    return <String, dynamic>{
      ...current,
      'subnets': current['subnets'] ?? <dynamic>[],
      'includedRoutes': withRoutes('includedRoutes', included),
      'excludedRoutes': withRoutes('excludedRoutes', excluded),
    };
  }

  final ipv4 = merge(value['ipv4'], routes.includedV4, routes.excludedV4);
  final ipv6 = merge(value['ipv6'], routes.includedV6, routes.excludedV6);
  final next = <String, dynamic>{...value, 'ipv4': ?ipv4, 'ipv6': ?ipv6};
  return profile.savingModule(TaggedModule.of(ModuleType.ip, next), activate: true);
}
