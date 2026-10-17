// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// "/": the profile list (upstream `AppCoordinator` + `ProfileContainerView`,
// `ProfileListView`, `ProfileGridView`, `InstalledProfileView`,
// `ProfileRowView`, `ProfileCardView`, `ProfileContextMenu`, `AppToolbar`,
// `AddProfileMenu`, `ProfilesLayoutPicker`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../domain/profile.dart';
import '../../l10n/app_strings.dart';
import '../../l10n/strings.g.dart';
import '../../state/app_state.dart';
import '../../state/profile_draft.dart';
import '../kit.dart';
import 'profile_transfer.dart';
import 'text_focus.dart';

/// `isBigDevice`: iPad/Mac layout (toolbar group, grid available).
bool isBigLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= 700;

/// Enter in the search field connects the first match, so a long list
/// works as a quick switcher: Ctrl+K (Cmd+K), type, Enter.
void connectFirstMatch(BuildContext context) {
  final matches = ProfileStore.state.filtered;
  if (matches.isEmpty) return;
  final profile = matches.first;
  if (TunnelStore.state.isActive(profile.id)) return;
  runGuarded(context, () => TunnelStore.connect(profile), title: profile.name);
}

@DVFunctionalWidget()
Widget _profilesScreen(BuildContext context) {
  final profiles = context.global<ProfilesState>();
  final preferences = context.global<Preferences>();
  final big = isBigLayout(context);
  final layout = big ? preferences.layout : ProfilesLayout.list;
  final searching = profiles.search.trim().isNotEmpty;

  final Widget body;
  if (!profiles.isReady) {
    body = Center(child: CircularProgressIndicator.adaptive(semanticsLabel: tr(Strings.globalNounsLoading)));
  } else if (!profiles.hasProfiles) {
    body = PSEmptyMessage(text: tr(Strings.viewsAppFoldersNoProfiles));
  } else {
    final header = preferences.pinsActiveProfile && !searching ? const InstalledProfileHeader() : null;
    body = layout == .grid
        ? ProfileGrid(header: header, profiles: profiles.filtered)
        : ProfileList(header: header, profiles: profiles.filtered);
  }

  Widget settingsButton() => DVIconButton(
        icon: Icons.settings_outlined,
        label: tr(Strings.globalNounsSettings),
        onPressed: () => DV.Navigation.push(DVRoutes.settings),
      );

  void focusSearch() => focusFirstTextField(context);

  return CallbackShortcuts(
    bindings: <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): focusSearch,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): focusSearch,
    },
    child: Scaffold(
      appBar: AppBar(
        leading: big ? null : settingsButton(),
        title: DVText('Dartvel VPN', const DVModifier().semanticHeading(1)),
        actions: <Widget>[
          if (profiles.hasProfiles) ProfileSearchField(onSubmitted: () => connectFirstMatch(context)),
          const AddProfileMenu(),
          if (big) ...<Widget>[
            settingsButton(),
            ProfilesLayoutPicker(layout: preferences.layout),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(top: false, child: body),
    ),
  );
}

@DVFunctionalWidget()
Widget _profilesLayoutPicker(BuildContext context, {required ProfilesLayout layout}) => SegmentedButton<ProfilesLayout>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const <ButtonSegment<ProfilesLayout>>[
        ButtonSegment<ProfilesLayout>(
          value: .list,
          tooltip: 'List',
          icon: Icon(Icons.view_list_outlined, semanticLabel: 'List'),
        ),
        ButtonSegment<ProfilesLayout>(
          value: .grid,
          tooltip: 'Grid',
          icon: Icon(Icons.grid_view_outlined, semanticLabel: 'Grid'),
        ),
      ],
      selected: <ProfilesLayout>{layout},
      onSelectionChanged: (selection) => PreferencesStore.update((p) => p.copyWith(layout: selection.first)),
    );

/// `.searchable(text:)`: filters profiles by name, module type and server.
/// The query lives in [ProfilesState.search], so the field follows it.
@DVFunctionalWidget()
Widget _profileSearchField(BuildContext context, {required VoidCallback onSubmitted}) {
  final theme = Theme.of(context);
  final big = isBigLayout(context);
  const InputBorder none = InputBorder.none;
  // Upstream's search bar: a filled, borderless pill with a magnifier.
  final field = Theme(
    data: theme.copyWith(
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        border: none,
        enabledBorder: none,
        focusedBorder: none,
        contentPadding: .symmetric(vertical: 8),
      ),
    ),
    child: DVText(
      context.global<ProfilesState>().search,
      const DVModifier().input(
        hint: big ? AppStrings.searchHint : AppStrings.search,
        onChanged: ProfileStore.search,
        onSubmitted: onSubmitted,
      ),
    ),
  );
  return DVBox(
    DVBox.row(
      <Widget>[
        Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
        Expanded(child: field),
      ],
      spacing: 6,
      crossAlign: .center,
    ),
    const DVModifier()
        .backgroundColor(theme.colorScheme.surfaceContainerHighest)
        .rounded(10)
        .paddingSymmetric(horizontal: 10)
        .marginOnly(top: 8, bottom: 8)
        .maxWidth(big ? 220 : 140),
  );
}

// ---------------------------------------------------------------------------
// Add profile

@DVFunctionalWidget()
Widget _addProfileMenu(BuildContext context) => MenuAnchor(
      menuChildren: <Widget>[
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined),
          onPressed: () => newEmptyProfile(context),
          child: DVText(tr(Strings.viewsAppToolbarNewProfileEmpty)),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.file_open_outlined),
          onPressed: () => importProfileFile(context),
          child: DVText('${tr(Strings.viewsAppToolbarImportFile)}...'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.qr_code_scanner),
          onPressed: () => importQrCode(context),
          child: DVText('${tr(Strings.viewsAppToolbarImportQrTitle)}...'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.text_snippet_outlined),
          onPressed: () => DV.Navigation.push(DVRoutes.importtext),
          child: DVText('${tr(Strings.viewsAppToolbarImportTextTitle)}...'),
        ),
        if (ProfileStore.state.hasProfiles) ...<Widget>[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.archive_outlined),
            onPressed: () => exportAllProfiles(context),
            child: const DVText('${AppStrings.exportAll}...'),
          ),
        ],
      ],
      builder: (context, controller, _) => DVIconButton(
        icon: Icons.add,
        label: tr(Strings.globalActionsAdd),
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );

void newEmptyProfile(BuildContext context) {
  final profile = DraftStore.create(ProfileStore.state.firstUniqueName(tr(Strings.placeholdersProfileName)));
  DV.Navigation.push(DVRoutes.profiles(id: profile.id));
}

/// `ProfileImporterModifier`: pick .ovpn/.conf files (or .zip archives of
/// them, as the WireGuard apps export) and import each.
Future<void> importProfileFile(BuildContext context) => runGuarded(context, () async {
      final files = await DV.Platform.fileStorage.pick(multiple: true);
      if (files.isEmpty || !context.mounted) return;
      await importPickedFiles(context, files);
    }, title: tr(Strings.globalActionsImport));

// ---------------------------------------------------------------------------
// Installed profile header

/// `InstalledProfileView`: the active profile pinned on top, with its status and switch.
@DVFunctionalWidget()
Widget _installedProfileHeader(BuildContext context) {
  final tunnel = context.global<TunnelState>();
  final profiles = context.global<ProfilesState>();
  final active = tunnel.activeProfileId == null ? null : profiles.byId(tunnel.activeProfileId!);
  final theme = Theme.of(context);
  // titleLarge, semibold.
  final nameStyle = const DVModifier().fontSize(22).fontWeight(.w600);
  return Card(
    elevation: 0,
    margin: const .fromLTRB(16, 8, 16, 8),
    color: theme.colorScheme.surface,
    shape: RoundedRectangleBorder(borderRadius: .circular(10)),
    child: DVBox.row(
      <Widget>[
        Expanded(
          child: DVBox.list(
            <Widget>[
              if (active == null)
                DVText(tr(Strings.viewsAppInstalledProfileNoneName), nameStyle)
              else
                ProfileMenuButton(
                  profile: active,
                  installed: true,
                  child: DVBox.row(
                    <Widget>[
                      Flexible(child: DVText(active.name, nameStyle)),
                      const Icon(Icons.expand_more, size: 20),
                    ],
                    spacing: 0,
                    crossAlign: .center,
                  ),
                ),
              const SizedBox(height: 12),
              if (active == null)
                DVText(tr(Strings.viewsAppInstalledProfileNoneStatus), const DVModifier().color(theme.colorScheme.onSurfaceVariant))
              else
                ConnectionStatusText(profileId: active.id),
            ],
            spacing: 0,
            crossAlign: .start,
          ),
        ),
        if (active != null) TunnelToggle(profileId: active.id),
      ],
      spacing: 0,
      crossAlign: .center,
      modifier: const DVModifier().paddingOnly(left: 16, top: 16, right: 12, bottom: 16),
    ),
  );
}

// ---------------------------------------------------------------------------
// List and grid

/// The red "delete" strip behind a row swiped to the left.
@DVFunctionalWidget()
Widget _swipeToDeleteBackground(BuildContext context) => DVBox(
      const Icon(Icons.delete, color: Colors.white),
      const DVModifier().backgroundColor(PSColors.error).align(Alignment.centerRight).paddingOnly(right: 20),
    );

@DVFunctionalWidget()
Widget _profileList(BuildContext context, {Widget? header, required List<TunnelProfile> profiles}) => PSForm(children: <Widget>[
      ?header,
      PSSection(
        header: tr(Strings.viewsAppFoldersDefault),
        children: <Widget>[
          for (final profile in profiles)
            Dismissible(
              key: ValueKey<String>(profile.id),
              direction: DismissDirection.endToStart,
              background: const SwipeToDeleteBackground(),
              confirmDismiss: (_) => confirmDeleteProfile(context, profile),
              child: ProfileRow(profile: profile),
            ),
        ],
      ),
    ]);

@DVFunctionalWidget()
Widget _profileGrid(BuildContext context, {Widget? header, required List<TunnelProfile> profiles}) => ListView(
      padding: const .all(8),
      children: <Widget>[
        ?header,
        Padding(
          padding: const .fromLTRB(16, 8, 16, 0),
          child: GridView.extent(
            maxCrossAxisExtent: 300,
            childAspectRatio: 2.4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[for (final profile in profiles) ProfileGridCell(profile: profile)],
          ),
        ),
      ],
    );

/// A grid cell toggles the connection on tap; its info button edits.
@DVFunctionalWidget()
Widget _profileGridCell(BuildContext context, {required TunnelProfile profile}) {
  final theme = Theme.of(context);
  final active = context.global<TunnelState>().isActive(profile.id);
  return ProfileMenuButton(
    profile: profile,
    asContextMenu: true,
    child: Material(
      color: active ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surface,
      borderRadius: .circular(10),
      child: Tooltip(
        message: '${tr(active ? Strings.globalActionsDisconnect : Strings.globalActionsConnect)}: ${profile.name}',
        excludeFromSemantics: true,
        // Hover only: a long press opens the context menu.
        triggerMode: TooltipTriggerMode.manual,
        child: InkWell(
          borderRadius: .circular(10),
          onTap: () => TunnelStore.toggle(profile).catchError((Object error) {
            if (context.mounted) showErrorAlert(context, title: profile.name, message: '$error');
          }),
          child: DVBox.row(
            <Widget>[
              Expanded(child: ProfileCard(profile: profile)),
              DVIconButton(
                icon: Icons.info_outline,
                label: tr(Strings.globalActionsEdit),
                onPressed: () => editProfile(profile),
              ),
            ],
            spacing: 0,
            crossAlign: .center,
            modifier: const DVModifier().padding(14),
          ),
        ),
      ),
    ),
  );
}

/// `ProfileRowView`: card (tap to edit), then the connect switch.
@DVFunctionalWidget()
Widget _profileRow(BuildContext context, {required TunnelProfile profile}) => ProfileMenuButton(
      profile: profile,
      asContextMenu: true,
      child: Tooltip(
        message: '${tr(Strings.globalActionsEdit)}: ${profile.name}',
        excludeFromSemantics: true,
        // Hover only: a long press opens the context menu.
        triggerMode: TooltipTriggerMode.manual,
        child: InkWell(
          onTap: () => editProfile(profile),
          child: DVBox.row(
            <Widget>[
              Expanded(child: ProfileCard(profile: profile)),
              TunnelToggle(profileId: profile.id),
            ],
            spacing: 0,
            crossAlign: .center,
            modifier: const DVModifier().paddingOnly(left: 16, top: 10, right: 12, bottom: 10),
          ),
        ),
      ),
    );

/// `ProfileCardView`: name (headline) over its status (subheadline).
@DVFunctionalWidget()
Widget _profileCard(BuildContext context, {required TunnelProfile profile}) => DVBox.list(
      <Widget>[
        // titleMedium, semibold.
        DVText(profile.name, const DVModifier().fontSize(16).fontWeight(.w600)),
        const SizedBox(height: 2),
        ConnectionStatusText(profileId: profile.id),
      ],
      spacing: 0,
      crossAlign: .start,
    );

void editProfile(TunnelProfile profile) {
  DraftStore.open(profile.id);
  DV.Navigation.push(DVRoutes.profiles(id: profile.id));
}

Future<bool> confirmDeleteProfile(BuildContext context, TunnelProfile profile) async {
  final confirmed = await confirmDestructive(
    context,
    title: tr(Strings.globalActionsRemove),
    message: profile.name,
    action: tr(Strings.globalActionsRemove),
  );
  if (confirmed) await ProfileStore.remove(profile.id);
  return confirmed;
}

/// `ProfileContextMenu`: Reconnect | Edit, then Hide (installed) or Duplicate, Delete.
/// As a context menu it opens on right-click and long-press; otherwise on tap.
@DVFunctionalWidget()
Widget _profileMenuButton(
  BuildContext context, {
  required TunnelProfile profile,
  required Widget child,
  bool installed = false,
  bool asContextMenu = false,
}) {
  final items = <Widget>[
    MenuItemButton(
      leadingIcon: const Icon(Icons.refresh),
      onPressed: () => runGuarded(context, () => TunnelStore.reconnect(profile)),
      child: DVText(tr(Strings.globalActionsReconnect)),
    ),
    const Divider(height: 1),
    MenuItemButton(
      leadingIcon: const Icon(Icons.edit_outlined),
      onPressed: () => editProfile(profile),
      child: DVText(tr(Strings.globalActionsEdit)),
    ),
    if (profile.activeConnection != null)
      MenuItemButton(
        leadingIcon: const Icon(Icons.ios_share),
        onPressed: () => exportProfileFile(context, profile),
        child: const DVText('${AppStrings.exportProfile}...'),
      ),
    if (installed)
      MenuItemButton(
        leadingIcon: const Icon(Icons.visibility_off_outlined),
        onPressed: () => PreferencesStore.update((p) => p.copyWith(pinsActiveProfile: false)),
        child: DVText(tr(Strings.globalActionsHide)),
      ),
    if (!installed) ...<Widget>[
      MenuItemButton(
        leadingIcon: const Icon(Icons.copy_outlined),
        onPressed: () => runGuarded(context, () => ProfileStore.duplicate(profile.id)),
        child: DVText(tr(Strings.globalActionsDuplicate)),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.delete_outline, color: PSColors.error),
        onPressed: () => confirmDeleteProfile(context, profile),
        child: DVText(tr(Strings.globalActionsRemove), const DVModifier().color(PSColors.error)),
      ),
    ],
  ];
  return MenuAnchor(
    menuChildren: items,
    builder: (context, controller, _) => asContextMenu
        ? GestureDetector(
            onSecondaryTapDown: (details) => controller.open(position: details.localPosition),
            onLongPressStart: (details) => controller.open(position: details.localPosition),
            child: child,
          )
        : Tooltip(
            message: profile.name,
            excludeFromSemantics: true,
            child: InkWell(
              borderRadius: .circular(6),
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              child: child,
            ),
          ),
  );
}
