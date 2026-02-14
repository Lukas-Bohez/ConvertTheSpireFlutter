import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

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
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dlDir = Directory('${extDir.path}${Platform.pathSeparator}downloads');
          await dlDir.create(recursive: true);
          return dlDir.path;
        }
      } catch (_) {}

      // Try documents directory
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dlDir = Directory('${docs.path}${Platform.pathSeparator}downloads');
        await dlDir.create(recursive: true);
        return dlDir.path;
      } catch (_) {}

      // path_provider is completely broken — mark it and return empty string;
      // the user will need to configure a download directory manually.
      _pathProviderBroken = true;
      return '';
    }

    // Desktop / iOS
    try {
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.path;
      }
    } catch (_) {}
    try {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}${Platform.pathSeparator}downloads';
    } catch (_) {}
    return '';
  }

  Future<File?> _settingsFile() async {
    if (_pathProviderBroken) return null;

    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {}

    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {}

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
