// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The profile list, the profile editor and "Import text": the behaviour each
// screen keeps however it is built (search and its shortcuts, the layout
// picker, the add menu, the editor's fields and save checks, pasting a
// profile). No engine: a fake service records what the screens ask of it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/dartvel_client/dartvel_client.dart';
import 'package:passepartout/domain/profile.dart';
import 'package:passepartout/l10n/app_strings.dart';
import 'package:passepartout/l10n/strings.g.dart';
import 'package:passepartout/platform/vpn_service.dart';
import 'package:passepartout/state/app_state.dart';
import 'package:passepartout/state/profile_draft.dart';
import 'package:passepartout/ui/kit.dart';
import 'package:passepartout/ui/screens/import_text_screen.dart';
import 'package:passepartout/ui/screens/profile_editor_screen.dart';
import 'package:passepartout/ui/screens/profiles_screen.dart';

import 'support/app_harness.dart';

class _FakeEngine implements VpnService {
  final List<String> connected = <String>[];
  final List<String> imported = <String>[];

  @override
  Future<void> connect(TunnelProfile profile, {required void Function(TunnelEvent) onStatus}) async {
    connected.add(profile.name);
  }

  @override
  Future<TunnelProfile> importProfile(String text, String name) async {
    imported.add(text);
    return TunnelProfile.empty(name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('not in this test');
}

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Lets the storage's real futures finish (a spinner never settles), then draws.
Future<void> _drain(WidgetTester tester) async {
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late _FakeEngine engine;

  setUp(() {
    DVDeviceStorage.useAdapters(DVMemoryFileStorageAdapter());
    setUpApp();
    engine = _FakeEngine();
    VpnService.instance = engine;
  });
  tearDown(DVDeviceStorage.reset);

  final office = TunnelProfile.empty('Office');
  final home = TunnelProfile.empty('Home');

  group('profile list', () {
    testWidgets('search filters the list; Enter connects the first match', (tester) async {
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office, home]));
      await tester.pumpWidget(appUnderTest(const ProfilesScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Office'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'off');
      await tester.pumpAndSettle();
      expect(ProfileStore.state.search, 'off');
      expect(find.text('Home'), findsNothing);
      expect(find.text('Office'), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(engine.connected, <String>['Office']);
    });

    testWidgets('Ctrl+K puts the focus in the search field', (tester) async {
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office]));
      await tester.pumpWidget(appUnderTest(const ProfilesScreen()));
      await tester.pumpAndSettle();
      final field = find.byType(EditableText);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
      // A shortcut needs the focus inside the screen, as on a desktop.
      Focus.of(tester.element(find.text('Office'))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
    });

    testWidgets('wide window: the layout picker switches to the grid', (tester) async {
      _window(tester, const Size(1200, 900));
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office]));
      await tester.pumpWidget(appUnderTest(const ProfilesScreen()));
      await tester.pumpAndSettle();
      expect(find.byTooltip(tr(Strings.globalNounsSettings)), findsOneWidget);
      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pumpAndSettle();
      expect(PreferencesStore.state.layout, ProfilesLayout.grid);
      // A grid cell has an edit button named for what it does.
      expect(find.byTooltip(tr(Strings.globalActionsEdit)), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
    });

    testWidgets('the add menu lists the ways to add a profile', (tester) async {
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office]));
      await tester.pumpWidget(appUnderTest(const ProfilesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tr(Strings.globalActionsAdd)));
      await tester.pumpAndSettle();
      expect(find.text(tr(Strings.viewsAppToolbarNewProfileEmpty)), findsOneWidget);
      expect(find.text('${tr(Strings.viewsAppToolbarImportTextTitle)}...'), findsOneWidget);
      expect(find.text('${AppStrings.exportAll}...'), findsOneWidget);
    });

    testWidgets('a profile row opens its context menu on a long press', (tester) async {
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office]));
      await tester.pumpWidget(appUnderTest(const ProfilesScreen()));
      await tester.pumpAndSettle();
      await tester.longPress(find.descendant(of: find.byType(ProfileRow), matching: find.text('Office')));
      await tester.pumpAndSettle();
      expect(find.text(tr(Strings.globalActionsReconnect)), findsOneWidget);
      expect(find.text(tr(Strings.globalActionsDuplicate)), findsOneWidget);
    });
  });

  group('profile editor', () {
    testWidgets('edits the name in the draft; saving an empty profile is refused', (tester) async {
      _window(tester, const Size(900, 2400));
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office]));
      await tester.pumpWidget(appUnderTest(ProfileEditorScreen(profileId: office.id)));
      await tester.pumpAndSettle();
      expect(find.byTooltip(AppStrings.copy), findsOneWidget);
      expect(find.text(tr(Strings.viewsProfileRowsDeleteProfile)), findsOneWidget);
      expect(find.text(tr(Strings.viewsProfileRowsAddModule)), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Office 2');
      await tester.pumpAndSettle();
      expect(DraftStore.state.profile?.name, 'Office 2');

      await tester.tap(find.text(tr(Strings.globalActionsSave)));
      await tester.pumpAndSettle();
      expect(find.text(tr(Strings.errorsAppNoActiveModules)), findsOneWidget);
      expect(ProfileStore.state.byId(office.id)?.name, 'Office', reason: 'nothing saved');
    });

    testWidgets('behavior toggles change the draft', (tester) async {
      _window(tester, const Size(900, 2400));
      DV.global<ProfilesState>(ProfilesState(isReady: true, profiles: <TunnelProfile>[office]));
      await tester.pumpWidget(appUnderTest(ProfileEditorScreen(profileId: office.id)));
      await tester.pumpAndSettle();
      final before = DraftStore.state.profile!.includesAllNetworks;
      await tester.tap(find.text(tr(Strings.modulesGeneralRowsEnforceTunnel)));
      await tester.pumpAndSettle();
      expect(DraftStore.state.profile!.includesAllNetworks, !before);
    });
  });

  group('import text', () {
    testWidgets('Import is enabled once there is text, and imports it', (tester) async {
      await tester.pumpWidget(appUnderTest(const ImportTextScreen()));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(TextButton, tr(Strings.globalActionsImport));
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue, reason: 'autofocus');

      await tester.enterText(find.byType(TextField), '[Interface]\nPrivateKey = x');
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await _drain(tester);
      expect(engine.imported, <String>['[Interface]\nPrivateKey = x']);
      expect(ProfileStore.state.profiles.map((p) => p.name), <String>[tr(Strings.placeholdersProfileImportedName)]);
    });

    testWidgets('Ctrl+Enter imports', (tester) async {
      await tester.pumpWidget(appUnderTest(const ImportTextScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'client');
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _drain(tester);
      expect(engine.imported, <String>['client']);
    });
  });
}
