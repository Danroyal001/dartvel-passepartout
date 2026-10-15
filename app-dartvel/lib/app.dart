// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The application: its startup and its root widget. main.dart only runs it.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dartvel_client/dartvel_client.dart';
import 'l10n/strings.g.dart';
import 'platform/vpn_service.dart';
import 'platform/web_vpn_service.dart';
import 'state/app_log.dart';
import 'state/app_state.dart';
import 'state/on_demand_store.dart';
import 'state/profile_draft.dart';
import 'state/rule_groups_store.dart';
import 'ui/desktop_shell.dart';
import 'ui/kit.dart';

/// What must be in place before the first frame: the launch target, the
/// strings, the engine boundary and every store (empty).
Future<void> prepareDartvelVpn(List<String> arguments) async {
  // Where this launch renders: nothing to decide unless the build opted into
  // the terminal, in which case a launch with no display may leave for it.
  await negotiateDartvelLaunch(arguments);
  loadStrings();
  if (kIsWeb) VpnService.instance = const WebVpnService();
  AppLog.init();
  VpnService.log = AppLog.add;
  ProfileStore.init();
  TunnelStore.init();
  PreferencesStore.init();
  DraftStore.init();
  RuleGroupStore.init();
  OnDemandStore.init();
}

/// What fills in after the first frame: saved data, on-demand rules and the
/// desktop tray.
Future<void> loadDartvelVpn() async {
  await PreferencesStore.load();
  await ProfileStore.load();
  await RuleGroupStore.load();
  await OnDemandStore.load();
  OnDemandStore.start();
  await DesktopShell.start();
}

/// Upstream's 13 locales; the device language picks one, English otherwise.
void loadStrings() {
  const DVI18n().loadAll(stringCatalogs.values);
  final device = ui.PlatformDispatcher.instance.locale;
  final tag = device.scriptCode == 'Hans' || device.languageCode == 'zh' ? 'zh-Hans' : device.languageCode;
  const DVI18n().useLocale(LocaleTag(stringCatalogs.containsKey(tag) ? tag : 'en'));
}

// The arguments are what a file association, an app link or a second
// launch hands a desktop application; the router opens them.
Widget createDartvelApp({List<String> arguments = const <String>[]}) => DartvelVpnApp(arguments: arguments);

@DVFunctionalWidget()
Widget _dartvelVpnApp(BuildContext context, {required List<String> arguments}) {
  final appearance = context.global<Preferences>().appearance;
  return MaterialApp.router(
    title: 'Dartvel VPN',
    debugShowCheckedModeBanner: false,
    theme: passepartoutTheme(.light),
    darkTheme: passepartoutTheme(.dark),
    themeMode: switch (appearance) {
      .light => ThemeMode.light,
      .dark => ThemeMode.dark,
      .system => ThemeMode.system,
    },
    routerConfig: createDartvelRouter(arguments: arguments),
  );
}
