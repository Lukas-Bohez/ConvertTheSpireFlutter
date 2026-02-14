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
    final directory = await getDownloadsDirectory();
    if (directory != null) {
      return directory.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}downloads';
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
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
