import 'dart:async';
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
///
/// It stays small however long the app runs: the first [_keptFirst] marks
/// (the startup) and the last [_keptLast] are kept, a flush appends only
/// what is new, flushes on errors come at most every [_errorFlushInterval],
/// and a session's file stops growing at [_maxFileBytes]. It used to keep
/// every mark and write all of them again on every error, so an app left
/// running with an error every few seconds (a torrent seeding for an hour)
/// spent its time rewriting an ever longer log.
class SessionLogService {
  SessionLogService._();
  static final SessionLogService instance = SessionLogService._();

  static const _keptFirst = 150;
  static const _keptLast = 350;
  static const _maxFileBytes = 2 * 1024 * 1024;
  static const _keptSessionFiles = 10;
  static const _errorFlushInterval = Duration(seconds: 30);

  final Stopwatch _uptime = Stopwatch();
  final List<String> _first = [];
  final List<String> _last = [];
  int _dropped = 0;
  final Set<String> _onceKeys = {};
  String? _sessionTag;
  bool _started = false;

  /// Marks not written to the file yet.
  final List<String> _unwritten = [];
  int _unwrittenDropped = 0;
  int _writtenBytes = 0;
  Future<String?>? _writing;
  Timer? _errorFlush;

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
    final entry =
        '${_uptime.elapsedMilliseconds.toString().padLeft(6)}ms  $label';
    if (_first.length < _keptFirst) {
      _first.add(entry);
    } else {
      _last.add(entry);
      if (_last.length > _keptLast) {
        _last.removeAt(0);
        _dropped++;
      }
    }
    _unwritten.add(entry);
    if (_unwritten.length > _keptLast) {
      _unwritten.removeAt(0);
      _unwrittenDropped++;
    }
    if (kDebugMode) debugPrint('[PERF] $entry');
  }

  /// Like [mark], but only records the first call with a given [key]
  /// (useful for marks that sit in build paths).
  void markOnce(String key, String label) {
    if (!_started) return;
    if (!_onceKeys.add(key)) return;
    mark(label);
  }

  /// The most recent breadcrumbs, newest last.
  ///
  /// Used by the in-app bug report and the release error screen, so a report
  /// arrives with the run-up to the failure attached.
  List<String> recent({int limit = 50}) {
    final all = [
      ..._first,
      if (_dropped > 0) '... $_dropped earlier marks not kept ...',
      ..._last,
    ];
    if (all.length <= limit) return List.unmodifiable(all);
    return List.unmodifiable(all.sublist(all.length - limit));
  }

  /// Records an error that would otherwise be swallowed.
  ///
  /// `lib/` is full of empty `catch (_) {}` blocks; that is how the missing
  /// foreground-service channel went unnoticed (issue #7). New code funnels
  /// through here instead.
  void logSwallowed(Object error, StackTrace stack, String where) {
    mark('swallowed[$where]: $error');
    if (kDebugMode) {
      debugPrint('[SWALLOWED] $where: $error');
      debugPrint(stack.toString());
    }
  }

  /// Writes the marks after an error: soon, but at most once every
  /// [_errorFlushInterval], however many errors come in between.
  void flushSoon(String reason) {
    if (!_started || _errorFlush != null) return;
    _errorFlush = Timer(_errorFlushInterval, () {
      _errorFlush = null;
      unawaited(flush(reason));
    });
  }

  /// Appends the marks recorded since the last flush to this session's log
  /// file. Returns the log file path, or null if unavailable.
  Future<String?> flush(String reason) async {
    if (!_started) return null;
    while (_writing != null) {
      await _writing;
    }
    final writing = _write(reason);
    _writing = writing;
    try {
      return await writing;
    } finally {
      _writing = null;
    }
  }

  Future<String?> _write(String reason) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${_separator}session_log_$_sessionTag.log');
      if (_writtenBytes == 0) unawaited(_deleteOldSessionFiles(dir));
      final sb = StringBuffer()
        ..writeln('=== flush: $reason ===')
        ..writeln('total: ${_uptime.elapsedMilliseconds}ms');
      if (_unwrittenDropped > 0) {
        sb.writeln('... $_unwrittenDropped marks not kept ...');
      }
      sb
        ..writeAll(_unwritten, '\n')
        ..writeln();
      _unwritten.clear();
      _unwrittenDropped = 0;
      final text = sb.toString();
      if (_writtenBytes + text.length > _maxFileBytes) return file.path;
      _writtenBytes += text.length;
      await file.writeAsString(text, mode: FileMode.append, flush: true);
      return file.path;
    } catch (e) {
      if (kDebugMode) debugPrint('[PERF] flush failed: $e');
      return null;
    }
  }

  /// Keeps the newest [_keptSessionFiles] session logs; each session wrote
  /// one and nothing ever removed them.
  Future<void> _deleteOldSessionFiles(Directory dir) async {
    try {
      final logs = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            name.startsWith('session_log_') &&
            name.endsWith('.log')) {
          logs.add(entity);
        }
      }
      if (logs.length <= _keptSessionFiles) return;
      // The timestamp in the name sorts oldest first.
      logs.sort((a, b) => a.path.compareTo(b.path));
      for (final old in logs.take(logs.length - _keptSessionFiles)) {
        await old.delete();
      }
    } catch (_) {
      // Cleanup is best effort.
    }
  }

  static String get _separator => Platform.pathSeparator;
}
