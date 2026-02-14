import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/app_settings.dart';
import 'platform_dirs.dart';

class SettingsStore {
  static const String _fileName = 'config.json';

  /// In-memory cache used on web or when file I/O is unavailable.
  String? _webSettingsJson;

  /// Whether path_provider is known to be broken on this device.
  bool _pathProviderBroken = false;

  Future<String> resolveDefaultDownloadDir() async {
    if (kIsWeb) return '/downloads';

    if (Platform.isAndroid) {
      // Try app-specific external storage (no permissions required)
      final extDir = await PlatformDirs.getExternalDir();
      if (extDir != null) {
        final dlDir = Directory('${extDir.path}${Platform.pathSeparator}downloads');
        await dlDir.create(recursive: true);
        return dlDir.path;
      }

      // Try internal files directory
      final filesDir = await PlatformDirs.getFilesDir();
      if (filesDir != null) {
        final dlDir = Directory('${filesDir.path}${Platform.pathSeparator}downloads');
        await dlDir.create(recursive: true);
        return dlDir.path;
      }

      // Native channel failed — return empty string;
      // the user will need to configure a download directory manually.
      _pathProviderBroken = true;
      return '';
    }

    // Desktop / iOS
    final downloadsDir = await PlatformDirs.getDownloadsDir();
    if (downloadsDir != null) {
      return downloadsDir.path;
    }
    final docs = await PlatformDirs.getFilesDir();
    if (docs != null) {
      return '${docs.path}${Platform.pathSeparator}downloads';
    }
    return '';
  }

  Future<File?> _settingsFile() async {
    if (_pathProviderBroken) return null;

    final supportDir = await PlatformDirs.getAppSupportDir();
    if (supportDir != null) {
      await supportDir.create(recursive: true);
      return File('${supportDir.path}${Platform.pathSeparator}$_fileName');
    }

    final filesDir = await PlatformDirs.getFilesDir();
    if (filesDir != null) {
      return File('${filesDir.path}${Platform.pathSeparator}$_fileName');
    }

    _pathProviderBroken = true;
    return null;
  }

  Future<AppSettings> load() async {
    final fallbackDir = await resolveDefaultDownloadDir();

    if (kIsWeb) {
      if (_webSettingsJson != null) {
        try {
          final json = jsonDecode(_webSettingsJson!) as Map<String, dynamic>;
          return AppSettings.fromJson(json, fallbackDownloadDir: fallbackDir);
        } catch (_) {}
      }
      return AppSettings.defaults(downloadDir: fallbackDir);
    }

    final file = await _settingsFile();
    if (file == null || !await file.exists()) {
      return AppSettings.defaults(downloadDir: fallbackDir);
    }
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(json, fallbackDownloadDir: fallbackDir);
    } catch (_) {
      return AppSettings.defaults(downloadDir: fallbackDir);
    }
  }

  Future<void> save(AppSettings settings) async {
    final json = jsonEncode(settings.toJson());
    if (kIsWeb) {
      _webSettingsJson = json;
      return;
    }
    try {
      final file = await _settingsFile();
      if (file != null) {
        await file.writeAsString(json);
      } else {
        // Can't persist — keep in memory
        _webSettingsJson = json;
      }
    } catch (_) {
      _webSettingsJson = json;
    }
  }
}
