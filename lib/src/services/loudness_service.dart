import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'ffmpeg_service.dart';

/// Measures how loud a file really is (whole-file mean + peak volume via
/// FFmpeg `volumedetect`) and turns that into a gain that pulls every track
/// towards one target loudness, so a quiet track and a loud one sound equally
/// loud. Results are cached so each file is only analysed once.
class LoudnessService {
  LoudnessService(this._prefs);

  final SharedPreferences _prefs;
  final FfmpegService _ffmpeg = FfmpegService();

  static const _cacheKey = 'player_loudness_cache_v1';

  /// Target mean volume (dBFS) for every track.
  static const double targetMeanDb = -20.0;

  /// Never boost so far that the loudest sample would exceed this (dBFS).
  static const double peakCeilingDb = -1.0;

  static const double maxBoostDb = 9.0;
  static const double maxCutDb = -15.0;

  final Map<String, double> _cache = {};
  bool _loaded = false;
  Future<void> _queue = Future.value();

  void _load() {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = _prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is num) _cache[k.toString()] = v.toDouble();
        });
      }
    } catch (e) {
      debugPrint('LoudnessService: cache load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      // Keep the cache bounded on low-end devices.
      while (_cache.length > 4000) {
        _cache.remove(_cache.keys.first);
      }
      await _prefs.setString(_cacheKey, jsonEncode(_cache));
    } catch (_) {}
  }

  String _key(String path, File file) {
    int len = 0;
    try {
      len = file.lengthSync();
    } catch (_) {}
    return '$path|$len';
  }

  /// Cached gain in dB for [localPath], or null when it has not been measured.
  double? cachedGainDb(String localPath) {
    _load();
    if (kIsWeb) return null;
    return _cache[_key(localPath, File(localPath))];
  }

  /// Measures [localPath] (serialised: one analysis at a time so we never
  /// starve a low-end device) and returns the gain in dB, or null on failure.
  Future<double?> gainDbFor(String localPath) {
    if (kIsWeb || localPath.startsWith('http')) return Future.value(null);
    final result = _queue.then<double?>((_) => _measure(localPath));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<double?> _measure(String localPath) async {
    _load();
    final file = File(localPath);
    if (!file.existsSync()) return null;
    final key = _key(localPath, file);
    final hit = _cache[key];
    if (hit != null) return hit;

    try {
      final output = await _runVolumeDetect(localPath);
      final mean = _parse(output, 'mean_volume');
      final max = _parse(output, 'max_volume');
      if (mean == null || mean.isNaN || mean < -90) return null;

      var gain = targetMeanDb - mean;
      if (max != null && gain > 0) {
        final headroom = peakCeilingDb - max;
        if (headroom < gain) gain = headroom < 0 ? 0 : headroom;
      }
      gain = gain.clamp(maxCutDb, maxBoostDb).toDouble();
      _cache[key] = gain;
      await _save();
      return gain;
    } catch (e) {
      debugPrint('LoudnessService: analysis failed for $localPath: $e');
      return null;
    }
  }

  double? _parse(String output, String field) {
    final m = RegExp('$field:\\s*(-?[0-9.]+|-inf)\\s*dB').firstMatch(output);
    if (m == null) return null;
    final v = m.group(1)!;
    if (v == '-inf') return -91.0;
    return double.tryParse(v);
  }

  Future<String> _runVolumeDetect(String path) async {
    final args = <String>[
      '-hide_banner',
      '-nostats',
      '-i',
      path,
      '-vn',
      '-sn',
      '-dn',
      '-af',
      'volumedetect',
      '-f',
      'null',
      '-',
    ];
    if (Platform.isAndroid || Platform.isIOS) {
      final session = await FFmpegKit.executeWithArguments(args)
          .timeout(const Duration(minutes: 3));
      return (await session.getOutput()) ?? '';
    }
    final exe = await _ffmpeg.resolveAvailablePath(null);
    if (exe == null) return '';
    final result =
        await Process.run(exe, args).timeout(const Duration(minutes: 3));
    return '${result.stderr}\n${result.stdout}';
  }
}
