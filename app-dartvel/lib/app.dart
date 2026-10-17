// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The application: its startup and its root widget. main.dart only runs it.

import 'dart:async';
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

/// Startup: the empty stores are in place at once; the saved data fills
/// them in the background, so the first frame does not wait on the disk.
@DVBoot()
void _startDartvelVpn(DVBoot boot) {
  prepareDartvelVpn();
  unawaited(loadDartvelVpn());
}

/// What must be in place before the first frame: the strings, the engine
/// boundary and every store (empty). DV.run has already chosen where this
/// launch renders.
void prepareDartvelVpn() {
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

/// The application root: the framework's router (which opens the launch
/// arguments a file association, an app link or a second launch hands a
/// desktop application) in the theme the person chose.
@DVAppRoot()
Widget _dartvelVpnRoot(BuildContext context, DVAppParts parts) {
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
    routerConfig: parts.router,
  );
}
