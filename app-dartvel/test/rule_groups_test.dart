// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/dartvel_client/dartvel_client.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/l10n/app_strings.dart';
import 'package:passepartout/l10n/strings.g.dart';
import 'package:passepartout/platform/network/domain_resolver.dart';
import 'package:passepartout/state/app_state.dart';
import 'package:passepartout/state/rule_groups_store.dart';
import 'package:passepartout/ui/kit.dart';

import 'support/app_harness.dart';

Future<List<String>> _resolver(String domain) async => switch (domain) {
      'example.com' => <String>['93.184.216.34', '2606:2800:220:1::1'],
      'dup.example' => <String>['93.184.216.34'],
      _ => throw StateError('NXDOMAIN'),
    };

RuleRoutes _routes({List<String> v4In = const <String>[], List<String> v4Out = const <String>[]}) =>
    (includedV4: v4In, excludedV4: v4Out, includedV6: const <String>[], excludedV6: const <String>[]);

void main() {
  test('RuleGroup JSON round trip and validation', () {
    final group = RuleGroup.create('Work').copyWith(included: <String>['10.0.0.0/8', 'intranet.example.com'], excluded: <String>['bad rule']);
    final copy = RuleGroup.fromJson(jsonDecode(jsonEncode(group.toJson())) as Map<String, dynamic>);
    expect(copy.toJson(), group.toJson());
    expect(copy.summary, '2 included, 1 excluded');
    expect(copy.firstInvalidRule, 'bad rule');
    expect(() => RuleGroup.fromJson(<String, dynamic>{'name': 'x'}), throwsFormatException);
  });

  test('rule targets', () {
    expect(RuleTarget.parse('10.1.2.3')!.block.toString(), '10.1.2.3/32');
    expect(RuleTarget.parse('Example.COM')!.domain, 'example.com');
    expect(RuleTarget.parse('sub.example.co.uk.')!.domain, 'sub.example.co.uk.');
    for (final bad in <String>['', 'localhost', 'exa mple.com', '-bad.com', '10.0.0.0/40']) {
      expect(RuleTarget.parse(bad), isNull, reason: bad);
    }
  });

  test('profiles keep group ids in userInfo without touching other keys', () {
    final profile = TunnelProfile(json: <String, dynamic>{
      ...TunnelProfile.empty('P').json,
      'userInfo': <String, dynamic>{'other': 1},
    });
    expect(profile.ruleGroupIds, isEmpty);
    final attached = profile.togglingRuleGroup('A').togglingRuleGroup('B');
    expect(attached.ruleGroupIds, <String>['A', 'B']);
    expect(attached.json['userInfo']['other'], 1);
    final detached = attached.togglingRuleGroup('A').togglingRuleGroup('B');
    expect(detached.ruleGroupIds, isEmpty);
    expect(detached.json['userInfo'], <String, dynamic>{'other': 1}, reason: 'empty namespace removed');
    expect(TunnelProfile.empty('Q').withRuleGroupIds(<String>[]).json.containsKey('userInfo'), isFalse);
  });

  test('rules become routes; domains resolve; failures are skipped and reported', () async {
    final skipped = <String>[];
    final routes = await ruleRoutes(
      <RuleGroup>[
        RuleGroup.create('A').copyWith(included: <String>['10.0.0.0/8', 'example.com', 'missing.example'], excluded: <String>['192.168.1.0/24']),
        RuleGroup.create('B').copyWith(included: <String>['dup.example', '10.0.0.0/8'], excluded: <String>['not a rule', 'fd00::/8']),
      ],
      resolve: _resolver,
      onSkipped: (rule, _) => skipped.add(rule),
    );
    expect(routes.includedV4, <String>['10.0.0.0/8', '93.184.216.34/32'], reason: 'deduplicated');
    expect(routes.includedV6, <String>['2606:2800:220:1::1/128']);
    expect(routes.excludedV4, <String>['192.168.1.0/24']);
    expect(routes.excludedV6, <String>['fd00::/8']);
    expect(skipped, <String>['missing.example', 'not a rule']);
  });

  group('applyRuleRoutes', () {
    test('adds an active IP module when the profile has none', () {
      final profile = TunnelProfile.empty('P').savingModule(TaggedModule.empty(ModuleType.dns));
      final applied = applyRuleRoutes(profile, _routes(v4In: <String>['10.0.0.0/8'], v4Out: <String>['192.168.0.0/16']));
      final ip = applied.modules.singleWhere((m) => m.type == ModuleType.ip);
      expect(applied.isActive(ip.id), isTrue);
      expect(ip.value['ipv4'], <String, dynamic>{
        'subnets': <dynamic>[],
        'includedRoutes': <dynamic>[<String, dynamic>{'destination': '10.0.0.0/8'}],
        'excludedRoutes': <dynamic>[<String, dynamic>{'destination': '192.168.0.0/16'}],
      });
      expect(ip.value.containsKey('ipv6'), isFalse, reason: 'no IPv6 rules, no IPv6 settings');
      expect(profile.modules.where((m) => m.type == ModuleType.ip), isEmpty, reason: 'the saved profile is untouched');
    });

    test('merges into the active IP module without duplicating routes', () {
      final ipModule = TaggedModule.of(ModuleType.ip, <String, dynamic>{
        'id': 'IP1',
        'mtu': 1400,
        'ipv4': <String, dynamic>{
          'subnets': <dynamic>['10.8.0.2/24'],
          'includedRoutes': <dynamic>[<String, dynamic>{'destination': '10.0.0.0/8', 'gateway': '10.8.0.1'}],
          'excludedRoutes': <dynamic>[],
        },
      });
      final profile = TunnelProfile.empty('P').savingModule(ipModule);
      final applied = applyRuleRoutes(profile, _routes(v4In: <String>['10.0.0.0/8', '172.16.0.0/12']));
      final ip = applied.module('IP1')!;
      expect(applied.modules, hasLength(1));
      expect(ip.value['mtu'], 1400);
      expect((ip.value['ipv4'] as Map)['subnets'], <dynamic>['10.8.0.2/24']);
      expect((ip.value['ipv4'] as Map)['includedRoutes'], <dynamic>[
        <String, dynamic>{'destination': '10.0.0.0/8', 'gateway': '10.8.0.1'},
        <String, dynamic>{'destination': '172.16.0.0/12'},
      ]);
    });

    test('no routes, no change', () {
      final profile = TunnelProfile.empty('P');
      expect(applyRuleRoutes(profile, _routes()), same(profile));
    });
  });

  group('stores', () {
    late DVMemoryFileStorageAdapter disk;

    setUp(() {
      disk = DVMemoryFileStorageAdapter();
      DVDeviceStorage.useAdapters(disk);
      setUpApp();
    });
    tearDown(DVDeviceStorage.reset);

    test('RuleGroupStore saves, loads and removes', () async {
      final group = await RuleGroupStore.create('Work');
      expect((await RuleGroupStore.create('Work')).name, 'Work 2');
      await RuleGroupStore.save(group.copyWith(included: <String>['10.0.0.0/8']));
      expect(await disk.exists('rule-groups/${group.id}.json'), isTrue);
      RuleGroupStore.init();
      await disk.put('rule-groups/broken.json', utf8.encode('{'));
      await RuleGroupStore.load();
      expect(RuleGroupStore.state.sorted.map((g) => g.name), <String>['Work', 'Work 2']);
      expect(RuleGroupStore.state.byId(group.id)!.included, <String>['10.0.0.0/8']);
      expect(RuleGroupStore.state.resolve(<String>['missing', group.id]).single.id, group.id);
      await RuleGroupStore.remove(group.id);
      expect(RuleGroupStore.state.byId(group.id), isNull);
    });

    testWidgets('list: the add button is named and creates a group', (tester) async {
      await tester.pumpWidget(appUnderTest(const RuleGroupsScreen()));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noRuleGroups), findsOneWidget);
      expect(find.byTooltip(AppStrings.addRuleGroup), findsWidgets);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip(AppStrings.addRuleGroup).first);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(RuleGroupStore.state.sorted.map((g) => g.name), <String>[AppStrings.newRuleGroup]);
      expect(find.text(AppStrings.newRuleGroup), findsOneWidget);
      expect(find.text(AppStrings.noRuleGroups), findsNothing);
    });

    testWidgets('editor: rules save as typed, empty rows left out', (tester) async {
      late RuleGroup group;
      await tester.runAsync(() async {
        group = await RuleGroupStore.create('Work');
        await RuleGroupStore.save(group.copyWith(included: <String>['10.0.0.0/8']));
      });
      await tester.pumpWidget(appUnderTest(RuleGroupEditorScreen(groupId: group.id)));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.excludedRules.toUpperCase()), findsOneWidget);
      await tester.runAsync(() async {
        await tester.enterText(find.widgetWithText(TextField, '10.0.0.0/8'), '10.1.0.0/16');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(RuleGroupStore.state.byId(group.id)!.included, <String>['10.1.0.0/16']);
      // Add: a new empty row, not saved while empty.
      await tester.tap(find.text(tr(Strings.globalActionsAdd)).first);
      await tester.pumpAndSettle();
      expect(RuleGroupStore.state.byId(group.id)!.included, <String>['10.1.0.0/16']);
      // The name saves too.
      await tester.runAsync(() async {
        await tester.enterText(find.widgetWithText(TextField, 'Work'), 'Office');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(RuleGroupStore.state.byId(group.id)!.name, 'Office');
      expect(find.text('10.1.0.0/16'), findsOneWidget, reason: 'rows keep their text across rebuilds');
    });

    testWidgets('editor: delete asks first; cancel keeps the group', (tester) async {
      late RuleGroup group;
      await tester.runAsync(() async => group = await RuleGroupStore.create('Work'));
      await tester.pumpWidget(appUnderTest(RuleGroupEditorScreen(groupId: group.id)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(AppStrings.deleteRuleGroup), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(AppStrings.deleteRuleGroup));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(tr(Strings.globalActionsCancel)));
      await tester.pumpAndSettle();
      expect(RuleGroupStore.state.byId(group.id), isNotNull);
    });

    test('connect hands the engine the profile with its groups applied', () async {
      DomainResolution.resolve = _resolver;
      final group = await RuleGroupStore.create('Sites');
      await RuleGroupStore.save(group.copyWith(excluded: <String>['example.com']));
      final profile = TunnelProfile.empty('P').savingModule(TaggedModule.empty(ModuleType.dns)).togglingRuleGroup(group.id);
      final engineProfile = await TunnelStore.withRuleGroups(profile);
      final ip = engineProfile.modules.singleWhere((m) => m.type == ModuleType.ip);
      expect((ip.value['ipv4'] as Map)['excludedRoutes'], <dynamic>[<String, dynamic>{'destination': '93.184.216.34/32'}]);
      expect((ip.value['ipv6'] as Map)['excludedRoutes'], <dynamic>[<String, dynamic>{'destination': '2606:2800:220:1::1/128'}]);
      expect(await TunnelStore.withRuleGroups(TunnelProfile.empty('none')), isA<TunnelProfile>());
    });
  });
}
