// SPDX-License-Identifier: GPL-3.0
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/tunnel_status.dart';
import 'tunnel_protocol.dart';

/// Runs the tunnel helper. The profile (it holds the private key) goes in as
/// the first stdin line: never on disk, never in argv.
class TunnelProcess {
  final String executable;
  final List<String> prefix;
  final Duration startTimeout;
  TunnelProcess(
    this.executable, {
    this.prefix = const [],
    this.startTimeout = const Duration(seconds: 90),
  });
  Process? _process;
  Future<void>? _finished;
  bool _starting = false;
  bool get isRunning => _process != null;

  /// Completes when the helper has exited and its last events are delivered.
  Future<void> get finished => _finished ?? Future<void>.value();

  Future<void> start(
    String profile,
    void Function(HelperEvent) event,
    void Function(String) log,
  ) async {
    if (_starting || _process != null) {
      throw StateError('Tunnel already running');
    }
    _starting = true;
    final ready = Completer<void>();
    var started = false;
    var restored = false;
    try {
      final process = await Process.start(executable, [...prefix, '--stdin']);
      _process = process;
      unawaited(process.stdin.done.catchError((Object _) {}));
      // JSON has no raw newlines, so the profile is exactly one line.
      process.stdin.writeln(profile.replaceAll('\n', ' '));
      await process.stdin.flush();
      final outDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final HelperEvent parsed;
            try {
              parsed = parseTunnelLine(line);
            } on FormatException {
              log('Invalid helper event');
              return;
            }
            switch (parsed) {
              case HelperReady():
                started = true;
                if (!ready.isCompleted) ready.complete();
              case HelperError(:final code) when !ready.isCompleted:
                ready.completeError(StateError(code));
              case HelperNetworkRestored():
                restored = true;
              default:
            }
            event(parsed);
          })
          .asFuture<void>();
      final errDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(log)
          .asFuture<void>();
      _finished = () async {
        final code = await process.exitCode;
        await Future.wait([outDone, errDone]);
        if (!ready.isCompleted) {
          ready.completeError(
            StateError('Helper exited ($code) before startup'),
          );
        }
        log('Tunnel helper exited ($code)');
        event(HelperTerminated(
          exitCode: code,
          needsCleanup: helperNeedsCleanup(started: started, restored: restored, exitCode: code),
        ));
        event(const HelperStatus(TunnelStatus.disconnected));
        if (identical(_process, process)) _process = null;
      }();
      await ready.future.timeout(startTimeout);
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln('stop');
      await process.stdin.flush();
    } catch (_) {}
    try {
      await _finished!.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      Process.killPid(process.pid, ProcessSignal.sigterm);
      try {
        await _finished!.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw StateError('Helper did not stop; privileged cleanup required');
      }
    }
  }
}
