import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Appends uncaught errors to `startup_errors.log` without letting it grow
/// without end.
///
/// An app left running with an error every few seconds (a torrent seeding for
/// an hour) wrote every one, with its stack trace, and flushed the file each
/// time. Now the same error is written in full [fullRepeats] times, then
/// only on its 10th, 100th, 1000th... time with its count, and at [maxBytes]
/// the file moves to `startup_errors.old.log`, replacing the one before.
class ErrorLog {
  ErrorLog(this.file, {this.maxBytes = 1024 * 1024, this.fullRepeats = 3});

  final File? file;
  final int maxBytes;
  final int fullRepeats;

  final Map<String, int> _seen = {};
  Future<void> _writes = Future.value();

  void record(String label, Object error, StackTrace stack) {
    final message = '$error';
    final newline = message.indexOf('\n');
    final key =
        '$label ${error.runtimeType} ${newline == -1 ? message : message.substring(0, newline)}';
    // Messages that differ every time (addresses, ports) must not fill it.
    if (_seen.length > 500) _seen.clear();
    final count = (_seen[key] ?? 0) + 1;
    _seen[key] = count;

    final timestamp = DateTime.now().toIso8601String();
    final String entry;
    if (count <= fullRepeats) {
      entry = '[$timestamp] $label:\n$error\n$stack\n\n';
      debugPrint(entry);
    } else if (_isPowerOfTen(count)) {
      entry = '[$timestamp] $label, $count times this session:\n$error\n\n';
    } else {
      return;
    }
    final target = file;
    if (target == null) return;
    _writes = _writes.then((_) => _append(target, entry));
  }

  /// Written writes, for tests.
  Future<void> get idle => _writes;

  Future<void> _append(File target, String entry) async {
    try {
      if (await target.exists() && await target.length() > maxBytes) {
        final old =
            File(target.path.replaceFirst(RegExp(r'\.log$'), '.old.log'));
        if (await old.exists()) await old.delete();
        await target.rename(old.path);
      }
      await target.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('Failed to write error log entry: $e');
    }
  }

  static bool _isPowerOfTen(int n) {
    while (n >= 10 && n % 10 == 0) {
      n ~/= 10;
    }
    return n == 1;
  }
}
