// SPDX-License-Identifier: GPL-3.0
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:passepartout/domain/tunnel_status.dart';
import 'package:passepartout/platform/tunnel/tunnel_process.dart';
import 'package:passepartout/platform/tunnel/tunnel_protocol.dart';

/// The Dart SDK that ships with the Flutter running this test: the fake
/// helpers are Dart scripts, like the real one.
String get dartExecutable {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) return '$root/bin/dart';
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
  final cache = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  return '${cache.path}/dart-sdk/bin/dart';
}

void main() {
  test('protocol reads typed events', () {
    expect(parseTunnelLine('{"type":"status","status":"connected"}'), const HelperStatus(TunnelStatus.connected));
    expect(parseTunnelLine('{"type":"data","received":42,"sent":7}'), const HelperData(received: 42, sent: 7));
    expect(parseTunnelLine('{"type":"error","code":"denied"}'), const HelperError('denied'));
    expect(parseTunnelLine('{"type":"log","level":3,"message":"hi"}'), const HelperLog(level: 3, message: 'hi'));
    expect(parseTunnelLine('{"type":"ready","pid":12}'), const HelperReady(12));
    expect(parseTunnelLine('{"type":"exit","code":1}'), const HelperExit(1));
    expect(parseTunnelLine('{"type":"network","state":"restored"}'), const HelperNetworkRestored());
    for (final line in [
      '[]',
      'oops',
      '{"type":"status","status":"oops"}',
      '{"type":"data","received":-1,"sent":0}',
      '{"type":"ready","pid":0}',
      '{"type":"network","state":"other"}',
      '{"type":"unknown"}',
    ]) {
      expect(() => parseTunnelLine(line), throwsFormatException, reason: line);
    }
  });

  test('events written by the helper read back the same', () {
    const events = <HelperEvent>[
      HelperStatus(TunnelStatus.connecting),
      HelperData(received: 1, sent: 2),
      HelperError('network_setup'),
      HelperLog(level: 1, message: 'line'),
      HelperReady(99),
      HelperExit(0),
      HelperNetworkRestored(),
    ];
    for (final event in events) {
      expect(parseTunnelLine(event.encode()), event);
    }
  });

  test('a failure event names the error type, never its text', () {
    final event = HelperError.fromFailure('network_setup', StateError('ip failed: secret-key-material'));
    expect(event.code, 'network_setup');
    expect(event.encode(), isNot(contains('secret')));
    expect(event.encode(), contains('StateError'));
  });

  test('cleanup is needed only when a started helper ended without restoring', () {
    expect(helperNeedsCleanup(started: false, restored: false, exitCode: 126), false);
    expect(helperNeedsCleanup(started: true, restored: true, exitCode: 1), false);
    expect(helperNeedsCleanup(started: true, restored: false, exitCode: 0), false);
    expect(helperNeedsCleanup(started: true, restored: false, exitCode: -9), true);
    expect(helperNeedsCleanup(started: true, restored: false, exitCode: 255), true);
  });

  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tunnel-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<String> helper(String body) async {
    final file = File('${temp.path}/fake_helper.dart');
    await file.writeAsString("import 'dart:convert';\nimport 'dart:io';\n$body");
    return file.path;
  }

  test('profile on stdin, stream, duplicate guard and stop', () async {
    final report = '${temp.path}/report';
    final script = await helper('''
Future<void> main(List<String> args) async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  var first = true;
  await for (final line in lines) {
    if (first) {
      first = false;
      File(${_quote(report)}).writeAsStringSync(jsonEncode({'argv': args, 'profile': line}));
      print(jsonEncode({'type': 'ready', 'pid': pid}));
      print('invalid');
      print(jsonEncode({'type': 'status', 'status': 'connecting'}));
      print(jsonEncode({'type': 'data', 'received': 100, 'sent': 25}));
      stderr.writeln('native log');
      continue;
    }
    if (line.trim() == 'stop') break;
  }
  print(jsonEncode({'type': 'network', 'state': 'restored'}));
}
''');
    final events = <HelperEvent>[];
    final logs = <String>[];
    final process = TunnelProcess(dartExecutable, prefix: [script]);
    await process.start('{"secret":"test"}', events.add, logs.add);
    // No path or profile on the command line; the profile arrived on stdin.
    final recorded = await File(report).readAsString();
    expect(recorded, '{"argv":["--stdin"],"profile":"{\\"secret\\":\\"test\\"}"}');
    await expectLater(process.start('{}', events.add, logs.add), throwsStateError);
    await process.stop();
    await process.stop();
    expect(events, contains(const HelperData(received: 100, sent: 25)));
    expect(events.last, const HelperStatus(TunnelStatus.disconnected));
    expect(events, contains(const HelperTerminated(exitCode: 0, needsCleanup: false)));
    expect(logs, contains('native log'));
    expect(logs, contains('Invalid helper event'));
  });

  test('no temp profile file is written', () async {
    final before = Directory.systemTemp.listSync().where((e) => e.path.contains('partout-')).length;
    final script = await helper('''
Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim() == 'stop') break;
    print(jsonEncode({'type': 'ready', 'pid': pid}));
  }
}
''');
    final process = TunnelProcess(dartExecutable, prefix: [script]);
    await process.start('{"k":1}', (_) {}, (_) {});
    final during = Directory.systemTemp.listSync().where((e) => e.path.contains('partout-')).length;
    await process.stop();
    expect(during, before);
  });

  test('a started helper that dies without restoring asks for cleanup', () async {
    final script = await helper('''
Future<void> main() async {
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  print(jsonEncode({'type': 'ready', 'pid': pid}));
  await stdout.flush();
  exit(3);
}
''');
    final events = <HelperEvent>[];
    final process = TunnelProcess(dartExecutable, prefix: [script]);
    await process.start('{}', events.add, (_) {});
    await process.finished;
    expect(events, contains(const HelperTerminated(exitCode: 3, needsCleanup: true)));
  });

  test('early exit fails the start and needs no cleanup', () async {
    final script = await helper('void main() => exit(7);\n');
    final events = <HelperEvent>[];
    final process = TunnelProcess(dartExecutable, prefix: [script]);
    await expectLater(process.start('{}', events.add, (_) {}), throwsStateError);
    expect(events, contains(const HelperTerminated(exitCode: 7, needsCleanup: false)));
  });

  test('timeout sends stop', () async {
    final script = await helper('''
Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim() == 'stop') break;
  }
}
''');
    final process = TunnelProcess(dartExecutable, prefix: [script], startTimeout: const Duration(milliseconds: 100));
    await expectLater(process.start('{}', (_) {}, (_) {}), throwsA(isA<Exception>()));
    await process.stop();
  });
}

String _quote(String value) => "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
