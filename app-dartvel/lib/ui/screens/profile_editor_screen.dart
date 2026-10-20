// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// "/profiles/<id>": edit a profile (upstream `ProfileCoordinator`,
// `ProfileEditView` iOS / `ProfileSplitView` macOS, `ProfileNameSection`,
// modules section with `EditorModuleToggle`, `AddModuleMenu`,
// `ProfileBehaviorSection`, `ProfileActionsSection`, `ProfileSaveButton`).
//
// Omitted, Apple-only: iCloud sharing, "Send to TV", Shortcuts, paywall.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../domain/profile.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../state/app_state.dart';
import '../../state/profile_draft.dart';
import '../../state/rule_groups_store.dart';
import '../kit.dart';
import '../modules/common/module_validation.dart';
import '../../platform/vpn_service.dart';

/// Upstream's message for a [ProfileProblem].
String profileProblemMessage(ProfileProblem problem) => switch (problem.kind) {
      .emptyName => tr(Strings.errorsAppEmptyProfileName),
      .noActiveModules => tr(Strings.errorsAppNoActiveModules),
      .incompatibleModules => tr(Strings.errorsAppIncompatibleModules),
      .incompleteModule => tr(Strings.errorsAppIncompleteModule, <Object>[problem.moduleType ?? '']),
    };

/// Leaves the editor: back to where it was opened from, or to the list.
void closeProfileEditor() {
  if (DV.Navigation.canGoBack) {
    DV.Navigation.back();
  } else {
    DV.Navigation.navigate(DVRoutes.index);
  }
}

@DVFunctionalWidget()
Widget _profileEditorScreen(BuildContext context, {required String profileId}) {
  final DVSignal<Set<String>> errorModuleIds = context.signal<Set<String>>(const <String>{});
  final DVSignal<bool> saving = context.signal<bool>(false);
  final profiles = context.global<ProfilesState>();
  final draft = context.global<ProfileDraft>();
  final errors = errorModuleIds.value;
  final isSaving = saving.value;

  Future<void> save(TunnelProfile profile) async {
    // Upstream builds every module first and shows the first invalid field.
    for (final module in profile.modules) {
      final error = moduleValidationError(module);
      if (error != null) {
        errorModuleIds.value = <String>{module.id};
        await showErrorAlert(context, title: module.typeLabel, message: error);
        return;
      }
    }
    final problem = profile.validate();
    if (problem != null) {
      errorModuleIds.value = problem.moduleIds;
      await showErrorAlert(context, title: profile.name, message: profileProblemMessage(problem));
      return;
    }
    saving.value = true;
    errorModuleIds.value = const <String>{};
    await runGuarded(context, () async {
      await DraftStore.commit();
      DraftStore.discard();
      closeProfileEditor();
    });
    if (context.mounted) saving.value = false;
  }

  void cancel() {
    DraftStore.discard();
    closeProfileEditor();
  }

  var profile = draft.profile?.id == profileId ? draft.profile : null;
  if (profile == null && profiles.isReady) profile = DraftStore.open(profileId);
  if (profile == null) {
    return PSScaffold(
      title: tr(Strings.globalNounsProfile),
      body: profiles.isReady
          ? PSEmptyMessage(text: tr(Strings.globalNounsNoContent))
          : const Center(child: CircularProgressIndicator.adaptive()),
    );
  }
  final current = profile;
  final isExisting = profiles.byId(current.id) != null;
  final isApple = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);
  return CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => save(current),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => save(current),
      const SingleActivator(LogicalKeyboardKey.escape): cancel,
    },
    child: PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) DraftStore.discard();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 96,
          leading: TextButton(onPressed: cancel, child: DVText(tr(Strings.globalActionsCancel))),
          title: DVText(tr(Strings.globalNounsProfile), const DVModifier().semanticHeading(1)),
          centerTitle: true,
          actions: <Widget>[
            if (isSaving)
              DVBox(
                const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const DVModifier().padding(14),
              )
            else
              TextButton(
                onPressed: () => save(current),
                child: DVText(tr(Strings.globalActionsSave), const DVModifier().fontWeight(.w600)),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: PSForm(children: <Widget>[
            PSSection(
              header: tr(Strings.globalNounsName),
              footer: isApple ? tr(Strings.viewsProfileSectionsNameFooter) : null,
              children: <Widget>[
                ProfileNameField(
                  name: current.name,
                  onSubmitted: () => save(DraftStore.state.profile ?? current),
                ),
              ],
            ),
            ProfileModulesSection(profile: current, errorModuleIds: errors),
            ProfileRuleGroupsSection(profile: current),
            PSSection(
              header: tr(Strings.modulesGeneralSectionsBehaviorHeader),
              children: <Widget>[
                PSToggleRow(
                  title: tr(Strings.modulesGeneralRowsKeepAliveOnSleep),
                  subtitle: tr(Strings.modulesGeneralRowsKeepAliveOnSleepFooter),
                  value: !current.disconnectsOnSleep,
                  onChanged: (on) => DraftStore.update((p) => p.withBehavior(disconnectsOnSleep: !on)),
                ),
                PSToggleRow(
                  title: tr(Strings.modulesGeneralRowsEnforceTunnel),
                  subtitle: tr(Strings.modulesGeneralRowsEnforceTunnelFooter),
                  value: current.includesAllNetworks,
                  onChanged: (on) => DraftStore.update((p) => p.withBehavior(includesAllNetworks: on)),
                ),
              ],
            ),
            PSSection(children: <Widget>[
              PSRow(
                title: 'ID',
                subtitle: current.id,
                monospaced: true,
                trailing: PSIconAction(
                  icon: Icons.copy,
                  size: 18,
                  label: AppStrings.copy,
                  onPressed: () => copyToClipboard(context, current.id),
                ),
              ),
            ]),
            if (isExisting)
              PSSection(children: <Widget>[
                PSRow(
                  title: tr(Strings.viewsProfileRowsDeleteProfile),
                  destructive: true,
                  onTap: () async {
                    final confirmed = await confirmDestructive(
                      context,
                      title: tr(Strings.globalActionsDelete),
                      message: current.name,
                      action: tr(Strings.globalActionsDelete),
                    );
                    if (!confirmed) return;
                    DraftStore.discard();
                    closeProfileEditor();
                    await ProfileStore.remove(current.id);
                  },
                ),
              ]),
          ]),
        ),
      ),
    ),
  );
}

/// The rule groups attached to this profile: a switch per group, then a link
/// to manage them (TunnlTo's reusable rules, decoupled from the tunnel).
@DVFunctionalWidget()
Widget _profileRuleGroupsSection(BuildContext context, {required TunnelProfile profile}) {
  final groups = context.global<RuleGroupsState>().sorted;
  final attached = profile.ruleGroupIds.toSet();
  return PSSection(
    header: AppStrings.ruleGroups,
    footer: AppStrings.profileRuleGroupsFooter,
    children: <Widget>[
      for (final group in groups)
        PSToggleRow(
          key: ValueKey<String>('profile/rule-group/${group.id}'),
          title: group.name,
          subtitle: group.summary,
          value: attached.contains(group.id),
          onChanged: (_) => DraftStore.update((p) => p.togglingRuleGroup(group.id)),
        ),
      PSRow(
        title: AppStrings.manageRuleGroups,
        navigates: true,
        onTap: () => DV.Navigation.push(DVRoutes.settingsrulegroups),
      ),
    ],
  );
}

@DVFunctionalWidget()
Widget _profileNameField(BuildContext context, {required String name, required VoidCallback onSubmitted}) => PSTextRow(
      label: tr(Strings.globalNounsName),
      value: name,
      placeholder: tr(Strings.placeholdersProfileName),
      onChanged: (text) => DraftStore.update((p) => p.renamed(text)),
      onSubmitted: (_) => onSubmitted(),
    );

/// The red "delete" strip behind a module swiped to the left.
@DVFunctionalWidget()
Widget _moduleSwipeBackground(BuildContext context) => DVBox(
      const Icon(Icons.delete, color: Colors.white),
      const DVModifier().backgroundColor(PSColors.error).align(Alignment.centerRight).paddingOnly(right: 20),
    );

/// Modules: a switch per module (tap the name to edit it), drag to reorder,
/// swipe to delete, then "Add module".
@DVFunctionalWidget()
Widget _profileModulesSection(BuildContext context, {required TunnelProfile profile, required Set<String> errorModuleIds}) {
  final modules = profile.modules;
  final theme = Theme.of(context);
  final present = modules.map((m) => m.type).toSet();
  final available = ModuleType.addable.where((t) => !present.contains(t)).toList();
  return PSSection(
    header: tr(Strings.globalNounsModules),
    footer: tr(Strings.viewsProfileModuleListSectionFooter),
    children: <Widget>[
      if (modules.isNotEmpty)
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) => DraftStore.update((p) => p.movingModule(from, to > from ? to + 1 : to)),
          children: <Widget>[
            for (var i = 0; i < modules.length; i++)
              Dismissible(
                key: ValueKey<String>(modules[i].id),
                direction: DismissDirection.endToStart,
                background: const ModuleSwipeBackground(),
                onDismissed: (_) => DraftStore.update((p) => p.removingModule(modules[i].id)),
                child: Material(
                  color: theme.colorScheme.surface,
                  child: DVBox.list(
                    <Widget>[
                      if (i > 0) DVBox(const Divider(), const DVModifier().paddingOnly(left: 16)),
                      ProfileModuleRow(
                        index: i,
                        profile: profile,
                        module: modules[i],
                        hasError: errorModuleIds.contains(modules[i].id),
                      ),
                    ],
                    spacing: 0,
                  ),
                ),
              ),
          ],
        ),
      AddModuleMenu(types: available, profileId: profile.id),
    ],
  );
}

@DVFunctionalWidget()
Widget _profileModuleRow(
  BuildContext context, {
  required int index,
  required TunnelProfile profile,
  required TaggedModule module,
  required bool hasError,
}) =>
    Tooltip(
      message: module.typeLabel,
      excludeFromSemantics: true,
      child: ListTile(
        contentPadding: const .only(left: 4, right: 8),
        leading: ReorderableDragStartListener(
          index: index,
          child: DVBox(
            const Icon(Icons.drag_indicator, size: 20, semanticLabel: 'Reorder'),
            const DVModifier().padding(8).tooltip('Drag to reorder'),
          ),
        ),
        title: DVBox.row(
          <Widget>[
            Flexible(child: DVText(module.typeLabel)),
            if (hasError)
              DVBox(
                const Icon(Icons.warning_amber, color: PSColors.pending, size: 18),
                const DVModifier().paddingOnly(left: 6),
              ),
            const Icon(Icons.chevron_right, size: 20),
          ],
          spacing: 0,
          crossAlign: .center,
        ),
        onTap: () => DV.Navigation.push(DVRoutes.profilesmodules(id: profile.id, moduleId: module.id)),
        trailing: Switch.adaptive(
          value: profile.isActive(module.id),
          onChanged: (_) => DraftStore.update((p) => p.togglingModule(module.id)),
        ),
      ),
    );

/// `AddModuleMenu`: "Connection" types, then "Settings" types; disabled when none left.
@DVFunctionalWidget()
Widget _addModuleMenu(BuildContext context, {required List<String> types, required String profileId}) {
  final connection = types.where(ModuleType.isConnection).toList()..sort();
  final other = types.where((t) => !ModuleType.isConnection(t)).toList()..sort();
  Widget entry(String type) => MenuItemButton(
        onPressed: () => runGuarded(context, () async {
          var module = TaggedModule.empty(type);
          // Upstream starts a WireGuard module with a fresh private key and no peers.
          if (type == ModuleType.wireGuard) {
            module = module.withField('configuration', <String, dynamic>{
              'interface': <String, dynamic>{
                'privateKey': await VpnService.instance.generateWireGuardKey(),
                'addresses': <dynamic>[],
              },
              'peers': <dynamic>[],
            });
          }
          DraftStore.update((p) => p.savingModule(module, activate: true));
          await DV.Navigation.push(DVRoutes.profilesmodules(id: profileId, moduleId: module.id));
        }),
        child: DVText(TaggedModule.of(type, const <String, dynamic>{'id': ''}).typeLabel),
      );
  // labelSmall.
  Widget header(String text) => DVText(
        text,
        const DVModifier().fontSize(11).fontWeight(.w500).paddingOnly(left: 12, top: 8, right: 12, bottom: 4),
      );
  return MenuAnchor(
    menuChildren: <Widget>[
      if (connection.isNotEmpty) ...<Widget>[header(tr(Strings.globalNounsConnection)), ...connection.map(entry)],
      if (connection.isNotEmpty && other.isNotEmpty) const Divider(height: 1),
      if (other.isNotEmpty) ...<Widget>[header(tr(Strings.globalNounsSettings)), ...other.map(entry)],
    ],
    builder: (context, controller, _) => PSRow(
      title: tr(Strings.viewsProfileRowsAddModule),
      onTap: types.isEmpty ? null : () => controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}
