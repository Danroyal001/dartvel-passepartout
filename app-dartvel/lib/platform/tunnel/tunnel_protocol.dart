// SPDX-License-Identifier: GPL-3.0
// The privileged helper and the app talk over stdio: one JSON object per
// line. This file is the only place that line format is read or written; the
// rest of the app sees the typed events below.
import 'dart:convert';

import '../../domain/tunnel_status.dart';

/// A line the tunnel helper writes on stdout.
sealed class HelperEvent {
  const HelperEvent();

  /// The line the helper writes for this event.
  String encode() => jsonEncode(_fields);
  Map<String, Object> get _fields;
}

final class HelperStatus extends HelperEvent {
  final TunnelStatus status;
  const HelperStatus(this.status);
  @override
  Map<String, Object> get _fields => {'type': 'status', 'status': status.name};
  @override
  bool operator ==(Object other) => other is HelperStatus && other.status == status;
  @override
  int get hashCode => status.hashCode;
}

final class HelperData extends HelperEvent {
  final int received;
  final int sent;
  const HelperData({required this.received, required this.sent});
  @override
  Map<String, Object> get _fields => {'type': 'data', 'received': received, 'sent': sent};
  @override
  bool operator ==(Object other) => other is HelperData && other.received == received && other.sent == sent;
  @override
  int get hashCode => Object.hash(received, sent);
}

/// A fixed error [code]. [detail], when present, is the type of the failure,
/// never its text: an exception message can quote the profile or a file the
/// helper (running as root) read.
final class HelperError extends HelperEvent {
  final String code;
  final String? detail;
  const HelperError(this.code, {this.detail});
  HelperError.fromFailure(this.code, Object error) : detail = error.runtimeType.toString();
  @override
  Map<String, Object> get _fields => {'type': 'error', 'code': code, 'detail': ?detail};
  @override
  bool operator ==(Object other) => other is HelperError && other.code == code && other.detail == detail;
  @override
  int get hashCode => Object.hash(code, detail);
}

final class HelperLog extends HelperEvent {
  final int level;
  final String message;
  const HelperLog({required this.level, required this.message});
  @override
  Map<String, Object> get _fields => {'type': 'log', 'level': level, 'message': message};
  @override
  bool operator ==(Object other) => other is HelperLog && other.level == level && other.message == message;
  @override
  int get hashCode => Object.hash(level, message);
}

/// The helper read its profile, set up the network and started the engine.
final class HelperReady extends HelperEvent {
  final int pid;
  const HelperReady(this.pid);
  @override
  Map<String, Object> get _fields => {'type': 'ready', 'pid': pid};
  @override
  bool operator ==(Object other) => other is HelperReady && other.pid == pid;
  @override
  int get hashCode => pid.hashCode;
}

/// The engine stopped with [code].
final class HelperExit extends HelperEvent {
  final int code;
  const HelperExit(this.code);
  @override
  Map<String, Object> get _fields => {'type': 'exit', 'code': code};
  @override
  bool operator ==(Object other) => other is HelperExit && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

/// The helper undid its routes, DNS and kill switch.
final class HelperNetworkRestored extends HelperEvent {
  const HelperNetworkRestored();
  @override
  Map<String, Object> get _fields => {'type': 'network', 'state': 'restored'};
  @override
  bool operator ==(Object other) => other is HelperNetworkRestored;
  @override
  int get hashCode => 0;
}

/// Not written by the helper: [TunnelProcess] adds it when the helper process
/// has ended. [needsCleanup] says the helper may have left its network
/// changes (the kill switch fails closed) and `--cleanup` should run.
final class HelperTerminated extends HelperEvent {
  final int exitCode;
  final bool needsCleanup;
  const HelperTerminated({required this.exitCode, required this.needsCleanup});
  @override
  Map<String, Object> get _fields => {'type': 'terminated', 'code': exitCode};
  @override
  bool operator ==(Object other) =>
      other is HelperTerminated && other.exitCode == exitCode && other.needsCleanup == needsCleanup;
  @override
  int get hashCode => Object.hash(exitCode, needsCleanup);
}

/// Whether a helper that ended may have left routes, DNS or the kill switch
/// behind. One that never [started] changed nothing (pkexec refused, or the
/// profile was rejected); one that reported [restored] undid its changes; a
/// clean exit (0) always restores first.
bool helperNeedsCleanup({required bool started, required bool restored, required int exitCode}) =>
    started && !restored && exitCode != 0;

/// Reads one helper line. Throws [FormatException] for anything else.
HelperEvent parseTunnelLine(String line) {
  final value = jsonDecode(line);
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected event object');
  }
  int count(String key) {
    final number = value[key];
    if (number is! int || number < 0) throw const FormatException('Invalid count');
    return number;
  }

  switch (value['type']) {
    case 'status':
      final status = TunnelStatus.values.asNameMap()[value['status']];
      if (status == null) throw const FormatException('Unknown status');
      return HelperStatus(status);
    case 'data':
      return HelperData(received: count('received'), sent: count('sent'));
    case 'error':
      final code = value['code'];
      final detail = value['detail'];
      if (code is! String || (detail != null && detail is! String)) {
        throw const FormatException('Invalid error');
      }
      return HelperError(code, detail: detail as String?);
    case 'log':
      final message = value['message'];
      final level = value['level'] ?? 0;
      if (message is! String || level is! int) throw const FormatException('Invalid log');
      return HelperLog(level: level, message: message);
    case 'ready':
      final pid = value['pid'];
      if (pid is! int || pid <= 0) throw const FormatException('Invalid PID');
      return HelperReady(pid);
    case 'exit':
      final code = value['code'];
      if (code is! int) throw const FormatException('Invalid exit');
      return HelperExit(code);
    case 'network':
      if (value['state'] != 'restored') throw const FormatException('Unknown network state');
      return const HelperNetworkRestored();
    default:
      throw const FormatException('Unknown event');
  }
}

/// Holds the engine's "connected" until the helper has configured the tun
/// device (addresses, routes, DNS): until then nothing is routed through the
/// tunnel, and the app must not say it is connected. Every other status
/// passes straight through.
class HelperStatusGate {
  HelperStatusGate(this._emit);
  final void Function(HelperEvent) _emit;
  bool _deviceReady = false;
  bool _held = false;

  void engineStatus(TunnelStatus status) {
    if (status == TunnelStatus.connected && !_deviceReady) {
      _held = true;
      return;
    }
    _held = false;
    // A reconnection opens a new tun device, which needs configuring again.
    if (status == TunnelStatus.connecting) _deviceReady = false;
    _emit(HelperStatus(status));
  }

  /// The current tun device is configured.
  void deviceConfigured() {
    _deviceReady = true;
    if (_held) {
      _held = false;
      _emit(const HelperStatus(TunnelStatus.connected));
    }
  }
}
