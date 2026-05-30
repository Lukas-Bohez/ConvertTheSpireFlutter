import 'dart:async';
import 'dart:io';

import 'yt_dlp_updater.dart';

/// Controls periodic checking and manual triggering of the yt-dlp updater.
class YtDlpUpdateController {
  static Timer? _timer;
  static final Duration _defaultInterval = const Duration(hours: 24);

  /// Start the periodic checker. If already running, this is a no-op.
  ///
  /// [interval] defaults to 24 hours. For development you can pass a shorter
  /// duration, but avoid aggressive polling in production.
  static void start({Duration? interval}) {
    if (_timer != null) return;
    final dur = interval ?? _defaultInterval;
    _timer = Timer.periodic(dur, (_) async {
      try {
        await YtDlpUpdater.updateFromGithubLatest();
      } catch (e) {
        // swallow - it's non-critical
        stdout.writeln('yt-dlp controller: periodic check failed: $e');
      }
    });
    // Run one immediate check in background (don't await here)
    Future.microtask(() async {
      try {
        await YtDlpUpdater.updateFromGithubLatest();
      } catch (e) {
        stdout.writeln('yt-dlp controller: initial check failed: $e');
      }
    });
  }

  /// Stop the periodic checker.
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Trigger an immediate manual update. Returns true on success.
  static Future<bool> triggerOnce() async {
    try {
      return await YtDlpUpdater.updateFromGithubLatest();
    } catch (e) {
      stdout.writeln('yt-dlp controller: manual trigger failed: $e');
      return false;
    }
  }
}
