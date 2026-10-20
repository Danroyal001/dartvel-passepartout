// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Upstream `theme.listSection` / `EditableListSection`: one row per item,
// swipe or minus to remove, an "Add" row that stays disabled while the last
// item is still empty. Items carry stable ids, so removing a row never moves
// another row's text into the wrong field.

import 'package:flutter/material.dart';

import '../../../l10n/strings.g.dart';
import '../../../dartvel_client/dartvel_client.dart';
import '../../kit.dart';
import 'module_builder_cache.dart';

/// The list section itself, by index: row [i] is drawn by [rowBuilder] and
/// keyed by `rowIds[i]` (a stable [ListItem.id]); [onAdd] is null while
/// adding is disabled. [editableListSection] is the typed front over
/// [ListItem]s.
@DVFunctionalWidget()
Widget _editableListSection(
  BuildContext context, {
  String? header,
  String? footer,
  required String addTitle,
  required List<int> rowIds,
  required Widget Function(BuildContext context, int index) rowBuilder,
  required ValueChanged<int> onRemove,
  required VoidCallback? onAdd,
}) {
  final delete = tr(Strings.globalActionsDelete);
  return PSSection(
    header: header,
    footer: footer,
    children: <Widget>[
      for (var i = 0; i < rowIds.length; i++)
        Dismissible(
          key: ValueKey<String>('${header ?? ''}/item/${rowIds[i]}'),
          direction: .endToStart,
          background: DVBox(
            DVText(delete, const DVModifier().color(Colors.white)),
            const DVModifier().backgroundColor(PSColors.error).paddingOnly(right: 16).align(Alignment.centerRight),
          ),
          onDismissed: (_) => onRemove(i),
          child: DVBox.row(
            <Widget>[
              PSIconAction(icon: Icons.remove_circle, color: PSColors.error, label: delete, onPressed: () => onRemove(i)),
              Expanded(child: rowBuilder(context, i)),
            ],
            spacing: 0,
            crossAlign: .center,
            modifier: const DVModifier().paddingOnly(right: 16),
          ),
        ),
      PSRow(
        title: addTitle,
        leading: Icon(Icons.add_circle, color: onAdd != null ? PSColors.active : Theme.of(context).disabledColor),
        onTap: onAdd,
      ),
    ],
  );
}

/// [EditableListSection] over [items]: reports the whole new list on every
/// add, removal and edit. [itemBuilder] draws one row; calling its setter
/// replaces that row's value.
Widget editableListSection<T>({
  Key? key,
  String? header,
  String? footer,
  required String addTitle,
  required List<ListItem<T>> items,
  required ValueChanged<List<ListItem<T>>> onChanged,
  required T Function() emptyValue,
  required bool Function(T value) isEmptyValue,
  required Widget Function(BuildContext context, ListItem<T> item, ValueChanged<T> setValue) itemBuilder,
}) {
  final canAdd = items.isEmpty || !isEmptyValue(items.last.value);
  return EditableListSection(
    key: key,
    header: header,
    footer: footer,
    addTitle: addTitle,
    rowIds: <int>[for (final item in items) item.id],
    rowBuilder: (context, index) {
      final item = items[index];
      return itemBuilder(
        context,
        item,
        (value) => onChanged(<ListItem<T>>[for (final other in items) other.id == item.id ? other.copyWith(value) : other]),
      );
    },
    onRemove: (index) {
      final id = items[index].id;
      onChanged(<ListItem<T>>[...items]..removeWhere((other) => other.id == id));
    },
    onAdd: canAdd ? () => onChanged(<ListItem<T>>[...items, ListItem<T>(emptyValue())]) : null,
  );
}

/// A borderless text field for one list row, following [value]
/// (`ThemeTextField("", text:, placeholder:)` with hidden label: the label
/// names the field to screen readers only).
@DVFunctionalWidget()
Widget _listItemTextField(
  BuildContext context, {
  required String value,
  required ValueChanged<String> onChanged,
  String? placeholder,
  String? semanticLabel,
}) {
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none)),
    child: Semantics(
      label: semanticLabel,
      child: DVText(value, const DVModifier().input(hint: placeholder, onChanged: onChanged)),
    ),
  );
}
