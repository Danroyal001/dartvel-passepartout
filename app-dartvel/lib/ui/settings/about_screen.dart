// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Upstream `LinksView` (About), `CreditsView`/`GenericCreditsView` (Credits),
// `VersionView` and `ChangelogView` (Version).
//
// Upstream pushes the license, notice and changelog pages without routes of
// their own. Here each has its own URL as a query on its parent page:
//   /settings/about/credits?license=<name>
//   /settings/about/credits?notice=<name>
//   /settings/version?changelog=1

import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';
import '../../l10n/strings.g.dart';
import '../../platform/vpn_service.dart';
import '../../state/app_log.dart';
import '../kit.dart';
import 'settings_support.dart';

/// `LinksView`. Shown as "About" in the route tree, titled "Links" as upstream.
@DVFunctionalWidget()
Widget _aboutScreen(BuildContext context) => PSScaffold(
      title: tr(Strings.viewsSettingsLinksTitle),
      body: PSForm(children: <Widget>[
        PSSection(header: tr(Strings.viewsSettingsLinksSectionsSupport), children: <Widget>[
          SettingsLinkRow(title: tr(Strings.viewsSettingsLinksRowsOpenDiscussion), url: SettingsConstants.discussionsUrl),
          // `WebDonationLink`: shown when there are no in-app purchases
          // and this is not a beta, which is this app on every platform.
          SettingsLinkRow(title: tr(Strings.viewsDonateTitle), url: SettingsConstants.donateUrl),
        ]),
        PSSection(header: tr(Strings.viewsSettingsLinksSectionsWeb), children: <Widget>[
          SettingsLinkRow(title: tr(Strings.viewsSettingsLinksRowsHomePage), url: SettingsConstants.homeUrl),
          SettingsLinkRow(title: tr(Strings.viewsSettingsLinksRowsBlog), url: SettingsConstants.blogUrl),
        ]),
        PSSection(children: <Widget>[
          SettingsLinkRow(title: tr(Strings.viewsSettingsLinksRowsDisclaimer), url: SettingsConstants.disclaimerUrl),
          SettingsLinkRow(title: tr(Strings.viewsSettingsLinksRowsPrivacyPolicy), url: SettingsConstants.privacyPolicyUrl),
        ]),
      ]),
    );

// ---------------------------------------------------------------------------
// Credits

/// The queries that open one license or notice on the Credits page.
const String creditsLicenseQuery = 'license';
const String creditsNoticeQuery = 'notice';

/// The bundled credits, or none when the asset cannot be read.
Future<Credits> loadCredits() async {
  try {
    return await Credits.load();
  } on Object catch (error) {
    AppLog.warning('Unable to load credits: $error');
    return const Credits();
  }
}

/// `contentForLicense`, kept for the life of the app as upstream's @State is
/// for the life of the view.
final Map<String, String> _contentForLicense = <String, String>{};

/// A license text fetched before, if any.
String? cachedLicenseText(CreditsLicense license) => _contentForLicense[license.name];

/// [license]'s text through [fetcher], kept for next time; on failure the
/// error's description, which upstream shows in place of the text.
Future<String> fetchLicenseText(CreditsLicense license, TextFetcher fetcher) async {
  try {
    return _contentForLicense[license.name] = await fetcher(license.licenseUrl);
  } on Object catch (error) {
    return '$error';
  }
}

/// `CreditsView`: licenses, notices and translators, from credits.json.
///
/// [credits] is given in tests, otherwise read from the asset; [query] is the
/// page query, read from the router when null.
@DVFunctionalWidget()
Widget _creditsScreen(
  BuildContext context, {
  Credits? credits,
  Map<String, String>? query,
  TextFetcher fetcher = fetchText,
}) {
  final DVSignal<Credits?> loaded = context.signal<Credits?>(null);
  runOnce(context, () async {
    if (credits == null) loaded.value = await loadCredits();
  });
  final shown = credits ?? loaded.value;
  if (shown == null) {
    return PSScaffold(
      title: tr(Strings.viewsSettingsCreditsTitle),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
  final current = query ?? currentRouteQuery(context);
  final licenseName = current[creditsLicenseQuery];
  final noticeName = current[creditsNoticeQuery];
  for (final license in shown.licenses) {
    if (license.name == licenseName) {
      return CreditsLicensePage(key: ValueKey<String>('license/${license.name}'), license: license, fetcher: fetcher);
    }
  }
  for (final notice in shown.notices) {
    if (notice.name == noticeName) return CreditsNoticePage(notice: notice);
  }
  return CreditsList(credits: shown);
}

@DVFunctionalWidget()
Widget _creditsList(BuildContext context, {required Credits credits}) => PSScaffold(
      title: tr(Strings.viewsSettingsCreditsTitle),
      body: PSForm(children: <Widget>[
        if (credits.licenses.isNotEmpty)
          PSSection(header: tr(Strings.viewsSettingsCreditsLicenses), children: <Widget>[
            for (final license in credits.sortedLicenses)
              PSRow(
                title: license.name,
                value: license.licenseName,
                navigates: true,
                onTap: () => pushRoute(DVRoutes.settingsaboutcredits.withQuery(<String, String>{creditsLicenseQuery: license.name})),
              ),
          ]),
        if (credits.notices.isNotEmpty)
          PSSection(header: tr(Strings.viewsSettingsCreditsNotices), children: <Widget>[
            for (final notice in credits.sortedNotices)
              PSRow(
                title: notice.name,
                navigates: true,
                onTap: () => pushRoute(DVRoutes.settingsaboutcredits.withQuery(<String, String>{creditsNoticeQuery: notice.name})),
              ),
          ]),
        if (credits.translations.isNotEmpty)
          PSSection(header: tr(Strings.viewsSettingsCreditsTranslations), children: <Widget>[
            for (final code in credits.sortedLanguages)
              CreditsTranslationRow(language: languageName(code), authors: credits.translations[code] ?? const <String>[]),
          ]),
      ]),
    );

@DVFunctionalWidget()
Widget _creditsTranslationRow(BuildContext context, {required String language, required List<String> authors}) {
  final secondary = DVModifier().color(Theme.of(context).colorScheme.onSurfaceVariant);
  return ListTile(
    title: DVText(language),
    trailing: DVBox.list(
      <Widget>[for (final author in authors) DVText(author, secondary)],
      spacing: 0,
      crossAlign: .end,
    ),
  );
}

/// `GenericCreditsView.LicenseView`: the license text, fetched, monospaced.
@DVFunctionalWidget()
Widget _creditsLicensePage(BuildContext context, {required CreditsLicense license, required TextFetcher fetcher}) {
  final DVSignal<String?> content = context.signal<String?>(cachedLicenseText(license));
  runOnce(context, () async {
    if (content.read() == null) content.value = await fetchLicenseText(license, fetcher);
  });
  final text = content.value;
  return PSScaffold(
    title: license.name,
    body: text == null
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const .all(16),
            child: DVText(text, const DVModifier().fontFamily('monospace')),
          ),
  );
}

@DVFunctionalWidget()
Widget _creditsNoticePage(BuildContext context, {required CreditsNotice notice}) => PSScaffold(
      title: notice.name,
      body: DVBox(DVText(notice.message), const DVModifier().padding(16).align(.topLeft)),
    );

// ---------------------------------------------------------------------------
// Version

/// The query that opens the changelog on the Version page.
const String versionChangelogQuery = 'changelog';

/// `VersionView`: logo, name, version, credit line and the CHANGELOG button.
@DVFunctionalWidget()
Widget _versionScreen(
  BuildContext context, {
  Map<String, String>? query,
  TextFetcher fetcher = fetchText,
  String? partoutVersion,
}) {
  final current = query ?? currentRouteQuery(context);
  if (current.containsKey(versionChangelogQuery)) return ChangelogScreen(fetcher: fetcher);
  final theme = Theme.of(context);
  return PSScaffold(
    title: tr(Strings.viewsSettingsTitle),
    body: SingleChildScrollView(
      padding: const .all(24),
      // DVText has no textAlign; the ambient style centres the credit line.
      child: DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        child: DVBox.list(
          <Widget>[
            Image.asset('assets/icon.png', width: 120, height: 120, semanticLabel: SettingsUnlocalized.appName,
                errorBuilder: (_, _, _) => const SizedBox.square(dimension: 120)),
            const SizedBox(height: 24),
            DVText(SettingsUnlocalized.appName, DVModifier().fontSize(theme.textTheme.displaySmall?.fontSize ?? 36)),
            const SizedBox(height: 8),
            DVText(
              SettingsBundle.versionString,
              DVModifier().fontSize(theme.textTheme.titleMedium?.fontSize ?? 16).color(theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            DVText(tr(Strings.viewsVersionExtra, <Object>['Passepartout', SettingsUnlocalized.authorName])),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => pushRoute(DVRoutes.settingsversion.withQuery(const <String, String>{versionChangelogQuery: '1'})),
              child: const DVText(SettingsUnlocalized.changelog),
            ),
            const SizedBox(height: 24),
            // Not in upstream's VersionView: the engine version.
            PSSection(children: <Widget>[EngineVersionRow(version: partoutVersion)]),
          ],
          spacing: 0,
          crossAlign: .center,
        ),
      ),
    ),
  );
}

/// The entries of [build]'s CHANGELOG.txt; none without a build or when it
/// cannot be fetched.
Future<List<ChangelogEntry>> loadChangelog(TextFetcher fetcher, String? build) async {
  if (build == null) return const <ChangelogEntry>[];
  try {
    return ChangelogEntry.parseAll(await fetcher(SettingsConstants.urlForChangelog(build)));
  } on Object catch (error) {
    AppLog.error('CHANGELOG: Unable to load: $error');
    return const <ChangelogEntry>[];
  }
}

/// `ChangelogView`: the build's CHANGELOG.txt, one row per entry, issue rows
/// open on GitHub. [buildNumber] is the build whose changelog to load; this
/// app has no build number yet. (Not `build`: the generated widget's build
/// method would clash with it.)
@DVFunctionalWidget()
Widget _changelogScreen(BuildContext context, {TextFetcher fetcher = fetchText, String? buildNumber}) {
  final DVSignal<List<ChangelogEntry>?> entries = context.signal<List<ChangelogEntry>?>(null);
  runOnce(context, () async {
    entries.value = await loadChangelog(fetcher, buildNumber ?? SettingsBundle.buildNumber?.toString());
  });
  final loaded = entries.value;
  return PSScaffold(
    title: SettingsUnlocalized.changelog,
    body: loaded == null
        ? const Center(child: CircularProgressIndicator())
        : loaded.isEmpty
            ? PSEmptyMessage(text: tr(Strings.globalNounsNoContent))
            : PSForm(children: <Widget>[
                PSSection(header: SettingsBundle.versionString, children: <Widget>[
                  for (final entry in loaded)
                    if (entry.issueUrl != null)
                      SettingsLinkRow(title: entry.comment, url: entry.issueUrl!)
                    else
                      PSRow(title: entry.comment),
                ]),
              ]),
  );
}

/// `VpnService.engineVersion()`, or "Unknown" when it cannot be read.
Future<String> loadEngineVersion() async {
  try {
    return await VpnService.instance.engineVersion();
  } on Object catch (error) {
    AppLog.warning('Unable to read the engine version: $error');
    return 'Unknown';
  }
}

/// "Partout  <version>", from `VpnService.engineVersion()` unless [version] is given.
@DVFunctionalWidget()
Widget _engineVersionRow(BuildContext context, {String? version}) {
  final DVSignal<String?> loaded = context.signal<String?>(null);
  runOnce(context, () async {
    if (version == null) loaded.value = await loadEngineVersion();
  });
  return PSRow(
    title: SettingsUnlocalized.partout,
    value: version ?? loaded.value ?? '…',
    monospaced: true,
  );
}
