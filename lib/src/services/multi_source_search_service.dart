import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import '../models/search_result.dart';

// ─── YouTube searcher ────────────────────────────────────────────────────────

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

// ─── SoundCloud searcher ─────────────────────────────────────────────────────

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

      final data = jsonDecode(response.body);
      final collection = data['collection'] as List? ?? [];

      return collection.map<SearchResult>((track) {
        return SearchResult(
          id: track['id'].toString(),
          title: track['title'] ?? '',
          artist: track['user']?['username'] ?? '',
          duration: Duration(milliseconds: (track['duration'] as num?)?.toInt() ?? 0),
          thumbnailUrl: track['artwork_url'] ?? '',
          source: 'soundcloud',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

// ─── Multi-source aggregator ─────────────────────────────────────────────────

class MultiSourceSearchService {
  final YouTubeSearcher youtubeSearcher;
  final SoundCloudSearcher soundcloudSearcher;

  MultiSourceSearchService({
    required this.youtubeSearcher,
    required this.soundcloudSearcher,
  });

  /// Search YouTube and SoundCloud in parallel, merge and rank results.
  Future<List<SearchResult>> searchAll(String query, {int limitPerSource = 10}) async {
    final results = await Future.wait([
      youtubeSearcher.search(query, limit: limitPerSource),
      _safeSoundCloudSearch(query, limit: limitPerSource),
    ]);

    final combined = results.expand((list) => list).toList();

    // Sort: exact title matches first, then by source quality ranking
    combined.sort((a, b) {
      final queryLower = query.toLowerCase();
      final aExact = a.title.toLowerCase() == queryLower;
      final bExact = b.title.toLowerCase() == queryLower;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      const sourceQuality = {'soundcloud': 2, 'youtube': 1};
      return (sourceQuality[b.source] ?? 0) - (sourceQuality[a.source] ?? 0);
    });

    return combined;
  }

  Future<List<SearchResult>> _safeSoundCloudSearch(String query, {int limit = 10}) async {
    try {
      return await soundcloudSearcher.search(query, limit: limit);
    } catch (_) {
      return [];
    }
  }
}
