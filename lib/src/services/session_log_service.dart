import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight startup/shutdown breadcrumb logger.
///
/// Records timestamped marks through the app's startup sequence (and any
/// interesting later events) in memory, then writes them to a
/// `session_log_<timestamp>.log` file in the app's documents directory when
/// the session ends - a normal window close, or an error path. This exists
/// so slow-start reports on low-end hardware come with real numbers
/// (which phase ate the time) instead of guesses.
///
/// Nothing is written to disk during startup itself, so the logger never
/// distorts the startup time it is measuring.
class SessionLogService {
  SessionLogService._();
  static final SessionLogService instance = SessionLogService._();

  final Stopwatch _uptime = Stopwatch();
  final List<String> _entries = [];
  final Set<String> _onceKeys = {};
  String? _sessionTag;
  bool _started = false;

  /// Starts the clock. Call exactly once, as early in `main()` as possible.
  void start() {
    if (_started) return;
    _started = true;
    final now = DateTime.now();
    _sessionTag = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    _uptime.start();
    mark('session_start');
  }

  /// Records a breadcrumb with the elapsed time since [start].
  void mark(String label) {
    if (!_started) return;
    final entry = '${_uptime.elapsedMilliseconds.toString().padLeft(6)}ms  $label';
    _entries.add(entry);
    if (kDebugMode) debugPrint('[PERF] $entry');
  }

  /// Like [mark], but only records the first call with a given [key]
  /// (useful for marks that sit in build paths).
  void markOnce(String key, String label) {
    if (!_started) return;
    if (!_onceKeys.add(key)) return;
    mark(label);
  }

  /// Writes all breadcrumbs to disk. Safe to call more than once (each
  /// flush appends). Returns the log file path, or null if unavailable.
  Future<String?> flush(String reason) async {
    if (!_started) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
          '${dir.path}${_separator}session_log_$_sessionTag.log');
      final sb = StringBuffer()
        ..writeln('=== flush: $reason ===')
        ..writeln('total: ${_uptime.elapsedMilliseconds}ms')
        ..writeAll(_entries, '\n')
        ..writeln();
      await file.writeAsString(sb.toString(),
          mode: FileMode.append, flush: true);
      return file.path;
    } catch (e) {
      if (kDebugMode) debugPrint('[PERF] flush failed: $e');
      return null;
    }
  }

  static String get _separator => Platform.pathSeparator;
}
