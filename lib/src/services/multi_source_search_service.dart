import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/search_result.dart';
import '../utils/safe_json.dart';
import 'yt_dlp_service.dart';

// --─ YouTube searcher --------------------------------------------------------

class YouTubeSearcher {
  final YoutubeExplode _yt;

  YouTubeSearcher({required YoutubeExplode yt}) : _yt = yt;

  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final results = await _yt.search.search(query);
    return results.take(limit).map((video) {
      return SearchResult(
        id: video.id.value,
        title: video.title,
        artist: video.author,
        duration: video.duration ?? Duration.zero,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        source: 'youtube',
      );
    }).toList();
  }

  Future<String> getAudioUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    // Prefer muxed stream (reliable), fall back to audio-only
    final stream = manifest.muxed.isNotEmpty
        ? manifest.muxed.withHighestBitrate()
        : manifest.audioOnly.withHighestBitrate();
    return stream.url.toString();
  }
}

// --─ SoundCloud searcher ----------------------------------------------------─

class SoundCloudSearcher {
  String? clientId; // Must be injected or extracted

  SoundCloudSearcher({this.clientId});

  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    if (clientId == null || clientId!.isEmpty) return [];

    final url = 'https://api-v2.soundcloud.com/search/tracks'
        '?q=${Uri.encodeComponent(query)}'
        '&client_id=$clientId'
        '&limit=$limit';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return [];

      final data = safeJsonDecode<Map<String, dynamic>>(response.body);
      if (data == null) return [];
      final collection = data['collection'] as List? ?? [];

      return collection.map<SearchResult>((track) {
        return SearchResult(
          id: track['id'].toString(),
          title: track['title'] ?? '',
          artist: track['user']?['username'] ?? '',
          duration:
              Duration(milliseconds: (track['duration'] as num?)?.toInt() ?? 0),
          thumbnailUrl: track['artwork_url'] ?? '',
          source: 'soundcloud',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

// --─ Multi-source aggregator ------------------------------------------------─

class MultiSourceSearchService {
  final YouTubeSearcher youtubeSearcher;
  final SoundCloudSearcher soundcloudSearcher;
  final BiliSearcher? biliSearcher;
  final RumbleSearcher? rumbleSearcher;
  final DailymotionSearcher? dailymotionSearcher;
  final OdyseeSearcher? odyseeSearcher;
  final Duration perSourceTimeout;
  final Duration globalTimeout;

  MultiSourceSearchService({
    required this.youtubeSearcher,
    required this.soundcloudSearcher,
    this.biliSearcher,
    this.rumbleSearcher,
    this.dailymotionSearcher,
    this.odyseeSearcher,
    this.perSourceTimeout = const Duration(seconds: 5),
    this.globalTimeout = const Duration(seconds: 10),
  });

  /// Search YouTube, SoundCloud, and optionally other platforms in parallel,
  /// merge and rank results.
  Future<List<SearchResult>> searchAll(String query,
      {int limitPerSource = 10}) async {
    final per = perSourceTimeout;
    final global = globalTimeout;

    // Build list of futures for each available searcher
    final futures = <Future<List<SearchResult>>>[];

    // Always search YouTube and SoundCloud
    futures.add(youtubeSearcher
        .search(query, limit: limitPerSource)
        .timeout(per, onTimeout: () => <SearchResult>[]));
    futures.add(_safeSoundCloudSearch(query, limit: limitPerSource)
        .timeout(per, onTimeout: () => <SearchResult>[]));

    // Add other platforms if available (desktop builds)
    if (biliSearcher != null) {
      futures.add(biliSearcher!
          .search(query, limit: limitPerSource)
          .timeout(per, onTimeout: () => <SearchResult>[]));
    }
    if (rumbleSearcher != null) {
      futures.add(rumbleSearcher!
          .search(query, limit: limitPerSource)
          .timeout(per, onTimeout: () => <SearchResult>[]));
    }
    if (dailymotionSearcher != null) {
      futures.add(dailymotionSearcher!
          .search(query, limit: limitPerSource)
          .timeout(per, onTimeout: () => <SearchResult>[]));
    }
    if (odyseeSearcher != null) {
      futures.add(odyseeSearcher!
          .search(query, limit: limitPerSource)
          .timeout(per, onTimeout: () => <SearchResult>[]));
    }

    // Run all searches in parallel
    final results = await Future.wait(futures)
        .timeout(global, onTimeout: () => List.filled(futures.length, <SearchResult>[]));

    final combined = results.expand((list) => list).toList();

    // Sort: exact title matches first, then by source quality ranking
    combined.sort((a, b) {
      final queryLower = query.toLowerCase();
      final aExact = a.title.toLowerCase() == queryLower;
      final bExact = b.title.toLowerCase() == queryLower;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      // Source quality ranking (higher priority = earlier in list)
      const sourceQuality = {
        'soundcloud': 6,
        'odysee': 5,
        'dailymotion': 4,
        'rumble': 3,
        'bilibili': 2,
        'youtube': 1,
      };
      return (sourceQuality[b.source] ?? 0) - (sourceQuality[a.source] ?? 0);
    });

    return combined;
  }

  Future<List<SearchResult>> _safeSoundCloudSearch(String query,
      {int limit = 10}) async {
    try {
      return await soundcloudSearcher.search(query, limit: limit);
    } catch (_) {
      return [];
    }
  }
}

// --─ yt-dlp generic searcher for desktop platforms ---------------------------

class YtDlpSearcher {
  final String? _ytDlpPath;
  final String _extractorPrefix; // e.g., 'ytsearch:', 'scsearch:', etc.
  final String _platformName; // e.g., 'YouTube', 'SoundCloud', 'Bilibili'
  final String _source; // lowercase source name for SearchResult

  YtDlpSearcher({
    required String? ytDlpPath,
    required String extractorPrefix,
    required String platformName,
    required String source,
  })  : _ytDlpPath = ytDlpPath,
        _extractorPrefix = extractorPrefix,
        _platformName = platformName,
        _source = source;

  /// Search using yt-dlp with the configured extractor.
  /// Runs: yt-dlp --dump-json "extractorPrefix:query" --match-filters "!is_live"
  /// Returns up to [limit] results parsed from yt-dlp's JSON output.
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    if (_ytDlpPath == null || _ytDlpPath!.isEmpty) return [];

    try {
      final searchQuery = '$_extractorPrefix${Uri.encodeComponent(query)}';
      final args = [
        '--dump-json',
        '--match-filters',
        '!is_live', // Skip live streams
        searchQuery,
      ];

      // Run yt-dlp process
      final process = await Process.start(_ytDlpPath!, args, runInShell: false);
      final output = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.drain();
      final exitCode = await process.exitCode;

      if (exitCode != 0 || output.isEmpty) {
        debugPrint('YtDlpSearcher($_platformName): yt-dlp exited with $exitCode');
        return [];
      }

      // Parse JSON output (each line is a separate video object)
      final lines = output.split('\n').where((l) => l.trim().isNotEmpty);
      final results = <SearchResult>[];

      for (final line in lines) {
        if (results.length >= limit) break;

        try {
          final json =
              safeJsonDecode<Map<String, dynamic>>(line.trim());
          if (json == null) continue;

          final id = json['id'] as String? ?? '';
          final title = json['title'] as String? ?? 'Unknown';
          final artist = json['uploader'] as String? ?? _platformName;
          final durationSec = json['duration'] as int? ?? 0;
          final thumbnailUrl =
              json['thumbnail'] as String? ?? '';

          results.add(SearchResult(
            id: id,
            title: title,
            artist: artist,
            duration: Duration(seconds: durationSec),
            thumbnailUrl: thumbnailUrl,
            source: _source,
          ));
        } catch (e) {
          debugPrint(
              'YtDlpSearcher($_platformName): JSON parse error on line: $e');
        }
      }

      return results;
    } catch (e) {
      debugPrint(
          'YtDlpSearcher($_platformName): search failed: $e');
      return [];
    }
  }
}

// --─ Platform-specific yt-dlp searchers (desktop only) ----------------------

class BiliSearcher {
  final YtDlpSearcher _searcher;

  BiliSearcher({required YtDlpService ytDlp, required String? ytDlpPath})
      : _searcher = YtDlpSearcher(
          ytDlpPath: ytDlpPath,
          extractorPrefix: 'bilisearch:',
          platformName: 'Bilibili',
          source: 'bilibili',
        );

  Future<List<SearchResult>> search(String query, {int limit = 10}) =>
      _searcher.search(query, limit: limit);
}

class RumbleSearcher {
  final YtDlpSearcher _searcher;

  RumbleSearcher({required YtDlpService ytDlp, required String? ytDlpPath})
      : _searcher = YtDlpSearcher(
          ytDlpPath: ytDlpPath,
          extractorPrefix: 'rumble:search:',
          platformName: 'Rumble',
          source: 'rumble',
        );

  Future<List<SearchResult>> search(String query, {int limit = 10}) =>
      _searcher.search(query, limit: limit);
}

class DailymotionSearcher {
  final YtDlpSearcher _searcher;

  DailymotionSearcher({required YtDlpService ytDlp, required String? ytDlpPath})
      : _searcher = YtDlpSearcher(
          ytDlpPath: ytDlpPath,
          extractorPrefix: 'dmsearch:',
          platformName: 'Dailymotion',
          source: 'dailymotion',
        );

  Future<List<SearchResult>> search(String query, {int limit = 10}) =>
      _searcher.search(query, limit: limit);
}

class OdyseeSearcher {
  final YtDlpSearcher _searcher;

  OdyseeSearcher({required YtDlpService ytDlp, required String? ytDlpPath})
      : _searcher = YtDlpSearcher(
          ytDlpPath: ytDlpPath,
          extractorPrefix: 'odysee:search:',
          platformName: 'Odysee',
          source: 'odysee',
        );

  Future<List<SearchResult>> search(String query, {int limit = 10}) =>
      _searcher.search(query, limit: limit);
}
