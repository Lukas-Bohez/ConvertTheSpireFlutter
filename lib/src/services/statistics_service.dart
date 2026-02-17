import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_stats.dart';

/// Persists and exposes download statistics.
class StatisticsService {
  static const _key = 'download_stats';

  DownloadStats _stats = DownloadStats();
  DownloadStats get stats => _stats;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        _stats = DownloadStats.fromJson(jsonDecode(raw));
      } catch (_) {
        _stats = DownloadStats();
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_stats.toJson()));
  }

  Future<void> recordDownload({
    required bool success,
    required String artist,
    required String source,
    required String format,
  }) async {
    _stats.recordDownload(
      success: success,
      artist: artist,
      source: source,
      format: format,
    );
    await _save();
  }

  Future<void> reset() async {
    _stats = DownloadStats();
    await _save();
  }
}
