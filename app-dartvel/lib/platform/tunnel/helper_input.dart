// SPDX-License-Identifier: GPL-3.0
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// The largest profile the privileged helper accepts on stdin (bytes,
/// excluding the newline). A real profile is a few KiB.
const int kMaxHelperProfileBytes = 4 * 1024 * 1024;

/// Why the helper could not read its profile. [code] is a fixed string that is
/// safe to print: it never contains any part of the input.
class HelperInputException implements Exception {
  final String code;
  const HelperInputException(this.code);
  @override
  String toString() => code;
}

/// Reads the helper's stdin: the first line is the profile (a JSON object),
/// every later line is a command ("stop"). The helper takes no path argument,
/// so it cannot be pointed at a file, and the profile (which holds the
/// WireGuard private key) never touches disk.
class HelperInput {
  HelperInput(Stream<List<int>> source, {this.maxProfileBytes = kMaxHelperProfileBytes}) {
    _subscription = source.listen(_onData, onError: (_) => _fail('profile_unreadable'), onDone: _onDone);
  }

  final int maxProfileBytes;
  late final StreamSubscription<List<int>> _subscription;
  final _profile = Completer<String>();
  // Cancelling the commands also releases stdin; otherwise the open stdin
  // subscription keeps the helper alive after it has stopped.
  late final _commands = StreamController<String>(onCancel: () => _subscription.cancel());
  final _head = BytesBuilder(copy: false);
  final _tail = BytesBuilder(copy: false);
  bool _profileDone = false;

  /// The profile text. Completes with a [HelperInputException] when stdin
  /// ends without a profile line, the line is too long, or it is not a JSON
  /// object.
  Future<String> get profile => _profile.future;

  /// Command lines after the profile; closes when stdin closes.
  Stream<String> get commands => _commands.stream;

  void _fail(String code) {
    if (!_profile.isCompleted) _profile.completeError(HelperInputException(code));
  }

  void _onData(List<int> chunk) {
    if (_profileDone) {
      _commandBytes(chunk);
      return;
    }
    final newline = chunk.indexOf(0x0a);
    final take = newline < 0 ? chunk.length : newline;
    if (_head.length + take > maxProfileBytes) {
      _fail('profile_too_large');
      _profileDone = true;
      _subscription.cancel();
      _commands.close();
      return;
    }
    _head.add(chunk.sublist(0, take));
    if (newline < 0) return;
    _profileDone = true;
    final bytes = _head.takeBytes();
    String text;
    try {
      text = utf8.decode(bytes);
      // Shape only; the caller decodes it again. Errors carry no content.
      if (jsonDecode(text) is! Map) throw const FormatException();
    } on FormatException {
      _fail('profile_invalid');
      _subscription.cancel();
      _commands.close();
      return;
    }
    _profile.complete(text);
    _commandBytes(chunk.sublist(newline + 1));
  }

  void _commandBytes(List<int> chunk) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0a) continue;
      _tail.add(chunk.sublist(start, i));
      _emitCommand();
      start = i + 1;
    }
    if (start < chunk.length) {
      _tail.add(chunk.sublist(start));
      // Commands are short. Anything longer is not one: drop it.
      if (_tail.length > 4096) _tail.clear();
    }
  }

  void _emitCommand() {
    final line = utf8.decode(_tail.takeBytes(), allowMalformed: true);
    if (!_commands.isClosed) _commands.add(line);
  }

  void _onDone() {
    _fail('profile_missing');
    if (!_commands.isClosed) _commands.close();
  }
}
