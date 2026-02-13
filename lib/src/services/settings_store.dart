import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

class SettingsStore {
  static const String _fileName = 'config.json';

  Future<String> resolveDefaultDownloadDir() async {
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
    final file = await _settingsFile();
    final json = jsonEncode(settings.toJson());
    await file.writeAsString(json);
  }
}
