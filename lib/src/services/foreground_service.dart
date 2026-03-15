import 'package:flutter/services.dart';

class ForegroundService {
  static const MethodChannel _channel = MethodChannel('convert_the_spire/foreground');

  /// Start the platform foreground service. Returns true on success.
  static Future<bool> start() async {
    try {
      final res = await _channel.invokeMethod('startForegroundService');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Stop the platform foreground service. Returns true on success.
  static Future<bool> stop() async {
    try {
      final res = await _channel.invokeMethod('stopForegroundService');
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
