import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'foreground_service.dart';

/// Keeps the Android foreground service in step with how much work is running.
///
/// Downloads, torrents and conversions all report into one place, because the
/// process only needs to be held up once. Before this existed the foreground
/// service was never started at all and downloads stopped whenever the phone
/// locked (issue #7).
///
/// Each kind of work reports under its own [report] `source`, so the download
/// queue going idle does not stop the service while a torrent is still running.
class DownloadKeepAlive {
  DownloadKeepAlive._()
      : _enabled = ForegroundService.isSupported,
        _start = _defaultStart,
        _update = _defaultUpdate,
        _stop = _defaultStop;

  /// Lets tests drive the state machine without an Android device.
  @visibleForTesting
  DownloadKeepAlive.forTest({
    required Future<void> Function(String text, int progress) start,
    required Future<void> Function(String text, int progress) update,
    required Future<void> Function() stop,
    this.stopDebounce = const Duration(milliseconds: 20),
    this.updateInterval = Duration.zero,
  })  : _enabled = true,
        _start = start,
        _update = update,
        _stop = stop;

  static final DownloadKeepAlive instance = DownloadKeepAlive._();

  /// The source used when a caller does not name one: the download queue.
  static const String downloadsSource = 'downloads';

  /// Torrents report under this source.
  static const String torrentsSource = 'torrents';

  final bool _enabled;
  final Future<void> Function(String text, int progress) _start;
  final Future<void> Function(String text, int progress) _update;
  final Future<void> Function() _stop;

  /// Stopping is debounced so a queue that briefly empties between two items
  /// does not tear the service down and immediately rebuild it.
  Duration stopDebounce = const Duration(seconds: 5);

  /// Android throttles notification updates; once a second is plenty.
  Duration updateInterval = const Duration(seconds: 1);

  /// Notification title. Set at startup from the build flavour's app name.
  String appName = 'Downloads';

  /// Notification channel name, shown in Android's notification settings.
  String channelName = 'Downloads';

  final Map<String, _Work> _sources = {};
  int _active = 0;
  bool _serviceRunning = false;
  Timer? _stopTimer;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastText = '';
  int _lastProgress = -1;

  bool get isServiceRunning => _serviceRunning;
  int get activeCount => _active;

  /// Reports how much work [source] currently has running.
  ///
  /// [text] and [progress] are shown in the notification; progress is a
  /// percentage, or -1 for indeterminate. When more than one source is busy
  /// their texts are joined and the progress bar goes indeterminate.
  void report({
    required int active,
    required String text,
    int progress = -1,
    String source = downloadsSource,
  }) {
    if (!_enabled) return;

    if (active > 0) {
      _sources[source] = _Work(active, text, progress);
    } else {
      _sources.remove(source);
    }

    final was = _active;
    _active = _sources.values.fold<int>(0, (sum, work) => sum + work.count);
    final busy = _sources.values.toList();
    final shownText = busy.length == 1
        ? busy.first.text
        : busy.map((work) => work.text).join(' · ');
    final shownProgress = busy.length == 1 ? busy.first.progress : -1;

    if (_active > 0 && was == 0) {
      _stopTimer?.cancel();
      _stopTimer = null;
      if (_serviceRunning) {
        // The debounce had not fired yet, so the service is still up.
        _maybeUpdate(shownText, shownProgress, force: true);
      } else {
        _beginService(shownText, shownProgress);
      }
      return;
    }
    if (_active == 0 && was > 0) {
      _scheduleStop();
      return;
    }
    if (_active > 0) {
      _maybeUpdate(shownText, shownProgress);
    }
  }

  /// Stops the service immediately, e.g. when the user pauses everything.
  Future<void> stopNow() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    _sources.clear();
    _active = 0;
    if (!_serviceRunning) return;
    _serviceRunning = false;
    await _stop();
  }

  void _beginService(String text, int progress) {
    _serviceRunning = true;
    _lastText = text;
    _lastProgress = progress;
    _lastUpdate = DateTime.now();
    unawaited(_start(text, progress));
  }

  void _scheduleStop() {
    _stopTimer?.cancel();
    _stopTimer = Timer(stopDebounce, () {
      _stopTimer = null;
      if (_active > 0) return;
      unawaited(stopNow());
    });
  }

  void _maybeUpdate(String text, int progress, {bool force = false}) {
    if (!_serviceRunning) {
      _beginService(text, progress);
      return;
    }
    if (!force && text == _lastText && progress == _lastProgress) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastUpdate) < updateInterval) return;

    _lastUpdate = now;
    _lastText = text;
    _lastProgress = progress;
    unawaited(_update(text, progress));
  }

  static Future<void> _defaultStart(String text, int progress) async {
    await ForegroundService.start(
      title: instance.appName,
      text: text,
      channelName: instance.channelName,
      progress: progress,
    );
  }

  static Future<void> _defaultUpdate(String text, int progress) async {
    await ForegroundService.update(
      title: instance.appName,
      text: text,
      channelName: instance.channelName,
      progress: progress,
    );
  }

  static Future<void> _defaultStop() => ForegroundService.stop();
}

class _Work {
  final int count;
  final String text;
  final int progress;

  const _Work(this.count, this.text, this.progress);
}
