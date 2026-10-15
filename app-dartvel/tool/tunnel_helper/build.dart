// SPDX-License-Identifier: GPL-3.0
// Builds the Linux tunnel helper: the C bridge, the helper executable, and a
// copy of the engine libraries beside it (the helper loads them from there).
//
//   dart run tool/tunnel_helper/build.dart [OUTPUT_DIR]
//
// Paths default to this checkout; override with PARTOUT_SOURCE,
// PARTOUT_LIB_DIR and PARTOUT_OPENSSL_DIR (only needed when the engine was
// built with the prebuilt OpenSSL instead of the system one).
import 'dart:io';

Future<void> main(List<String> args) async {
  final app = File.fromUri(Platform.script).parent.parent.parent;
  Directory.current = app;
  final env = Platform.environment;
  final source = env['PARTOUT_SOURCE'] ?? '../partout';
  final libDir = env['PARTOUT_LIB_DIR'] ?? '../partout/bin/linux-x86_64/partout/lib';
  final opensslDir = env['PARTOUT_OPENSSL_DIR'] ?? '../partout/bin/linux-x86_64/openssl/lib';
  final output = Directory(args.isNotEmpty ? args.first : 'build/tunnel-helper');
  await output.create(recursive: true);

  await _run(env['CC'] ?? 'cc', [
    '-std=gnu11', '-Wall', '-Wextra', '-Werror', '-fPIC', '-shared', '-pthread',
    '-I', '$source/src', 'tool/tunnel_helper/bridge.c', '-ldl',
    '-o', '${output.path}/libtunnel_bridge.so',
  ]);
  await _run(Platform.resolvedExecutable, [
    'compile', 'exe', 'tool/tunnel_helper/main.dart', '-o', '${output.path}/partout-tunnel',
  ]);
  var copied = 0;
  for (final dir in [libDir, opensslDir]) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync().whereType<File>()) {
      if (!file.path.contains('.so')) continue;
      await file.copy('${output.path}/${file.uri.pathSegments.last}');
      copied++;
    }
  }
  if (!File('${output.path}/libpartout.so').existsSync()) {
    stderr.writeln('libpartout.so not found in $libDir: build the engine first (docs/BUILD.md).');
    exitCode = 1;
    return;
  }
  stdout.writeln('Helper built in ${output.path} ($copied engine libraries copied).');
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(executable, arguments, mode: ProcessStartMode.inheritStdio);
  final code = await process.exitCode;
  if (code != 0) throw ProcessException(executable, arguments, 'exit $code', code);
}
