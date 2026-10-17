# Dartvel gaps

Things this port needed that Dartvel does not provide, with a repro each.

## settings

### No `DV.Platform` API to open an external URL

Settings rows open web pages (FAQ, Links, license sources) and `mailto:` (Report issue).
`DV.Platform` has share, clipboard, files and so on, but nothing like `openUrl(url)`.

Repro:

```dart
DV.Platform.openUrl('https://partout.io/passepartout/faq'); // no such member
```

What exists: `DVNavLink.external(url, child: ...)` (a link widget) and `DVLinkOpener.open(url)`, the
funnel those links use, installed by the generated router. The port calls `DVLinkOpener.open(url, newTab: true)`.
It returns nothing, so the app cannot tell when no handler opened the URL (upstream shows
"unable to email" when `mailto:` cannot be opened). Wanted: `Future<bool> DV.Platform.openUrl(String url)`.

### No generated app version constant

pubspec `version:` is not available at runtime without a plugin (package_info). Settings > Version repeats
it as a constant (`SettingsBundle.versionNumber`), checked against pubspec by a test.
Wanted: a generated `DV.app.version` / build number.

### No language display names

Credits > Translations names each language. Upstream uses Foundation's localized language names; Dartvel's
`DVI18n` has no display-name table, so the port names each language in itself (Deutsch, Français...).

## lead

### Web-server build rejects some dot shorthands that `dart analyze` and Flutter accept

`dartvel build web-server` failed with `The static getter or field 'w600' isn't defined for the type 'invalid-type'`
for `theme.textTheme.titleMedium?.copyWith(fontWeight: .w600)` and for `Text(..., textAlign: .center)`, while
the same shorthands compile for web and pass `dart analyze`. The server compile resolves those parameter types
to an invalid type, so a shorthand has no context. Repro: any page using `Text('x', textAlign: .center)`, then
`dartvel build web-server`. Workaround in the app: spell the type (`TextAlign.center`). Fix belongs in the
server-side compile of pages (the shorthand rule in the generated CLAUDE.md promises they work).

### Backend functions silently lose imports that reach Flutter

A backend function importing `../../platform/vpn_service.dart` failed with `Undefined name 'VpnService'`,
because that file (transitively) imported Flutter and the generator drops such imports without a word.
Wanted: a build error naming the import chain that reaches Flutter.
## modules (sub-page routes)

### `DV.Navigation.push` does not put the pushed page's URL in the address bar

Module sub-pages are real routes (`/profiles/<id>/modules/<moduleId>/<section>`), open from their
URL on a reload, and are pushed over the module page so back pops to it:

```dart
DV.Navigation.push<void>(DVRoutes.profilesmodulesIdModuleIdSection(id: id, moduleId: moduleId, section: 'ca'));
DV.Navigation.currentPath; // still '/profiles/<id>/modules/<moduleId>'
```

`DV.Navigation.push` is go_router's `push`, and go_router leaves the URL at the page underneath unless
`GoRouter.optionURLReflectsImperativeAPIs` is true (default false). On the web the address bar,
copy-link and reload therefore show the module page, not the sub-page. Every `DV.Navigation.push`
in the app has this (profile list → profile, settings → sub-pages). Wanted: Dartvel's push
reflects the pushed page's URL (the generated router setting the option, or `push` doing it
itself) so that every page has its own URL in the address bar. The app does not set the
go_router flag itself; the fix belongs in the framework.

### Only one generated-router app per test file

In a widget test, a second `createDartvelApp()` in the same file (a new `testWidgets`) renders an
empty page at any URL after the first test's app; the first renders fine. Probably the router's
once-per-process setup (`_dartvelSetUp`, deferred page loaders) keeps state from the first app.
`test/module_subpages_test.dart` works around it by opening every URL from one app.

### `dartvel build linux` rewrites tracked project files

Every Linux build modifies `.metadata` and `analysis_options.yaml` (and touches `pubspec.lock`), so a clean
worktree is dirty after a build. Repro: `git status` clean, `dartvel build linux`, `git status`. Wanted: a
build leaves committed project files alone.

## feature port (TunnlTo / WireGuard apps)

### No API for the network kind or the Wi-Fi name

On-demand rules need to know whether the device is on Wi-Fi (and which SSID), mobile data or
Ethernet. `DV.Platform.network` reports only online/metered/offline/unknown. The app reads
NetworkManager (`nmcli`) itself on Linux (`lib/platform/network/`); every other target answers
"unknown", so the app does not evaluate on-demand rules there. Wanted:
`DV.Platform.network.kind` (wifi/mobile/ethernet/other) and `DV.Platform.network.wifiName`
(with the location permission it needs on iOS/Android).

### No save-file or share-file API on phones and the web

Exporting a zip uses `DV.Platform.dialogs.saveFile` + a file write, which exists on desktops only.
`DV.Platform.share` shares text, not files. Wanted: `DV.Platform.share.shareFile(name, bytes)` and a
browser download fallback.

### No live camera preview

QR import takes one photo (`DV.Platform.camera.takePhoto`) or an image file. A live scanner needs
a camera preview stream from Dartvel.

## conventions (audit 2026-10, Dartvel 0.12.2)

### Closed in Dartvel 0.13

- `main` is `void main(List<String> args) => DV.run(args);`. Startup is a private `@DVBoot`
  (lib/app.dart) and the root an `@DVAppRoot` using `parts.router`. The saved data loads in
  the background from the boot step, so the first frame does not wait on the disk; Dartvel has
  no after-first-frame hook, and per the owner boot stays independent of any UI.
- `@DVBackendFunction(middleware: [...])` replaced `@DVUseMiddleware` on backend functions.

### Typed backend functions stop at primitives and maps

The generated client decodes `String`, numbers, `bool`, lists of those and `Map<String, Object?>`;
any other return type, `@DVModel` classes included, generates a client function that needs a
`fromJson:` mapper, so the application writes JSON decoding after all. Repro: a backend function
returning a `@DVModel` type; its client function has a required `fromJson` parameter.

### No device-only data model

`@DVModel(offline: ...)` keeps a local store but replays writes to the server. VPN profiles hold
private keys and must never leave the device, so the app keeps them (and preferences, rule groups,
on-demand state) as JSON files in `DV.Platform.fileStorage`. Wanted: a model whose store is the
device only (no server table, no replay), with the same `save()`/`find()` surface.

### Functional widgets: no lifecycle, no type parameters, listeners not released

- No `init`/`dispose` for `@DVFunctionalWidget`: an initial load or a periodic refresh needs a
  workaround (lib/ui/kit.dart `runOnce`, `everyWhileMounted`, built on a signal and a timer that
  checks `context.mounted`).
- `Widget _list<T>(...)` is not recognised (the name regex expects `(` right after the name), so a
  generic widget must become index-based (`PSPickerRow` + `pickerRow<T>()`).
- `DVSignal.value` subscribes the element through `container.listen` and the subscription is kept
  in an `Expando` that is never closed when the element unmounts.

### DV inputs and text

The `DVModifier.input(...)` field has no keyboard type, autofocus, text alignment, max length or
text style (monospace); `DVText` has no `textAlign`. Number and URL fields therefore show the
plain keyboard on phones. `DVIconButton.onPressed` is non-nullable, so a disabled icon button
cannot be expressed.

### No conventions check in the published CLI

`dartvel doctor` 0.12.2 has the tooltip lint but no `--conventions` (StatelessWidget, `Text`,
Listenable builders, JSON in app code, `main.dart`). This app checks them itself in
test/conventions_test.dart.

### Analyzing the generated server reports false errors

`dart analyze .dart_tool/dartvel_backend_routes.g.dart` reports undefined named parameters
(`pageData`, `pageStore`, ...) on `dv.serve`: `dartvel_shelf` exports `serve` conditionally
(`if (dart.library.ffi)`) and the analyzer checks the non-FFI stub. The VM build uses the right one.

### No way to declare an Android service or an Apple app extension

Android needs a `VpnService` subclass with a `<service android:permission="android.permission.BIND_VPN_SERVICE">`
manifest entry and intent filter; Apple needs a packet-tunnel app extension target with its own
entitlements. A Dartvel app cannot declare either from pubspec (native folders are generated and
not committed). Repro: enable android/ios in pubspec and try to express the `<service>` entry or the
extension target. Details and the planned design: docs/TUNNEL.md. Connecting is therefore Linux-only.
