// SPDX-License-Identifier: GPL-3.0
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:passepartout/platform/tunnel/helper_input.dart';

Stream<List<int>> bytes(List<String> parts) => Stream.fromIterable(parts.map(utf8.encode));

void main() {
  test('first line is the profile, later lines are commands', () async {
    final input = HelperInput(bytes(['{"a":', '1}\nsto', 'p\nother\n']));
    expect(await input.profile, '{"a":1}');
    expect(await input.commands.toList(), ['stop', 'other']);
  });
  test('stdin closing ends the command stream', () async {
    final input = HelperInput(bytes(['{}\n']));
    expect(await input.profile, '{}');
    expect(await input.commands.toList(), isEmpty);
  });
  test('missing profile is a fixed error', () async {
    await expectLater(HelperInput(bytes([])).profile, throwsA(isA<HelperInputException>().having((e) => e.code, 'code', 'profile_missing')));
    await expectLater(HelperInput(bytes(['{"x":1}'])).profile, throwsA(isA<HelperInputException>().having((e) => e.code, 'code', 'profile_missing')));
  });
  test('oversized profile is refused without echoing it', () async {
    final input = HelperInput(bytes(['{"k":"', 'A' * 100, '"}\n']), maxProfileBytes: 50);
    await expectLater(
      input.profile,
      throwsA(isA<HelperInputException>().having((e) => e.code, 'code', 'profile_too_large').having((e) => e.toString().contains('AAAA'), 'echo', false)),
    );
  });
  test('invalid profile error never contains file or input content', () async {
    for (final text in ['not json secret-xyz\n', '[1,2]\n', '"secret-xyz"\n']) {
      final input = HelperInput(bytes([text]));
      Object? error;
      try {
        await input.profile;
      } catch (e) {
        error = e;
      }
      expect(error, isA<HelperInputException>());
      expect((error as HelperInputException).code, 'profile_invalid');
      expect(error.toString().contains('secret'), false);
    }
  });
}
