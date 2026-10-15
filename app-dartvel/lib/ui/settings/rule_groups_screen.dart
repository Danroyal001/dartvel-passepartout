// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// "/settings/rule-groups": the reusable split-tunnel rule groups, and
// "/settings/rule-group/<id>": one group's editor. An idea from TunnlTo
// (rules decoupled from tunnels); our own screens.

import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../state/rule_groups_store.dart';
import '../kit.dart';
import '../modules/common/editable_list_section.dart';
import '../modules/common/module_builder_cache.dart';
import 'settings_support.dart';

/// Creates a group with the default name and opens its editor.
Future<void> createRuleGroup(BuildContext context) => runGuarded(context, () async {
      final group = await RuleGroupStore.create(AppStrings.newRuleGroup);
      pushRoute(DVRoutes.settingsrulegroup(id: group.id));
    });

@DVFunctionalWidget()
Widget _ruleGroupsScreen(BuildContext context) {
  final state = context.global<RuleGroupsState>();
  final groups = state.sorted;
  return PSScaffold(
    title: AppStrings.ruleGroups,
    actions: <Widget>[
      DVIconButton(icon: Icons.add, label: AppStrings.addRuleGroup, onPressed: () => createRuleGroup(context)),
    ],
    body: PSForm(children: <Widget>[
      PSSection(
        footer: AppStrings.ruleGroupsFooter,
        children: <Widget>[
          if (groups.isEmpty) const PSRow(title: AppStrings.noRuleGroups),
          for (final group in groups)
            PSRow(
              key: ValueKey<String>('rule-groups/${group.id}'),
              title: group.name,
              subtitle: group.summary,
              navigates: true,
              onTap: () => pushRoute(DVRoutes.settingsrulegroup(id: group.id)),
            ),
          PSRow(title: AppStrings.addRuleGroup, onTap: () => createRuleGroup(context)),
        ],
      ),
    ]),
  );
}

/// Saves [group] with these rows as its rules, empty rows left out.
void saveRuleGroupRules(RuleGroup group, List<ListItem<String>> included, List<ListItem<String>> excluded) {
  List<String> rules(List<ListItem<String>> rows) =>
      rows.map((row) => row.value.trim()).where((rule) => rule.isNotEmpty).toList();
  RuleGroupStore.save(group.copyWith(included: rules(included), excluded: rules(excluded)));
}

/// Deletes [group] after confirming, leaving its page first.
Future<void> deleteRuleGroup(BuildContext context, RuleGroup group) async {
  final confirmed = await confirmDestructive(
    context,
    title: AppStrings.deleteRuleGroup,
    message: group.name,
    action: tr(Strings.globalActionsDelete),
  );
  if (!confirmed) return;
  if (DV.Navigation.canGoBack) {
    DV.Navigation.back();
  } else {
    DV.Navigation.navigate(DVRoutes.settingsrulegroups);
  }
  await RuleGroupStore.remove(group.id);
}

@DVFunctionalWidget()
Widget _ruleGroupEditorScreen(BuildContext context, {required String groupId}) {
  // The rows being edited, with their ids; null until the first edit, the
  // stored rules standing in for them until then.
  final DVSignal<List<ListItem<String>>?> includedRows = context.signal<List<ListItem<String>>?>(null);
  final DVSignal<List<ListItem<String>>?> excludedRows = context.signal<List<ListItem<String>>?>(null);
  final state = context.global<RuleGroupsState>();
  final group = state.byId(groupId);
  if (group == null) {
    return PSScaffold(
      title: AppStrings.ruleGroup,
      body: PSEmptyMessage(text: state.isReady ? AppStrings.noRuleGroups : tr(Strings.globalNounsLoading)),
    );
  }
  final included = includedRows.value ?? stringItems(group.included);
  final excluded = excludedRows.value ?? stringItems(group.excluded);

  Widget rulesSection(String key, String header, String footer, List<ListItem<String>> rows, DVSignal<List<ListItem<String>>?> into) =>
      EditableListSection<String>(
        key: ValueKey<String>('rule-group/$key'),
        header: header,
        footer: footer,
        addTitle: tr(Strings.globalActionsAdd),
        items: rows,
        emptyValue: () => '',
        isEmptyValue: (value) => value.trim().isEmpty,
        onChanged: (next) {
          into.value = next;
          saveRuleGroupRules(group, includedRows.read() ?? included, excludedRows.read() ?? excluded);
        },
        itemBuilder: (context, item, setValue) {
          final rule = item.value.trim();
          final invalid = rule.isNotEmpty && RuleTarget.parse(rule) == null;
          // No URL keyboard: ListItemTextField's keyboardType has no DV
          // input equivalent, so the ported field will not take it.
          return DVBox.list(
            <Widget>[
              ListItemTextField(
                key: ValueKey<String>('rule-group/$key/${item.id}'),
                value: item.value,
                placeholder: AppStrings.rulePlaceholder,
                semanticLabel: header,
                onChanged: setValue,
              ),
              if (invalid) PSFieldError(text: AppStrings.invalidRule(rule)),
            ],
            spacing: 0,
          );
        },
      );

  return PSScaffold(
    title: group.name,
    body: PSForm(children: <Widget>[
      PSSection(children: <Widget>[
        PSTextRow(
          label: tr(Strings.globalNounsName),
          value: group.name,
          placeholder: AppStrings.newRuleGroup,
          onChanged: (name) {
            if (name.trim().isNotEmpty) RuleGroupStore.save(group.copyWith(name: name.trim()));
          },
        ),
      ]),
      rulesSection('included', AppStrings.includedRules, AppStrings.includedRulesFooter, included, includedRows),
      rulesSection('excluded', AppStrings.excludedRules, AppStrings.excludedRulesFooter, excluded, excludedRows),
      PSSection(children: <Widget>[
        PSRow(
          title: AppStrings.deleteRuleGroup,
          destructive: true,
          onTap: () => deleteRuleGroup(context, group),
        ),
      ]),
    ]),
  );
}
