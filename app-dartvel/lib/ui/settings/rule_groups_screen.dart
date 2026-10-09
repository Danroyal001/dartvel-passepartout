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

class const RuleGroupsScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.global<RuleGroupsState>();
    final groups = state.sorted;
    return PSScaffold(
      title: AppStrings.ruleGroups,
      actions: <Widget>[
        IconButton(
          tooltip: AppStrings.addRuleGroup,
          icon: const Icon(Icons.add),
          onPressed: () => _create(context),
        ),
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
            PSRow(title: AppStrings.addRuleGroup, onTap: () => _create(context)),
          ],
        ),
      ]),
    );
  }

  Future<void> _create(BuildContext context) => runGuarded(context, () async {
        final group = await RuleGroupStore.create(AppStrings.newRuleGroup);
        pushRoute(DVRoutes.settingsrulegroup(id: group.id));
      });
}

class RuleGroupEditorScreen extends StatefulWidget {
  const RuleGroupEditorScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<RuleGroupEditorScreen> createState() => _RuleGroupEditorScreenState();
}

class _RuleGroupEditorScreenState extends State<RuleGroupEditorScreen> {
  List<ListItem<String>>? _included;
  List<ListItem<String>>? _excluded;

  /// Saves [group] with the rows as they are, empty rows left out.
  void _save(RuleGroup group) {
    List<String> rules(List<ListItem<String>> rows) =>
        rows.map((row) => row.value.trim()).where((rule) => rule.isNotEmpty).toList();
    RuleGroupStore.save(group.copyWith(included: rules(_included!), excluded: rules(_excluded!)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.global<RuleGroupsState>();
    final group = state.byId(widget.groupId);
    if (group == null) {
      return PSScaffold(
        title: AppStrings.ruleGroup,
        body: PSEmptyMessage(text: state.isReady ? AppStrings.noRuleGroups : tr(Strings.globalNounsLoading)),
      );
    }
    final included = _included ??= stringItems(group.included);
    final excluded = _excluded ??= stringItems(group.excluded);

    Widget rulesSection(String key, String header, String footer, List<ListItem<String>> rows, void Function(List<ListItem<String>>) assign) =>
        EditableListSection<String>(
          key: ValueKey<String>('rule-group/$key'),
          header: header,
          footer: footer,
          addTitle: tr(Strings.globalActionsAdd),
          items: rows,
          emptyValue: () => '',
          isEmptyValue: (value) => value.trim().isEmpty,
          onChanged: (next) {
            setState(() => assign(next));
            _save(group);
          },
          itemBuilder: (context, item, setValue) {
            final rule = item.value.trim();
            final invalid = rule.isNotEmpty && RuleTarget.parse(rule) == null;
            return Column(crossAxisAlignment: .stretch, mainAxisSize: .min, children: <Widget>[
              ListItemTextField(
                key: ValueKey<String>('rule-group/$key/${item.id}'),
                value: item.value,
                placeholder: AppStrings.rulePlaceholder,
                keyboardType: TextInputType.url,
                semanticLabel: header,
                onChanged: setValue,
              ),
              if (invalid) PSFieldError(text: AppStrings.invalidRule(rule)),
            ]);
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
        rulesSection('included', AppStrings.includedRules, AppStrings.includedRulesFooter, included, (next) => _included = next),
        rulesSection('excluded', AppStrings.excludedRules, AppStrings.excludedRulesFooter, excluded, (next) => _excluded = next),
        PSSection(children: <Widget>[
          PSRow(
            title: AppStrings.deleteRuleGroup,
            destructive: true,
            onTap: () async {
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
            },
          ),
        ]),
      ]),
    );
  }
}
