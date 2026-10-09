// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// The shared look: upstream's `themeForm()` grouped lists, rows, toggles and
// status colours. Every screen builds from these so the app reads as one, and
// so a screen ported by anyone matches the Apple layout row for row.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
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
class const PSForm({super.key, required final List<Widget> children, final double maxWidth = 720}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListView(
        padding: const .symmetric(vertical: 8),
        children: <Widget>[
          for (final child in children)
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
        ],
      );
}

/// An inset grouped section: optional header, rows on a rounded card, optional footer.
class const PSSection({
  super.key,
  final String? header,
  final String? footer,
  required final List<Widget> children,
  final Widget? headerTrailing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Padding(padding: .only(left: 16), child: Divider()));
      rows.add(children[i]);
    }
    return Padding(
      padding: const .fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (header != null || headerTrailing != null)
            Padding(
              padding: const .fromLTRB(16, 8, 8, 6),
              child: Row(children: <Widget>[
                if (header != null)
                  Expanded(
                    child: Semantics(
                      headingLevel: 2,
                      child: Text(header!.toUpperCase(), style: secondary?.copyWith(letterSpacing: 0.3)),
                    ),
                  ),
                ?headerTrailing,
              ]),
            ),
          if (rows.isNotEmpty)
            Material(
              color: theme.colorScheme.surface,
              borderRadius: .circular(10),
              clipBehavior: .antiAlias,
              child: Column(crossAxisAlignment: .stretch, children: rows),
            ),
          if (footer != null)
            Padding(padding: const .fromLTRB(16, 6, 16, 0), child: Text(footer!, style: secondary)),
        ],
      ),
    );
  }
}

/// A row: title, optional subtitle/value, optional chevron when it navigates.
class const PSRow({
  super.key,
  required final String title,
  final String? subtitle,
  final String? value,
  final Widget? leading,
  final Widget? trailing,
  final VoidCallback? onTap,
  final bool navigates = false,
  final bool destructive = false,
  final bool monospaced = false,
  final bool selectable = false,
  final bool error = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor = destructive ? PSColors.error : (onTap != null && !navigates && trailing == null && value == null)
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFamily: monospaced ? 'monospace' : null,
    );
    return ListTile(
      leading: leading,
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: subtitle == null
          ? null
          : error
              ? PSFieldError(text: subtitle!)
              : (selectable ? SelectableText(subtitle!, style: valueStyle) : Text(subtitle!, style: valueStyle)),
      trailing: Row(mainAxisSize: .min, children: <Widget>[
        if (value != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(value!, style: valueStyle, overflow: .ellipsis, textAlign: .end),
          ),
        ?trailing,
        if (navigates) Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
      ]),
      onTap: onTap,
    );
  }
}

/// A toggle row. The whole row toggles, as on iOS.
class const PSToggleRow({
  super.key,
  required final String title,
  final String? subtitle,
  required final bool value,
  required final ValueChanged<bool>? onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        value: value,
        onChanged: onChanged,
      );
}

/// A labelled text field row (`ThemeTextField`): label left, field right.
class PSTextRow extends StatefulWidget {
  const PSTextRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.keyboardType,
    this.monospaced = false,
    this.obscure = false,
    this.onSubmitted,
    this.autofocus = false,
    this.error,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final TextInputType? keyboardType;
  final bool monospaced;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Shown under the field in red while the text is invalid.
  final String? error;

  @override
  State<PSTextRow> createState() => _PSTextRowState();
}

class _PSTextRowState extends State<PSTextRow> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(PSTextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const .symmetric(horizontal: 16, vertical: 4),
      child: Row(children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96),
          child: Text(widget.label, style: theme.textTheme.bodyLarge),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _controller,
            autofocus: widget.autofocus,
            textAlign: .end,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            style: TextStyle(fontFamily: widget.monospaced ? 'monospace' : null),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: widget.placeholder,
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
              semanticCounterText: widget.label,
            ),
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
          ),
        ),
      ]),
    );
    final error = widget.error;
    if (error == null) return row;
    return Column(crossAxisAlignment: .stretch, children: <Widget>[
      row,
      Padding(padding: const .fromLTRB(16, 0, 16, 8), child: PSFieldError(text: error)),
    ]);
  }
}

/// A picker row (`Picker` in a Form): title left, current choice right, menu on tap.
class const PSPickerRow<T>({
  super.key,
  required final String title,
  required final T value,
  required final List<T> options,
  required final String Function(T) label,
  required final ValueChanged<T>? onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      menuChildren: <Widget>[
        for (final option in options)
          MenuItemButton(
            leadingIcon: Icon(option == value ? Icons.check : null, size: 18),
            onPressed: onChanged == null ? null : () => onChanged!(option),
            child: Text(label(option)),
          ),
      ],
      builder: (context, controller, _) => ListTile(
        title: Text(title),
        trailing: Row(mainAxisSize: .min, children: <Widget>[
          Text(label(value), style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          Icon(Icons.unfold_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ]),
        onTap: onChanged == null ? null : () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The connect switch (`TunnelToggle`).
class const TunnelToggle({super.key, required final String profileId, final String? semanticLabel}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tunnel = context.global<TunnelState>();
    final profile = context.global<ProfilesState>().byId(profileId);
    final on = tunnel.statusOf(profileId) == .connected || tunnel.statusOf(profileId) == .connecting;
    return Semantics(
      label: semanticLabel ?? profile?.name,
      child: Switch.adaptive(
        value: on,
        onChanged: profile == null ? null : (_) => runGuarded(context, () => TunnelStore.toggle(profile)),
      ),
    );
  }
}

/// "Active", "Activating"... with the on-demand suffix, coloured by status
/// (`ConnectionStatusText`).
class const ConnectionStatusText({super.key, required final String profileId, final TextStyle? style}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
    return Text(text, style: (style ?? const TextStyle()).copyWith(color: PSColors.status(context, tunnel, profileId)));
  }
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
    await showErrorAlert(context, title: title ?? tr(Strings.globalNounsError), message: _describe(error));
  }
}

String _describe(Object error) => switch (error) {
      UnsupportedError(:final message) => message ?? '$error',
      FormatException(:final message) => message,
      _ => '$error',
    };

Future<void> showErrorAlert(BuildContext context, {required String title, required String message}) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(Strings.globalNounsOk))),
        ],
      ),
    );

/// Destructive confirmation (`themeConfirmation`). True when confirmed.
Future<bool> confirmDestructive(BuildContext context, {required String title, String? message, required String action}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr(Strings.globalActionsCancel))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: PSColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Copies [text] and confirms with a snack bar.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }
}

/// Empty-state message (`themeEmptyMessage`).
class const PSEmptyMessage({super.key, required final String text}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const .all(32),
          child: Text(
            text,
            textAlign: .center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

/// A screen: app bar with [title] and [actions], back button when it can pop.
class const PSScaffold({
  super.key,
  required final String title,
  required final Widget body,
  final List<Widget> actions = const <Widget>[],
  final Widget? leading,
  final bool largeTitle = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: leading ?? PSBackTarget.fallbackButton(context),
          title: Semantics(headingLevel: 1, child: Text(title, style: largeTitle ? Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: .bold) : null)),
          actions: <Widget>[...actions, const SizedBox(width: 8)],
        ),
        body: SafeArea(top: false, child: body),
      );
}

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
class const PSLongContentRow({
  super.key,
  required final String title,
  required final String text,
  required final VoidCallback onTap,
  final String? Function(String text)? preview,
  final String? error,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shown = preview == null ? text : preview!(text);
    return PSRow(
      title: title,
      subtitle: error,
      error: error != null,
      value: (shown == null || shown.isEmpty) ? null : _middleTruncated(shown),
      monospaced: preview == null,
      navigates: true,
      onTap: onTap,
    );
  }
}

/// An inline field error: red text, announced to screen readers as it changes.
class const PSFieldError({super.key, required final String text}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: PSColors.error)),
      );
}

/// Upstream truncates previews in the middle (`.truncationMode(.middle)`).
String _middleTruncated(String text, {int maxLength = 24}) {
  if (text.length <= maxLength) return text;
  final half = (maxLength - 1) ~/ 2;
  return '${text.substring(0, half)}…${text.substring(text.length - half)}';
}

/// `LongContentEditor` / long read-only content: a full page of monospaced
/// text. Editable when [onChanged] is set (each keystroke reports it);
/// otherwise selectable, with a copy action.
class PSLongContentPage extends StatefulWidget {
  const PSLongContentPage({
    super.key,
    required this.title,
    required this.text,
    this.onChanged,
    this.keyboardType,
    this.validate,
  });

  final String title;
  final String text;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  /// The error to show under the editor for the current text, or null.
  final String? Function(String text)? validate;

  @override
  State<PSLongContentPage> createState() => _PSLongContentPageState();
}

class _PSLongContentPageState extends State<PSLongContentPage> {
  late final TextEditingController _controller = TextEditingController(text: widget.text);
  late String? _error = widget.validate?.call(widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    widget.onChanged!(text);
    final validate = widget.validate;
    if (validate != null) setState(() => _error = validate(text));
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChanged;
    if (onChanged == null) {
      return PSScaffold(
        title: widget.title,
        actions: <Widget>[
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () => copyToClipboard(context, widget.text),
          ),
        ],
        body: PSForm(children: <Widget>[
          PSSection(children: <Widget>[
            Padding(
              padding: const .all(16),
              child: SelectableText(
                widget.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.4),
              ),
            ),
          ]),
        ]),
      );
    }
    final error = _error;
    return PSScaffold(
      title: widget.title,
      body: Padding(
        padding: const .all(16),
        child: Column(crossAxisAlignment: .stretch, children: <Widget>[
          if (error != null) Padding(padding: const .only(bottom: 8), child: PSFieldError(text: error)),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              expands: true,
              maxLines: null,
              keyboardType: widget.keyboardType ?? TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              textAlignVertical: .top,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(border: InputBorder.none, semanticCounterText: widget.title),
              onChanged: _changed,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Placeholder body for a screen whose port is in progress. Says so plainly.
class const PSNotPortedYet({super.key, required final String title}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PSScaffold(
        title: title,
        body: const PSEmptyMessage(text: 'Not ported yet'),
      );
}
