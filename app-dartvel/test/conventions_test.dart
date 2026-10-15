// SPDX-License-Identifier: GPL-3.0
// Copyright 2026 SigmaDev

// Dartvel conventions this application holds itself to, checked on the
// source. Each rule lists every offending file and line, so a failure says
// exactly what to change. Generated code (lib/dartvel_client, the ffigen
// bindings) is not application code and is skipped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Application source files, relative to the package root.
List<File> _appSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.startsWith('lib/dartvel_client/') && !f.path.startsWith('lib/platform/generated/'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

/// `file:line: text` for every line of [files] matching [pattern], skipping
/// comment lines.
List<String> _offenders(Iterable<File> files, RegExp pattern) => <String>[
      for (final file in files)
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (!line.trimLeft().startsWith('//') && pattern.hasMatch(line)) '${file.path}:${index + 1}: ${line.trim()}',
    ];

/// The engine's ABI, the helper's stdio protocol and the files on disk are
/// JSON by nature; these files are where that format is read and written, and
/// nowhere else. Each entry says why it is allowed.
const Map<String, String> _jsonBoundary = <String, String>{
  'lib/domain/profile.dart': "Partout's profile document (openapi.yaml), encoded and decoded once at the engine boundary",
  'lib/platform/vpn_service_native.dart': "Partout's C ABI takes and returns JSON strings",
  'lib/platform/tunnel/tunnel_protocol.dart': "the tunnel helper's stdio line protocol",
  'lib/platform/tunnel/helper_input.dart': 'checks the profile line the helper reads is a JSON object',
  'lib/platform/tunnel/linux_network.dart': "the helper's root-owned state file under /run",
  'lib/state/app_state.dart': 'TODO(dartvel-models): preferences and profiles on DV.Platform.fileStorage',
  'lib/domain/rule_groups.dart': 'TODO(dartvel-models): the rule group record stored by RuleGroupStore',
  'lib/state/rule_groups_store.dart': 'TODO(dartvel-models): rule groups on DV.Platform.fileStorage',
  'lib/state/on_demand_store.dart': 'TODO(dartvel-models): on-demand state on DV.Platform.fileStorage',
  'lib/ui/settings/settings_support.dart': 'the bundled credits asset (assets/credits)',
};

void main() {
  final sources = _appSources();

  test('widgets are DVFunctionalWidget or DVClassWidget, never Stateless/StatefulWidget', () {
    expect(_offenders(sources, RegExp(r'extends\s+(StatelessWidget|StatefulWidget|State<)')), isEmpty);
  });

  test('text is DVText and boxes are DVBox: no Text, SelectableText or Container', () {
    expect(_offenders(sources, RegExp(r'(?<![\w.])(Text|SelectableText|Container)(\.rich)?\(')), isEmpty);
  });

  test('state is signals: no Listenable builders or notifiers', () {
    expect(
      _offenders(sources, RegExp(r'\b(ListenableBuilder|ValueListenableBuilder|AnimatedBuilder|ValueNotifier|ChangeNotifier)\b')),
      isEmpty,
    );
  });

  test('icon-only buttons are DVIconButton (label = tooltip + screen-reader name)', () {
    expect(_offenders(sources, RegExp(r'(?<![\w.])IconButton(\.\w+)?\(')), isEmpty);
  });

  test('JSON stays at the engine, helper and storage boundaries', () {
    final json = RegExp(r'\b(jsonEncode|jsonDecode|toJson|fromJson)\b');
    final outside = _offenders(sources.where((f) => !_jsonBoundary.containsKey(f.path)), json);
    expect(outside, isEmpty);
    // The list only shrinks: an entry whose file no longer needs JSON goes.
    for (final path in _jsonBoundary.keys) {
      expect(json.hasMatch(File(path).readAsStringSync()), isTrue, reason: '$path no longer uses JSON: remove it from the list');
    }
  });

  test('backend functions take and return typed values: no JSON, no Map payloads', () {
    final functions = sources.where((f) => f.path.startsWith('lib/backend/'));
    expect(_offenders(functions, RegExp(r'Map<String,\s*(dynamic|Object\?)>|jsonEncode|jsonDecode')), isEmpty);
  });

  test('main.dart only runs the app through DV.run', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('DV.run('));
    expect(main, isNot(contains('runApp(')));
    expect(RegExp(r'^(class|Widget|ThemeData)\b', multiLine: true).hasMatch(main), isFalse,
        reason: 'the app widget and theme live outside main.dart');
  });

  test('pages have an index and a guard', () {
    expect(File('lib/pages/index.dart').existsSync(), isTrue);
    final guard = File('lib/pages/_guard.dart');
    expect(guard.existsSync(), isTrue);
    expect(guard.readAsStringSync(), contains('guard(BuildContext context, GoRouterState state)'));
  });

  test('no private host paths or host tooling in the repository text', () {
    final texts = <File>[
      ...sources,
      for (final dir in <String>['docs', 'tool', 'test'])
        ...Directory(dir).listSync(recursive: true).whereType<File>().where((f) => RegExp(r'\.(md|dart|ya?ml|txt|json|policy|c|h)$').hasMatch(f.path)),
      File('README.md'),
      File('pubspec.yaml'),
    ].where((f) => f.path != 'test/conventions_test.dart');
    expect(_offenders(texts, RegExp(r'/home/sigmadev|heavy\.sh|~/\.local/zig|/tmp/pp-tunnel-build')), isEmpty);
  });
}
