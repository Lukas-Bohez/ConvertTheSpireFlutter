import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Bridge to the Android foreground service that keeps downloads alive while
/// the screen is off.
///
/// Every method is a no-op off Android, and failures are reported rather than
/// swallowed: a missing handler on the native side is exactly how this broke
/// silently before (issue #7).
class ForegroundService {
  static const MethodChannel _channel =
      MethodChannel('convert_the_spire/foreground');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Called when the user taps Stop on the download notification.
  static void Function()? onPauseRequested;

  static bool _handlerAttached = false;

  /// Starts listening for callbacks from the notification actions.
  static void attach() {
    if (!isSupported || _handlerAttached) return;
    _handlerAttached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pauseDownloads') {
        onPauseRequested?.call();
      }
      return null;
    });
  }

  /// Starts the foreground service. Returns true when Android accepted it.
  static Future<bool> start({
    required String title,
    required String text,
    required String channelName,
    int progress = -1,
  }) =>
      _invoke('startForegroundService', {
        'title': title,
        'text': text,
        'channelName': channelName,
        'progress': progress,
      });

  /// Updates the ongoing notification in place.
  static Future<bool> update({
    required String title,
    required String text,
    required String channelName,
    int progress = -1,
  }) =>
      _invoke('updateForegroundService', {
        'title': title,
        'text': text,
        'channelName': channelName,
        'progress': progress,
      });

  /// Stops the foreground service and drops its wake locks.
  static Future<bool> stop() => _invoke('stopForegroundService', null);

  /// Whether the app is exempt from battery optimisation. Devices that are not
  /// exempt can still kill long downloads despite the foreground service.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isSupported) return true;
    try {
      final result =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return result ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// The device's own name, used as a default display name for Watch Together.
  static Future<String?> deviceName() async {
    if (!isSupported) return null;
    try {
      final name = await _channel.invokeMethod<String>('deviceName');
      final trimmed = name?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> _invoke(String method, Map<String, Object?>? args) async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>(method, args);
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
