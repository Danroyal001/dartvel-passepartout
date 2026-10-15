// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Upstream `DiagnosticsView`, `ReportIssueButton` and `DebugLogView`.
//
// Sections, in upstream order:
//   Live log: App, Tunnel
//   Extensive logging, Include private data
//   Active profiles (only when a profile is active)
//   Tunnel: Remove tunnel logs + one row per saved tunnel log, newest first
//   Restore network (Dartvel VPN; only where a tunnel can run)
//   Report issue
//
// Log pages, each at its own URL:
//   /settings/diagnostics/log                           app log (live)
//   /settings/diagnostics/log?source=tunnel             newest tunnel log, re-read every second
//   /settings/diagnostics/log?source=tunnel&file=<name> one saved tunnel log

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../platform/vpn_service.dart';
import '../../state/app_log.dart';
import '../../state/app_state.dart';
import '../kit.dart';
import 'settings_support.dart';
import 'tunnel_log_access.dart';

export 'tunnel_log_access.dart';

/// The queries that pick which log [LiveLogScreen] shows.
const String logSourceQuery = 'source';
const String logFileQuery = 'file';
const String tunnelLogSource = 'tunnel';

DVRouteTarget tunnelLogRoute([String? fileName]) => DVRoutes.settingsdiagnosticslog.withQuery(<String, String>{
      logSourceQuery: tunnelLogSource,
      logFileQuery: ?fileName,
    });

/// `computedTunnelLogs()`: the saved tunnel logs, newest first, or none when
/// they cannot be listed.
Future<List<TunnelLogEntry>> loadTunnelLogEntries(TunnelLogAccess access) async {
  try {
    return await access.entries();
  } on Object catch (error) {
    AppLog.warning('Unable to list tunnel logs: $error');
    return const <TunnelLogEntry>[];
  }
}

/// `removeTunnelLogs()`, after the confirmation every destructive action gets
/// here; [entries] then holds what is left.
Future<void> removeTunnelLogs(BuildContext context, TunnelLogAccess access, DVSignal<List<TunnelLogEntry>> entries) async {
  final title = tr(Strings.viewsDiagnosticsRowsRemoveTunnelLogs);
  if (!await confirmDestructive(context, title: title, action: title)) return;
  if (!context.mounted) return;
  await runGuarded(context, access.deleteAll);
  entries.value = await loadTunnelLogEntries(access);
}

/// "Restore network" (Dartvel VPN, not in upstream): undoes what a killed
/// tunnel helper left behind. A failure shows the error alert, success a
/// snack bar; [isPending] is true while the helper works (not while the
/// alert is open).
Future<void> restoreNetwork(BuildContext context, DVSignal<bool> isPending) => runGuarded(context, () async {
      isPending.value = true;
      try {
        await VpnService.instance.restoreNetwork();
      } finally {
        isPending.value = false;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: DVText(AppStrings.networkRestored)));
      }
    });

@DVFunctionalWidget()
Widget _diagnosticsScreen(BuildContext context, {TunnelLogAccess tunnelLogs = const TunnelLogAccess()}) {
  final DVSignal<List<TunnelLogEntry>> logs = context.signal<List<TunnelLogEntry>>(const <TunnelLogEntry>[]);
  final DVSignal<bool> isRestoring = context.signal<bool>(false);
  runOnce(context, () async => logs.value = await loadTunnelLogEntries(tunnelLogs));

  final preferences = context.global<Preferences>();
  final tunnel = context.global<TunnelState>();
  final profiles = context.global<ProfilesState>();
  final tunnelLogEntries = logs.value;
  final restoring = isRestoring.value;
  void update(Preferences Function(Preferences) change) => runGuarded(context, () => PreferencesStore.update(change));

  // `activeHeaders`: profiles the tunnel holds, sorted.
  final activeNames = <String>[
    if (tunnel.activeProfileId != null && tunnel.status != .disconnected)
      profiles.byId(tunnel.activeProfileId!)?.name ?? tunnel.activeProfileId!,
  ]..sort();

  return PSScaffold(
    title: tr(Strings.viewsDiagnosticsTitle),
    body: PSForm(children: <Widget>[
      PSSection(header: tr(Strings.viewsDiagnosticsSectionsLive), children: <Widget>[
        PSRow(
          title: tr(Strings.viewsDiagnosticsRowsApp),
          navigates: true,
          onTap: () => pushRoute(DVRoutes.settingsdiagnosticslog),
        ),
        PSRow(
          title: tr(Strings.viewsDiagnosticsRowsTunnel),
          navigates: true,
          onTap: () => pushRoute(tunnelLogRoute()),
        ),
      ]),
      PSSection(children: <Widget>[
        PSToggleRow(
          title: tr(Strings.viewsDiagnosticsRowsExtensiveLogging),
          subtitle: tr(Strings.viewsDiagnosticsRowsExtensiveLoggingSubtitle),
          value: preferences.extensiveLogging,
          onChanged: (value) => update((current) => current.copyWith(extensiveLogging: value)),
        ),
        PSToggleRow(
          title: tr(Strings.viewsDiagnosticsRowsIncludePrivateData),
          subtitle: tr(Strings.viewsDiagnosticsRowsIncludePrivateDataSubtitle),
          value: preferences.logsPrivateData,
          onChanged: (value) => update((current) => current.copyWith(logsPrivateData: value)),
        ),
      ]),
      if (activeNames.isNotEmpty)
        // Upstream links each to `DiagnosticsProfileView` (the OpenVPN
        // server configuration the tunnel received). The engine does not
        // report it yet, so the rows name the profiles only.
        PSSection(
          header: tr(Strings.viewsDiagnosticsSectionsActiveProfiles),
          children: <Widget>[for (final name in activeNames) PSRow(title: name)],
        ),
      PSSection(header: tr(Strings.viewsDiagnosticsSectionsTunnel), children: <Widget>[
        PSRow(
          title: tr(Strings.viewsDiagnosticsRowsRemoveTunnelLogs),
          destructive: tunnelLogEntries.isNotEmpty,
          onTap: tunnelLogEntries.isEmpty ? null : () => removeTunnelLogs(context, tunnelLogs, logs),
        ),
        for (final entry in tunnelLogEntries)
          PSRow(
            title: tunnelLogTitle(context, entry),
            navigates: true,
            onTap: () => pushRoute(tunnelLogRoute(entry.name)),
          ),
      ]),
      // Only where a tunnel can run, so only where one can have left anything behind.
      if (VpnService.instance.canConnect)
        PSSection(footer: AppStrings.restoreNetworkFooter, children: <Widget>[
          PSRow(
            title: AppStrings.restoreNetwork,
            trailing: restoring ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            onTap: restoring ? null : () => restoreNetwork(context, isRestoring),
          ),
        ]),
      const PSSection(children: <Widget>[ReportIssueButton()]),
    ]),
  );
}

/// `appFormatter.string(from: item.date)`, or the file name without a date.
String tunnelLogTitle(BuildContext context, TunnelLogEntry entry) {
  final date = entry.date;
  if (date == null) return entry.name;
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(date)} '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
}

/// `ReportIssueButton`: asks for a comment, then writes the email upstream
/// sends (issue.txt template) through `mailto:`, as upstream's fallback does
/// when it cannot compose mail itself. `mailto:` carries no attachments.
@DVFunctionalWidget()
Widget _reportIssueButton(BuildContext context, {String? title}) {
  final DVSignal<bool> isPending = context.signal<bool>(false);
  final pending = isPending.value;
  Future<void> report() async {
    final comment = await showDialog<String>(context: context, builder: (context) => const ReportIssueCommentDialog());
    if (comment == null || comment.trim().isEmpty || !context.mounted) return;
    isPending.value = true;
    try {
      openExternalUrl(reportIssueMailto(comment.trim()));
    } finally {
      isPending.value = false;
    }
  }

  return PSRow(
    title: title ?? tr(Strings.viewsDiagnosticsReportIssueTitle),
    trailing: pending ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
    onTap: pending ? null : report,
  );
}

/// The comment [ReportIssueButton] asks for; pops with it on Send.
@DVFunctionalWidget()
Widget _reportIssueCommentDialog(BuildContext context) {
  final DVSignal<String> comment = context.signal<String>('');
  final text = comment.value;
  return AlertDialog(
    title: DVText(tr(Strings.viewsDiagnosticsReportIssueTitle)),
    content: DVText(
      text,
      const DVModifier().input(
        label: tr(Strings.globalNounsComment),
        multiline: true,
        onChanged: (value) => comment.value = value,
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: () => Navigator.of(context).pop(), child: DVText(tr(Strings.globalActionsCancel))),
      TextButton(
        onPressed: text.trim().isEmpty ? null : () => Navigator.of(context).pop(text),
        child: DVText(tr(Strings.globalActionsSend)),
      ),
    ],
  );
}

/// Upstream's issue.txt filled in, as a `mailto:` URL.
String reportIssueMailto(String comment) {
  final body = reportIssueBody(comment);
  return 'mailto:${SettingsConstants.issuesEmail}'
      '?subject=${Uri.encodeComponent(SettingsUnlocalized.issueSubject)}'
      '&body=${Uri.encodeComponent(body)}';
}

String reportIssueBody(String comment) {
  final os = kIsWeb ? 'web' : defaultTargetPlatform.name;
  return 'Hi,\n\n$comment\n\n--\n\n'
      'App: ${SettingsUnlocalized.appName} ${SettingsBundle.versionString} [dartvel]\n'
      'OS: $os\n'
      'Device: unknown\n'
      'Purchased: []\n\n--\n\nRegards';
}

// ---------------------------------------------------------------------------

/// Reads the tunnel log [LiveLogScreen] shows: the saved one named [file], or
/// the newest. Sets [entry] and [lines] only when they changed, so the live
/// log, re-read every second, rebuilds only when it grew.
Future<void> readTunnelLog(
  TunnelLogAccess access,
  String? file,
  DVSignal<TunnelLogEntry?> entry,
  DVSignal<List<String>> lines,
) async {
  try {
    final next = file == null ? (await access.entries()).firstOrNull : await access.byName(file);
    final nextLines = next == null ? const <String>[] : await access.lines(next);
    if (next?.path != entry.read()?.path) entry.value = next;
    if (!listEquals(nextLines, lines.read())) lines.value = nextLines;
  } on Object catch (error) {
    AppLog.warning('Unable to read tunnel log: $error');
  }
}

/// `DebugLogView` + `DebugLogContentView`: the app log, or a tunnel log
/// (`?source=tunnel`, `&file=<name>`), selectable, with copy, share and clear.
///
/// [source] is `tunnel`, or null for the app log; [file] is a saved tunnel
/// log's name. Both are read from the URL when null. [pollInterval] is how
/// often the live tunnel log is re-read.
@DVFunctionalWidget()
Widget _liveLogScreen(
  BuildContext context, {
  String? source,
  String? file,
  TunnelLogAccess tunnelLogs = const TunnelLogAccess(),
  Duration pollInterval = const Duration(seconds: 1),
}) {
  // Which log this page shows is settled by its first build (a signal keeps
  // its first value): the URL on screen changes when a page is pushed above.
  final query = currentRouteQuery(context);
  final isTunnel = context.signal<bool>((source ?? query[logSourceQuery]) == tunnelLogSource).read();
  final fileName = context.signal<String?>(file ?? query[logFileQuery]).read();
  final DVSignal<TunnelLogEntry?> entry = context.signal<TunnelLogEntry?>(null);
  final DVSignal<List<String>> tunnelLines = context.signal<List<String>>(const <String>[]);
  runOnce(context, () {
    if (!isTunnel) return;
    readTunnelLog(tunnelLogs, fileName, entry, tunnelLines);
    // A saved log is read once, as upstream's `DebugLogView(withURL:)`; the
    // live one follows the newest file while this page is open. This is
    // `everyWhileMounted` started only for the live log: the others need no
    // timer at all.
    if (fileName != null) return;
    Timer.periodic(pollInterval, (timer) {
      if (!context.mounted) {
        timer.cancel();
        return;
      }
      readTunnelLog(tunnelLogs, fileName, entry, tunnelLines);
    });
  });

  final appLines = context.global<AppLogLines>().lines;
  final lines = isTunnel ? tunnelLines.value : <String>[for (final line in appLines) '$line'];
  final shownEntry = entry.value;
  final text = lines.join('\n');
  final title = !isTunnel
      ? tr(Strings.viewsDiagnosticsRowsApp)
      : (fileName != null && shownEntry != null)
          ? tunnelLogTitle(context, shownEntry)
          : tr(Strings.viewsDiagnosticsRowsTunnel);

  return PSScaffold(
    title: title,
    // A DVIconButton is always enabled: with no lines, each does nothing.
    actions: <Widget>[
      DVIconButton(
        icon: Icons.copy,
        label: AppStrings.copy,
        onPressed: () {
          if (lines.isNotEmpty) copyToClipboard(context, text);
        },
      ),
      DVIconButton(
        icon: Icons.share,
        label: tr(Strings.globalActionsShare),
        onPressed: () {
          if (lines.isNotEmpty) runGuarded(context, () => DV.Platform.share.shareText(text));
        },
      ),
      if (!isTunnel)
        DVIconButton(
          icon: Icons.delete_outline,
          label: tr(Strings.globalActionsRemove),
          onPressed: () {
            if (lines.isNotEmpty) AppLog.clear();
          },
        ),
    ],
    body: lines.isEmpty
        ? PSEmptyMessage(text: tr(Strings.globalNounsNoContent))
        : Scrollbar(
            child: SingleChildScrollView(
              padding: const .all(16),
              child: DVText(text, const DVModifier().fontFamily('monospace').fontSize(12)),
            ),
          ),
  );
}
