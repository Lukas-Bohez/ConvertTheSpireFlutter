import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

class SettingsStore {
  static const String _fileName = 'config.json';

  /// In-memory cache used on web where file I/O is unavailable.
  String? _webSettingsJson;

  Future<String> resolveDefaultDownloadDir() async {
    if (kIsWeb) return '/downloads';

    // On Android, getDownloadsDirectory() and getExternalStorageDirectory() use
    // Pigeon channels that can fail if binding isn't fully ready or permissions
    // are missing. Wrap every call individually and always have a fallback.
    if (Platform.isAndroid) {
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dlDir = Directory('${extDir.path}${Platform.pathSeparator}downloads');
          await dlDir.create(recursive: true);
          return dlDir.path;
        }
      } catch (_) {}
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dlDir = Directory('${docs.path}${Platform.pathSeparator}downloads');
        await dlDir.create(recursive: true);
        return dlDir.path;
      } catch (_) {}
      // Last resort: use a known Android-safe path
      final fallback = Directory('/data/data/com.orokaconner.convertthespirereborn/files/downloads');
      await fallback.create(recursive: true);
      return fallback.path;
    }

    try {
      final directory = await getDownloadsDirectory();
      if (directory != null) {
        return directory.path;
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}downloads';
  }

  Future<File> _settingsFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    } catch (_) {
      // Fallback to documents directory if support directory fails
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}${Platform.pathSeparator}$_fileName');
    }
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
    if (!await file.exists()) {
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
    final file = await _settingsFile();
    await file.writeAsString(json);
  }
}
