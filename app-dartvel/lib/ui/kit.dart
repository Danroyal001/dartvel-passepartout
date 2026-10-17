// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The shared look: upstream's `themeForm()` grouped lists, rows, toggles and
// status colours. Every screen builds from these so the app reads as one, and
// so a screen ported by anyone matches the Apple layout row for row.
//
// Each widget here is a private `@DVFunctionalWidget` function; Dartvel
// generates the public widget (`_pSRow` -> `PSRow`), which every page reaches
// through the dartvel_client barrel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import '../l10n/app_strings.dart';
import '../l10n/strings.g.dart';
import '../state/app_state.dart';

/// Upstream `Theme`: accent, active/pending/error colours.
abstract final class PSColors {
  /// `darkAccentColor` 0x515d70, upstream's brand blue-grey.
  static const Color brand = Color(0xFF515D70);
  /// Logo gold, upstream's `lightAccentColor`.
  static const Color gold = Color(0xFFD4A63A);
  static const Color active = Color(0xFF00AA00);
  static const Color pending = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);

  static Color status(BuildContext context, TunnelState tunnel, String profileId) {
    if (tunnel.activeProfileId == profileId && tunnel.lastErrorCode != null) return error;
    return switch (tunnel.statusOf(profileId)) {
      .connected => active,
      .connecting || .disconnecting => pending,
      .disconnected => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }

  /// Secondary text: values, footers, headers.
  static Color secondary(BuildContext context) => Theme.of(context).colorScheme.onSurfaceVariant;
}

ThemeData dartvelVpnTheme(Brightness brightness) {
  final dark = brightness == .dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: PSColors.brand,
    brightness: brightness,
    primary: dark ? const Color(0xFF8FA3C2) : PSColors.brand,
    surface: dark ? const Color(0xFF1C1C1E) : Colors.white,
  );
  // iOS grouped background: systemGroupedBackground.
  final grouped = dark ? Colors.black : const Color(0xFFF2F2F7);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: grouped,
    appBarTheme: AppBarTheme(
      backgroundColor: grouped,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: .w600,
        color: scheme.onSurface,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), thickness: 0.5, space: 0.5),
    // iOS switch: green track, white thumb, no outline.
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? const Color(0xFF34C759) : (dark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA))),
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll<Icon?>(null),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: .symmetric(horizontal: 16), minVerticalPadding: 10),
  );
}

ThemeData passepartoutTheme(Brightness brightness) => dartvelVpnTheme(brightness);

/// `Strings.x` resolved in the current locale, with `{0}`, `{1}` arguments.
String tr(DVTranslationKey key, [List<Object> args = const <Object>[]]) => const DVI18n().t(
      key,
      args: <String, String>{for (var i = 0; i < args.length; i++) '$i': '${args[i]}'},
    );

/// A grouped form page body: a centred, readable column of [PSSection]s.
@DVFunctionalWidget()
Widget _pSForm(BuildContext context, {required List<Widget> children, double maxWidth = 720}) => DVBox.scrollableList(
      <Widget>[
        for (final child in children) DVBox(child, DVModifier().maxWidth(maxWidth).centered()),
      ],
      modifier: DVModifier().paddingSymmetric(vertical: 8),
      spacing: 0,
    );

/// An inset grouped section: optional header, rows on a rounded card, optional footer.
@DVFunctionalWidget()
Widget _pSSection(
  BuildContext context, {
  String? header,
  String? footer,
  required List<Widget> children,
  Widget? headerTrailing,
}) {
  final theme = Theme.of(context);
  final secondary = PSColors.secondary(context);
  final rows = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    if (i > 0) rows.add(DVBox(const Divider(), DVModifier().paddingOnly(left: 16)));
    rows.add(children[i]);
  }
  return DVBox.list(
    <Widget>[
      if (header != null || headerTrailing != null)
        DVBox.row(
          <Widget>[
            if (header != null)
              Expanded(
                child: DVText(
                  header.toUpperCase(),
                  DVModifier().color(secondary).fontSize(12).letterSpacing(0.3).semanticHeading(2),
                ),
              ),
            ?headerTrailing,
          ],
          modifier: DVModifier().paddingOnly(left: 16, top: 8, right: 8, bottom: 6),
          align: .spaceBetween,
          crossAlign: .center,
        ),
      if (rows.isNotEmpty)
        Material(
          color: theme.colorScheme.surface,
          borderRadius: .circular(10),
          clipBehavior: .antiAlias,
          child: DVBox.list(rows, spacing: 0),
        ),
      if (footer != null)
        DVText(footer, DVModifier().color(secondary).fontSize(12).paddingOnly(left: 16, top: 6, right: 16)),
    ],
    modifier: DVModifier().paddingOnly(left: 16, top: 8, right: 16, bottom: 12),
    spacing: 0,
  );
}

/// A row: title, optional subtitle/value, optional chevron when it navigates.
/// A row that does something on tap has a tooltip: its [tooltip], or its title.
@DVFunctionalWidget()
Widget _pSRow(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? value,
  Widget? leading,
  Widget? trailing,
  VoidCallback? onTap,
  bool navigates = false,
  bool destructive = false,
  bool monospaced = false,
  bool error = false,
  String? tooltip,
}) {
  final theme = Theme.of(context);
  final titleColor = destructive
      ? PSColors.error
      : (onTap != null && !navigates && trailing == null && value == null)
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface;
  final valueStyle = monospaced
      ? DVModifier().color(PSColors.secondary(context)).fontFamily('monospace')
      : DVModifier().color(PSColors.secondary(context));
  final tile = ListTile(
    leading: leading,
    title: DVText(title, DVModifier().color(titleColor)),
    subtitle: subtitle == null ? null : (error ? PSFieldError(text: subtitle) : DVText(subtitle, valueStyle)),
    trailing: DVBox.row(
      <Widget>[
        if (value != null) DVText(value, valueStyle.maxWidth(260).maxLines(1)),
        ?trailing,
        if (navigates) Icon(Icons.chevron_right, color: PSColors.secondary(context).withValues(alpha: 0.6)),
      ],
      spacing: 4,
      crossAlign: .center,
    ),
    onTap: onTap,
  );
  if (onTap == null) return tile;
  return Tooltip(message: tooltip ?? title, excludeFromSemantics: true, child: tile);
}

/// A toggle row. The whole row toggles, as on iOS; the switch is named by the title.
@DVFunctionalWidget()
Widget _pSToggleRow(
  BuildContext context, {
  required String title,
  String? subtitle,
  required bool value,
  required ValueChanged<bool>? onChanged,
}) =>
    Tooltip(
      message: title,
      excludeFromSemantics: true,
      child: SwitchListTile.adaptive(
        title: DVText(title),
        subtitle: subtitle == null ? null : DVText(subtitle, DVModifier().color(PSColors.secondary(context))),
        value: value,
        onChanged: onChanged,
      ),
    );

/// A labelled text field row (`ThemeTextField`). The label names the field to
/// screen readers and floats above it once there is text.
@DVFunctionalWidget()
Widget _pSTextRow(
  BuildContext context, {
  required String label,
  required String value,
  required ValueChanged<String> onChanged,
  String? placeholder,
  bool obscure = false,
  ValueChanged<String>? onSubmitted,
  String? error,
}) =>
    DVText(
      value,
      DVModifier()
          .input(
            label: label,
            hint: placeholder,
            obscureText: obscure,
            error: error,
            onChanged: onChanged,
            onSubmitted: onSubmitted == null ? null : () => onSubmitted(value),
          )
          .paddingSymmetric(horizontal: 16, vertical: 4),
    );

/// A picker row (`Picker` in a Form): title left, current choice right, menu
/// on tap. Picks by index into [labels]; [pickerRow] is the typed front.
@DVFunctionalWidget()
Widget _pSPickerRow(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required int selected,
  required ValueChanged<int>? onChanged,
}) {
  final secondary = PSColors.secondary(context);
  final current = selected >= 0 && selected < labels.length ? labels[selected] : '';
  return MenuAnchor(
    menuChildren: <Widget>[
      for (var i = 0; i < labels.length; i++)
        MenuItemButton(
          leadingIcon: Icon(i == selected ? Icons.check : null, size: 18),
          onPressed: onChanged == null ? null : () => onChanged(i),
          child: DVText(labels[i]),
        ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: '$title: $current',
      excludeFromSemantics: true,
      child: ListTile(
        title: DVText(title),
        trailing: DVBox.row(
          <Widget>[
            DVText(current, DVModifier().color(secondary)),
            Icon(Icons.unfold_more, size: 18, color: secondary),
          ],
          spacing: 4,
          crossAlign: .center,
        ),
        onTap: onChanged == null ? null : () => controller.isOpen ? controller.close() : controller.open(),
      ),
    ),
  );
}

/// [PSPickerRow] for any option type.
Widget pickerRow<T>({
  required String title,
  required T value,
  required List<T> options,
  required String Function(T) label,
  required ValueChanged<T>? onChanged,
}) =>
    PSPickerRow(
      title: title,
      labels: <String>[for (final option in options) label(option)],
      selected: options.indexOf(value),
      onChanged: onChanged == null ? null : (index) => onChanged(options[index]),
    );

/// The connect switch (`TunnelToggle`).
@DVFunctionalWidget()
Widget _tunnelToggle(BuildContext context, {required String profileId, String? semanticLabel}) {
  final tunnel = context.global<TunnelState>();
  final profile = context.global<ProfilesState>().byId(profileId);
  final on = tunnel.statusOf(profileId) == .connected || tunnel.statusOf(profileId) == .connecting;
  final name = semanticLabel ?? profile?.name ?? '';
  return Tooltip(
    message: name,
    excludeFromSemantics: true,
    child: Semantics(
      label: name,
      child: Switch.adaptive(
        value: on,
        onChanged: profile == null ? null : (_) => runGuarded(context, () => TunnelStore.toggle(profile)),
      ),
    ),
  );
}

/// "Active", "Activating"... with the on-demand suffix, coloured by status
/// (`ConnectionStatusText`).
@DVFunctionalWidget()
Widget _connectionStatusText(BuildContext context, {required String profileId, DVModifier? modifier}) {
  final tunnel = context.global<TunnelState>();
  final status = tunnel.statusOf(profileId);
  var text = switch (status) {
    .connected => tr(Strings.entitiesTunnelStatusActive),
    .connecting => tr(Strings.entitiesTunnelStatusActivating),
    .disconnecting => tr(Strings.entitiesTunnelStatusDeactivating),
    .disconnected => tr(Strings.entitiesTunnelStatusInactive),
  };
  if (tunnel.activeProfileId == profileId && tunnel.lastErrorCode != null) {
    text = tunnel.lastErrorCode!;
  } else if (status == .connected && (tunnel.received > 0 || tunnel.sent > 0)) {
    text = '↓${formatBytes(tunnel.received)} ↑${formatBytes(tunnel.sent)}';
    final since = tunnel.connectedSince;
    // Updated with every transfer count the engine reports.
    if (since != null) text = '$text · ${formatElapsed(DateTime.now().difference(since))}';
  }
  return DVText(text, (modifier ?? DVModifier()).color(PSColors.status(context, tunnel, profileId)));
}

/// How long a tunnel has been up: `0:42`, `12:03`, `1:02:03`.
String formatElapsed(Duration elapsed) {
  final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest' : '$minutes:$rest';
}

String formatBytes(int bytes) {
  const units = <String>['B', 'kB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  return unit == 0 ? '$bytes B' : '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// Runs [action], showing any error the way upstream's ErrorHandler does: an alert.
Future<void> runGuarded(BuildContext context, Future<void> Function() action, {String? title}) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) return;
    await showErrorAlert(context, title: title ?? tr(Strings.globalNounsError), message: describeError(error));
  }
}

/// The message an error alert shows.
String describeError(Object error) => switch (error) {
      UnsupportedError(:final message) => message ?? '$error',
      FormatException(:final message) => message,
      _ => '$error',
    };

Future<void> showErrorAlert(BuildContext context, {required String title, required String message}) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: DVText(title),
        content: DVText(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: DVText(tr(Strings.globalNounsOk))),
        ],
      ),
    );

/// Destructive confirmation (`themeConfirmation`). True when confirmed.
Future<bool> confirmDestructive(BuildContext context, {required String title, String? message, required String action}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: DVText(title),
        content: message == null ? null : DVText(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: DVText(tr(Strings.globalActionsCancel))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: PSColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: DVText(action),
          ),
        ],
      ),
    ) ??
    false;

/// Copies [text] and confirms with a snack bar.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: DVText(AppStrings.copied)));
  }
}

/// Empty-state message (`themeEmptyMessage`).
@DVFunctionalWidget()
Widget _pSEmptyMessage(BuildContext context, {required String text}) => DVBox(
      DVText(text, DVModifier().fontSize(24).color(PSColors.secondary(context))),
      DVModifier().padding(32).centered(),
    );

/// A screen: app bar with [title] and [actions], back button when it can pop.
@DVFunctionalWidget()
Widget _pSScaffold(
  BuildContext context, {
  required String title,
  required Widget body,
  List<Widget> actions = const <Widget>[],
  Widget? leading,
  bool largeTitle = false,
}) =>
    Scaffold(
      appBar: AppBar(
        leading: leading ?? PSBackTarget.fallbackButton(context),
        title: DVText(
          title,
          (largeTitle ? DVModifier().fontSize(24).fontWeight(.bold) : DVModifier()).semanticHeading(1),
        ),
        actions: <Widget>[...actions, const SizedBox(width: 8)],
      ),
      body: SafeArea(top: false, child: body),
    );

/// Where "back" goes on a page opened by URL with nothing under it (a deep
/// link or a reload): its parent page, e.g. a module's sub-page goes back to
/// the module. With a page to pop, back pops as usual.
class PSBackTarget extends InheritedWidget {
  const PSBackTarget({super.key, required this.target, required super.child});

  final DVRouteTarget target;

  /// A back button to the enclosing [PSBackTarget], or null when the page can
  /// pop or there is none.
  static Widget? fallbackButton(BuildContext context) {
    final backTarget = context.dependOnInheritedWidgetOfExactType<PSBackTarget>();
    if (backTarget == null || (Navigator.maybeOf(context)?.canPop() ?? false)) return null;
    return BackButton(onPressed: () => DV.Navigation.navigate(backTarget.target));
  }

  @override
  bool updateShouldNotify(PSBackTarget oldWidget) => oldWidget.target.path != target.path;
}

/// `ThemeLongContentLink`: a row showing [title] and a one-line preview of
/// [text] (or of [preview]'s result), opening the content's own page on tap.
@DVFunctionalWidget()
Widget _pSLongContentRow(
  BuildContext context, {
  required String title,
  required String text,
  required VoidCallback onTap,
  String? Function(String text)? preview,
  String? error,
}) {
  final shown = preview == null ? text : preview(text);
  return PSRow(
    title: title,
    subtitle: error,
    error: error != null,
    value: (shown == null || shown.isEmpty) ? null : middleTruncated(shown),
    monospaced: preview == null,
    navigates: true,
    onTap: onTap,
  );
}

/// An inline field error: red text, announced to screen readers as it changes.
@DVFunctionalWidget()
Widget _pSFieldError(BuildContext context, {required String text}) => Semantics(
      liveRegion: true,
      child: DVText(text, DVModifier().color(PSColors.error).fontSize(12)),
    );

/// Upstream truncates previews in the middle (`.truncationMode(.middle)`).
String middleTruncated(String text, {int maxLength = 24}) {
  if (text.length <= maxLength) return text;
  final half = (maxLength - 1) ~/ 2;
  return '${text.substring(0, half)}…${text.substring(text.length - half)}';
}

/// `LongContentEditor` / long read-only content: a full page of monospaced
/// text. Editable when [onChanged] is set (each keystroke reports it);
/// otherwise selectable (pages are), with a copy action.
@DVFunctionalWidget()
Widget _pSLongContentPage(
  BuildContext context, {
  required String title,
  required String text,
  ValueChanged<String>? onChanged,
  String? Function(String text)? validate,
}) {
  final DVSignal<String?> error = context.signal<String?>(validate?.call(text));
  if (onChanged == null) {
    return PSScaffold(
      title: title,
      actions: <Widget>[
        DVIconButton(
          icon: Icons.copy,
          label: AppStrings.copy,
          onPressed: () => copyToClipboard(context, text),
        ),
      ],
      body: PSForm(children: <Widget>[
        PSSection(children: <Widget>[
          DVText(text, DVModifier().fontFamily('monospace').lineHeight(1.4).padding(16)),
        ]),
      ]),
    );
  }
  final shown = error.value;
  return PSScaffold(
    title: title,
    body: DVBox.scrollableList(
      <Widget>[
        if (shown != null) PSFieldError(text: shown),
        DVText(
          text,
          DVModifier().input(
            label: title,
            multiline: true,
            onChanged: (value) {
              onChanged(value);
              if (validate != null) error.value = validate(value);
            },
          ),
        ),
      ],
      modifier: DVModifier().padding(16),
    ),
  );
}

// --- Lifecycle for functional widgets --------------------------------------
// A functional widget has no initState or dispose (Dartvel has no hook for
// them yet). These two cover what the app used them for. Call them on every
// build, unconditionally and in the same order, like any context.signal.

/// Runs [action] once for this widget, after its first build: what
/// `initState` did. Later builds do nothing.
void runOnce(BuildContext context, void Function() action) {
  final DVSignal<bool> started = context.signal<bool>(false);
  if (started.read()) return;
  // Not read with .value: setting it must not rebuild anything.
  started.value = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (context.mounted) action();
  });
}

/// Calls [tick] every [period] while this widget is on screen; the timer
/// stops itself once the widget is gone (what `dispose` did).
void everyWhileMounted(BuildContext context, Duration period, void Function() tick) => runOnce(
      context,
      () => Timer.periodic(period, (timer) {
        if (!context.mounted) {
          timer.cancel();
          return;
        }
        tick();
      }),
    );
