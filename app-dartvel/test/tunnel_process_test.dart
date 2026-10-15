// SPDX-License-Identifier: GPL-3.0
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:passepartout/platform/tunnel/tunnel_process.dart';
import 'package:passepartout/platform/tunnel/tunnel_protocol.dart';

void main() {
  test('protocol validates messages', () {
    expect(
      parseTunnelLine('{"type":"status","status":"connected"}')['status'],
      'connected',
    );
    expect(
      parseTunnelLine('{"type":"data","received":42,"sent":7}')['received'],
      42,
    );
    expect(
      parseTunnelLine('{"type":"error","code":"denied"}')['code'],
      'denied',
    );
    for (final line in [
      '[]',
      'oops',
      '{"type":"status","status":"oops"}',
      '{"type":"data","received":-1,"sent":0}',
      '{"type":"ready","pid":0}',
    ]) {
      expect(() => parseTunnelLine(line), throwsFormatException);
    }
  });
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tunnel-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<String> helper(String body) async {
    final file = File('${temp.path}/fake.py');
    await file.writeAsString(body);
    return file.path;
  }

  test('profile on stdin, stream, duplicate guard and stop', () async {
    final report = '${temp.path}/report';
    final script = await helper('''
import sys,os,json
first=sys.stdin.readline()
with open(${jsonEncode(report)},'w') as out:
 json.dump({'argv':sys.argv[1:],'profile':first},out)
print(json.dumps({'type':'ready','pid':os.getpid()}),flush=True)
print('invalid',flush=True)
print(json.dumps({'type':'status','status':'connecting'}),flush=True)
print(json.dumps({'type':'data','received':100,'sent':25}),flush=True)
print('native log',file=sys.stderr,flush=True)
for line in sys.stdin:
 if line.strip()=='stop': break
''');
    final events = <Map<String, dynamic>>[];
    final logs = <String>[];
    final process = TunnelProcess('/usr/bin/python3', prefix: [script]);
    await process.start('{"secret":"test"}', events.add, logs.add);
    final recorded = jsonDecode(await File(report).readAsString());
    // No path or profile on the command line, and the profile arrived on stdin.
    expect(recorded['argv'], ['--stdin']);
    expect(recorded['profile'], '{"secret":"test"}\n');
    await expectLater(
      process.start('{}', events.add, logs.add),
      throwsStateError,
    );
    await process.stop();
    await process.stop();
    expect(
      events.any((e) => e['type'] == 'data' && e['received'] == 100),
      true,
    );
    expect(events.last['status'], 'disconnected');
    expect(logs, contains('native log'));
    expect(logs, contains('Invalid helper event'));
  });
  test('no temp profile file is written', () async {
    final before = Directory.systemTemp.listSync().where((e) => e.path.contains('partout-')).length;
    final script = await helper(
      'import sys,os,json\nsys.stdin.readline()\nprint(json.dumps({"type":"ready","pid":os.getpid()}),flush=True)\nfor l in sys.stdin:\n if l.strip()=="stop": break\n',
    );
    final process = TunnelProcess('/usr/bin/python3', prefix: [script]);
    await process.start('{"k":1}', (_) {}, (_) {});
    final during = Directory.systemTemp.listSync().where((e) => e.path.contains('partout-')).length;
    await process.stop();
    expect(during, before);
  });
  test('early exit fails the start', () async {
    final script = await helper('import sys\nsys.exit(7)\n');
    final process = TunnelProcess('/usr/bin/python3', prefix: [script]);
    await expectLater(process.start('{}', (_) {}, (_) {}), throwsStateError);
  });
  test('timeout sends stop', () async {
    final script = await helper(
      'import sys\nfor line in sys.stdin:\n if line.strip()=="stop": break\n',
    );
    final process = TunnelProcess(
      '/usr/bin/python3',
      prefix: [script],
      startTimeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      process.start('{}', (_) {}, (_) {}),
      throwsA(isA<Exception>()),
    );
    await process.stop();
  });
}
