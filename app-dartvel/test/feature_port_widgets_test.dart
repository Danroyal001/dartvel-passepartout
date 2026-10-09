// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev
// Widget tests of the features ported from the WireGuard apps and TunnlTo:
// inline WireGuard field errors, "Exclude private IPs", rule groups.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/dartvel_client/dartvel_client.dart';
import 'package:passepartout/domain/ip_ranges.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/l10n/app_strings.dart';
import 'package:passepartout/platform/vpn_service.dart';
import 'package:passepartout/state/rule_groups_store.dart';
import 'package:passepartout/ui/kit.dart';
import 'package:passepartout/ui/modules/module_view.dart';
import 'package:passepartout/ui/modules/wireguard/wireguard_configuration.dart';
import 'package:passepartout/ui/modules/wireguard_view.dart';
import 'package:passepartout/ui/settings/rule_groups_screen.dart';

import 'support/app_harness.dart';

class _NoEngine implements VpnService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('no engine in this test');
}

TaggedModule _module({String endpoint = 'wg.example.com:51820', List<String> allowed = const <String>['0.0.0.0/0', '::/0']}) =>
    TaggedModule.of(ModuleType.wireGuard, <String, dynamic>{
      'id': 'WG',
      'configuration': <String, dynamic>{
        'interface': <String, dynamic>{
          'privateKey': '4hBza7JtPKZFKwqtEmDR0iZyru1kqpQta/DRduMbHQw=',
          'addresses': <dynamic>['10.0.0.2/32'],
          'dns': <String, dynamic>{'id': 'D', 'protocolType': <String, dynamic>{'type': 'cleartext'}, 'servers': <dynamic>['10.64.0.1']},
        },
        'peers': <dynamic>[
          <String, dynamic>{'publicKey': 'muwialz9E36nXp9qgbGIxwMrH+5Ovr8d7cutH8JHdvE=', 'allowedIPs': allowed, 'endpoint': endpoint},
        ],
      },
    });

class _Host extends StatefulWidget {
  const _Host({required this.initial});

  final TaggedModule initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late TaggedModule module = widget.initial;

  @override
  Widget build(BuildContext context) => PSScaffold(
        title: 'WireGuard',
        body: Builder(
          builder: (context) => PSForm(
            children: wireGuardSections(
              context,
              ModuleViewArgs(profileId: 'P', module: module, onChanged: (next) => setState(() => module = next)),
            ),
          ),
        ),
      );
}

/// A tall window, so every section of the long WireGuard form is built.
void _tallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() {
    setUpApp();
    VpnService.instance = _NoEngine();
  });

  testWidgets('an invalid endpoint is flagged next to its row', (tester) async {
    _tallWindow(tester);
    await tester.pumpWidget(appUnderTest(_Host(initial: _module(endpoint: 'wg.example.com'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Endpoint ‘wg.example.com’ is invalid'), findsOneWidget);
    expect(find.byType(PSFieldError), findsOneWidget);
  });

  testWidgets('a valid configuration shows no errors', (tester) async {
    _tallWindow(tester);
    await tester.pumpWidget(appUnderTest(_Host(initial: _module())));
    await tester.pumpAndSettle();
    expect(find.byType(PSFieldError), findsNothing);
  });

  testWidgets('Exclude private IPs rewrites AllowedIPs and back', (tester) async {
    _tallWindow(tester);
    await tester.pumpWidget(appUnderTest(_Host(initial: _module())));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey<String>('wireguard-peer-0-exclude-private'));
    expect(tester.widget<PSToggleRow>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final host = tester.state<_HostState>(find.byType(_Host));
    final allowed = WireGuardConfiguration(module: host.module).peers.single.allowedIPs;
    expect(allowed, containsAll(publicIpv4Blocks));
    expect(allowed, containsAll(<String>['::/0', '10.64.0.1/32']));
    expect(tester.widget<PSToggleRow>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(WireGuardConfiguration(module: host.module).peers.single.allowedIPs, <String>['0.0.0.0/0', '::/0']);
  });

  testWidgets('no Exclude private IPs toggle for a split peer', (tester) async {
    _tallWindow(tester);
    await tester.pumpWidget(appUnderTest(_Host(initial: _module(allowed: <String>['10.0.0.0/24']))));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.excludePrivateIps), findsNothing);
  });

  testWidgets('rule group editor flags a bad rule and saves good ones', (tester) async {
    DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
    addTearDown(DVDeviceStorage.reset);
    late RuleGroup group;
    await tester.runAsync(() async {
      group = await RuleGroupStore.create('Work');
      await RuleGroupStore.save(group.copyWith(included: <String>['10.0.0.0/8', 'not a rule']));
    });
    await tester.pumpWidget(appUnderTest(RuleGroupEditorScreen(groupId: group.id)));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.includedRules.toUpperCase()), findsOneWidget);
    expect(find.text(AppStrings.invalidRule('not a rule')), findsOneWidget);
    expect(find.text('10.0.0.0/8'), findsOneWidget);
  });

  testWidgets('rule groups list shows each group with its summary', (tester) async {
    DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
    addTearDown(DVDeviceStorage.reset);
    await tester.runAsync(() async {
      final group = await RuleGroupStore.create('Streaming');
      await RuleGroupStore.save(group.copyWith(excluded: <String>['example.com']));
    });
    await tester.pumpWidget(appUnderTest(const RuleGroupsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('0 included, 1 excluded'), findsOneWidget);
  });
}
