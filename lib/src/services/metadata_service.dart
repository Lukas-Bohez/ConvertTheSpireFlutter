import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track_metadata.dart';

// ─── MusicBrainz metadata fetcher ────────────────────────────────────────────

class MusicBrainzService {
  static const _baseUrl = 'https://musicbrainz.org/ws/2';
  static const _userAgent = 'ConvertTheSpireReborn/1.0 (https://github.com)';
  // Simple in-memory cache to avoid hammering MusicBrainz for repeated queries
  final Map<String, _CacheEntry<TrackMetadata?>> _mbCache = {};
  final Duration _mbCacheTtl = const Duration(hours: 6);
  // Rate limiter: allow 1 request per second across the service
  static const Duration _mbRateInterval = Duration(seconds: 1);
  DateTime _mbNextAllowed = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _mbQueue = Future.value();

  /// Search for metadata by artist + title.
  Future<TrackMetadata?> searchTrack(String artist, String title) async {
    try {
      final key = '$artist|$title'.toLowerCase();
      final now = DateTime.now();
      final cached = _mbCache[key];
      if (cached != null && now.difference(cached.storedAt) < _mbCacheTtl) {
        return cached.value;
      }

      final query = Uri.encodeComponent('artist:"$artist" AND recording:"$title"');
      final url = '$_baseUrl/recording/?query=$query&fmt=json&limit=5';

      final response = await _withMbRateLimit(() {
        return http
            .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 15));
      });
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final recordings = data['recordings'] as List? ?? [];
      if (recordings.isEmpty) return null;

      final best = recordings.first;
      final releaseTitle = (best['releases'] as List?)?.firstOrNull;

      final result = TrackMetadata(
        artist: (best['artist-credit'] as List?)?.firstOrNull?['name'] ?? artist,
        title: best['title'] ?? title,
        album: releaseTitle?['title'] ?? 'Singles',
        year: _extractYear(best['first-release-date']),
        genre: await _fetchGenre(best['id']),
      );

      _mbCache[key] = _CacheEntry(result, DateTime.now());
      return result;
    } catch (e) {
      debugPrint('MusicBrainz searchTrack failed: $e');
      return null;
    }
  }

  // Serialize requests to MusicBrainz and ensure at most one request per
  // `_mbRateInterval`. This uses a simple Future-chain queue so concurrent
  // callers are spaced correctly without external packages.
  Future<T> _withMbRateLimit<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _mbQueue = _mbQueue.then((_) async {
      final now = DateTime.now();
      if (now.isBefore(_mbNextAllowed)) {
        await Future.delayed(_mbNextAllowed.difference(now));
      }
      _mbNextAllowed = DateTime.now().add(_mbRateInterval);
      try {
        final res = await fn();
        completer.complete(res);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  int? _extractYear(String? date) {
    if (date == null || date.isEmpty) return null;
    return int.tryParse(date.split('-').first);
  }

  Future<String?> _fetchGenre(String recordingId) async {
    final key = 'genre|$recordingId';
    final now = DateTime.now();
    final cached = _mbCache[key];
    if (cached != null && now.difference(cached.storedAt) < _mbCacheTtl) {
      return cached.value as String?;
    }
    final url = '$_baseUrl/recording/$recordingId?inc=genres&fmt=json';
    try {
      final response = await _withMbRateLimit(() {
        return http
            .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 10));
      });
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final genres = data['genres'] as List?;
      if (genres == null || genres.isEmpty) return null;
      final g = genres.first['name'];
      _mbCache[key] = _CacheEntry(g, DateTime.now());
      return g;
    } catch (_) {
      return null;
    }
  }
}

// ─── Album art downloader ────────────────────────────────────────────────────

class AlbumArtService {
  static const _artTtl = Duration(days: 14);

  Future<String?> downloadAlbumArt(String thumbnailUrl, String trackId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final keySource = thumbnailUrl.isNotEmpty ? thumbnailUrl : trackId;
      final digest = md5.convert(utf8.encode(keySource));
      final fname = 'album_art_${digest.toString()}.jpg';
      final artPath = '${tempDir.path}${Platform.pathSeparator}$fname';
      final file = File(artPath);

      if (await file.exists()) {
        try {
          final stat = await file.stat();
          if (DateTime.now().difference(stat.modified) < _artTtl) {
            return artPath; // reuse existing recent art
          }
        } catch (_) {}
      }

      final response = await http.get(Uri.parse(thumbnailUrl))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      await file.writeAsBytes(response.bodyBytes);
      return artPath;
    } catch (e) {
      debugPrint('AlbumArtService.downloadAlbumArt failed: $e');
      return null;
    }
  }

  /// Delete cached album art files older than [_artTtl]. Safe to call on startup.
  Future<void> pruneOldAlbumArt() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        try {
          if (f is File && f.path.contains('album_art_')) {
            final stat = await f.stat();
            if (DateTime.now().difference(stat.modified) > _artTtl) {
              try {
                await f.delete();
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}

// ─── LRClib lyrics fetcher ───────────────────────────────────────────────────

class LyricsService {
  static const _baseUrl = 'https://lrclib.net/api';
  // Cache lyrics per track to avoid repeated fetching and rate-limit API usage
  final Map<String, _CacheEntry<String?>> _lyricsCache = {};
  final Duration _lyricsCacheTtl = const Duration(hours: 24);
  // Rate limiter for lyrics API: 1 request per second
  static const Duration _lyricsRateInterval = Duration(seconds: 1);
  DateTime _lyricsNextAllowed = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _lyricsQueue = Future.value();

  /// Fetch lyrics (prefer synced/LRC, fallback to plain).
  Future<String?> fetchLyrics(String artist, String title, {int? durationSeconds}) async {
    final key = '$artist|$title'.toLowerCase();
    final now = DateTime.now();
    final cached = _lyricsCache[key];
    if (cached != null && now.difference(cached.storedAt) < _lyricsCacheTtl) {
      return cached.value;
    }

    final params = <String, String>{
      'artist_name': artist,
      'track_name': title,
      if (durationSeconds != null) 'duration': durationSeconds.toString(),
    };

    final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: params);
    try {
      final response = await _withLyricsRateLimit(() {
        return http.get(uri).timeout(const Duration(seconds: 10));
      });
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final synced = data['syncedLyrics'] as String?;
      final result = (synced != null && synced.isNotEmpty)
          ? synced
          : data['plainLyrics'] as String?;
      _lyricsCache[key] = _CacheEntry(result, DateTime.now());
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<T> _withLyricsRateLimit<T>(Future<T> Function() fn) {
    final completer = Completer<T>();
    _lyricsQueue = _lyricsQueue.then((_) async {
      final now = DateTime.now();
      if (now.isBefore(_lyricsNextAllowed)) {
        await Future.delayed(_lyricsNextAllowed.difference(now));
      }
      _lyricsNextAllowed = DateTime.now().add(_lyricsRateInterval);
      try {
        final res = await fn();
        completer.complete(res);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Save lyrics as a .lrc sidecar file next to the audio file.
  Future<void> saveLyricsFile(String lyrics, String audioFilePath) async {
    final lrcPath = audioFilePath.replaceAll(RegExp(r'\.\w+$'), '.lrc');
    final file = File(lrcPath);
    await file.writeAsString(lyrics);
  }
}

// Simple cache entry used by services above
class _CacheEntry<T> {
  final T? value;
  final DateTime storedAt;
  _CacheEntry(this.value, this.storedAt);
}
