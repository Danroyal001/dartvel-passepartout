// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Rule groups on the device, one JSON file per group under
// `rule-groups/<id>.json` in `DV.Platform.fileStorage`, next to the profiles.

import 'dart:convert';

import '../dartvel_client/dartvel_client.dart';
import '../domain/rule_groups.dart';
import 'app_log.dart';

export '../domain/rule_groups.dart';

class const RuleGroupsState({final List<RuleGroup> groups = const <RuleGroup>[], final bool isReady = false}) {
  /// Sorted by name.
  List<RuleGroup> get sorted =>
      <RuleGroup>[...groups]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  RuleGroup? byId(String id) {
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// The groups among [ids] that still exist, in [ids]' order.
  List<RuleGroup> resolve(List<String> ids) => ids.map(byId).whereType<RuleGroup>().toList();

  String firstUniqueName(String base) {
    final names = groups.map((group) => group.name).toSet();
    if (!names.contains(base)) return base;
    var index = 2;
    while (names.contains('$base $index')) {
      index++;
    }
    return '$base $index';
  }
}

const String _groupsPrefix = 'rule-groups/';

abstract final class RuleGroupStore {
  static RuleGroupsState get state {
    try {
      return DV.global<RuleGroupsState>();
    } on StateError {
      return const RuleGroupsState(); // init() not called (a test, the server)
    }
  }

  static void _set(RuleGroupsState next) => DV.global<RuleGroupsState>(next);

  static void init() => DV.global<RuleGroupsState>(const RuleGroupsState());

  static DVStorage get _disk => DV.Platform.fileStorage;

  static Future<void> load() async {
    final groups = <RuleGroup>[];
    try {
      for (final key in await _disk.list(prefix: _groupsPrefix)) {
        if (!key.endsWith('.json')) continue;
        try {
          groups.add(RuleGroup.fromJson(jsonDecode(utf8.decode(await _disk.get(key))) as Map<String, dynamic>));
        } on Object catch (error) {
          AppLog.warning('Skipping unreadable rule group $key: $error');
        }
      }
    } on Object catch (error) {
      AppLog.error('Unable to list rule groups: $error');
    }
    _set(RuleGroupsState(groups: groups, isReady: true));
  }

  static Future<void> save(RuleGroup group) async {
    await _disk.put('$_groupsPrefix${group.id}.json', utf8.encode(jsonEncode(group.toJson())),
        contentType: 'application/json');
    _set(RuleGroupsState(groups: <RuleGroup>[...state.groups.where((g) => g.id != group.id), group], isReady: true));
  }

  static Future<RuleGroup> create(String name) async {
    final group = RuleGroup.create(state.firstUniqueName(name));
    await save(group);
    return group;
  }

  /// Removes the group. Profiles that list it keep the id, which then
  /// matches nothing ([RuleGroupsState.resolve] skips it).
  static Future<void> remove(String id) async {
    await _disk.delete('$_groupsPrefix$id.json');
    _set(RuleGroupsState(groups: state.groups.where((g) => g.id != id).toList(), isReady: true));
  }
}
