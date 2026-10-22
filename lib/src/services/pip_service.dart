import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Picture-in-picture on Android, only while a video plays (issue #45,
/// fix 11). Leaving the app used to always shrink it into the little window,
/// whatever was on screen; now Dart tells Android when it may.
class PipService {
  PipService._();

  static final PipService instance = PipService._();

  static const MethodChannel _channel =
      MethodChannel('com.torrentspire.ai/pip');

  /// True while Android shows the app in the little window.
  final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  bool _wired = false;
  bool? _lastAllowed;
  int _lastWidth = 0;
  int _lastHeight = 0;

  static bool get platformSupported => !kIsWeb && Platform.isAndroid;

  /// The little window may open for a video that is playing, with the
  /// setting on. Not for songs, and not for a paused video.
  static bool allowedFor({
    required bool enabled,
    required bool isVideo,
    required bool isPlaying,
  }) =>
      enabled && isVideo && isPlaying;

  void _wire() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        inPip.value = call.arguments == true;
      }
      return null;
    });
  }

  /// Tells Android whether leaving the app may open the little window, and
  /// its shape. Calls only when something changed.
  Future<void> update({
    required bool allowed,
    int width = 16,
    int height = 9,
  }) async {
    if (!platformSupported) return;
    _wire();
    if (allowed == _lastAllowed &&
        width == _lastWidth &&
        height == _lastHeight) {
      return;
    }
    _lastAllowed = allowed;
    _lastWidth = width;
    _lastHeight = height;
    try {
      await _channel.invokeMethod<bool>('setPipAllowed', {
        'allowed': allowed,
        'width': width,
        'height': height,
      });
    } catch (e) {
      debugPrint('PiP: setPipAllowed failed: $e');
    }
  }
}
