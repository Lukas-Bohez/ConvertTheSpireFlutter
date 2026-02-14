import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as pp;

/// Platform-aware directory resolver.
///
/// On Android, uses a native MethodChannel to bypass path_provider's Pigeon
/// channels which are broken in release mode when ffmpeg_kit_flutter_new (or
/// other plugins with old AGP versions) is present.
///
/// On other platforms, delegates to path_provider.
class PlatformDirs {
  static const MethodChannel _channel = MethodChannel('convert_the_spire/saf');

  /// App-internal files directory (equivalent to getApplicationDocumentsDirectory on Android).
  static Future<Directory?> getFilesDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getFilesDir');
        if (path != null && path.isNotEmpty) {
          return Directory(path);
        }
      } catch (_) {}
      return null;
    }
    try {
      return await pp.getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  /// App-internal cache directory (equivalent to getTemporaryDirectory).
  static Future<Directory> getCacheDir() async {
    if (kIsWeb) return Directory.systemTemp;
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getCacheDir');
        if (path != null && path.isNotEmpty) {
          return Directory(path);
        }
      } catch (_) {}
      return Directory.systemTemp;
    }
    try {
      return await pp.getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// App-specific external storage (no permissions needed on Android).
  /// Equivalent to getExternalStorageDirectory.
  static Future<Directory?> getExternalDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getExternalFilesDir');
        if (path != null && path.isNotEmpty) {
          return Directory(path);
        }
      } catch (_) {}
      return null;
    }
    try {
      return await pp.getExternalStorageDirectory();
    } catch (_) {
      return null;
    }
  }

  /// Application support directory (for config files).
  /// On Android, uses filesDir. On desktop, uses getApplicationSupportDirectory.
  static Future<Directory?> getAppSupportDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      // On Android, filesDir IS the app support directory
      return getFilesDir();
    }
    try {
      return await pp.getApplicationSupportDirectory();
    } catch (_) {
      return await getFilesDir();
    }
  }

  /// Downloads directory (desktop only).
  static Future<Directory?> getDownloadsDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) return null;
    try {
      return await pp.getDownloadsDirectory();
    } catch (_) {
      return null;
    }
  }
}
