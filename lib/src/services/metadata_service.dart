import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/track_metadata.dart';

// ─── MusicBrainz metadata fetcher ────────────────────────────────────────────

class MusicBrainzService {
  static const _baseUrl = 'https://musicbrainz.org/ws/2';
  static const _userAgent = 'ConvertTheSpireReborn/1.0 (https://github.com)';

  /// Search for metadata by artist + title.
  Future<TrackMetadata?> searchTrack(String artist, String title) async {
    final query = Uri.encodeComponent('artist:"$artist" AND recording:"$title"');
    final url = '$_baseUrl/recording/?query=$query&fmt=json&limit=5';

    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    final recordings = data['recordings'] as List? ?? [];
    if (recordings.isEmpty) return null;

    final best = recordings.first;
    final releaseTitle = (best['releases'] as List?)?.firstOrNull;

    return TrackMetadata(
      artist: (best['artist-credit'] as List?)?.firstOrNull?['name'] ?? artist,
      title: best['title'] ?? title,
      album: releaseTitle?['title'] ?? 'Singles',
      year: _extractYear(best['first-release-date']),
      genre: await _fetchGenre(best['id']),
    );
  }

  int? _extractYear(String? date) {
    if (date == null || date.isEmpty) return null;
    return int.tryParse(date.split('-').first);
  }

  Future<String?> _fetchGenre(String recordingId) async {
    final url = '$_baseUrl/recording/$recordingId?inc=genres&fmt=json';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final genres = data['genres'] as List?;
      if (genres == null || genres.isEmpty) return null;
      return genres.first['name'];
    } catch (_) {
      return null;
    }
  }
}

// ─── Album art downloader ────────────────────────────────────────────────────

class AlbumArtService {
  Future<String?> downloadAlbumArt(String thumbnailUrl, String trackId) async {
    try {
      final response = await http.get(Uri.parse(thumbnailUrl));
      if (response.statusCode != 200) return null;
      final tempDir = await getTemporaryDirectory();
      final artPath = '${tempDir.path}${Platform.pathSeparator}album_art_$trackId.jpg';
      final file = File(artPath);
      await file.writeAsBytes(response.bodyBytes);
      return artPath;
    } catch (_) {
      return null;
    }
  }
}

// ─── LRClib lyrics fetcher ───────────────────────────────────────────────────

class LyricsService {
  static const _baseUrl = 'https://lrclib.net/api';

  /// Fetch lyrics (prefer synced/LRC, fallback to plain).
  Future<String?> fetchLyrics(String artist, String title, {int? durationSeconds}) async {
    final params = <String, String>{
      'artist_name': artist,
      'track_name': title,
      if (durationSeconds != null) 'duration': durationSeconds.toString(),
    };

    final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: params);
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final synced = data['syncedLyrics'] as String?;
      if (synced != null && synced.isNotEmpty) return synced;
      return data['plainLyrics'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Save lyrics as a .lrc sidecar file next to the audio file.
  Future<void> saveLyricsFile(String lyrics, String audioFilePath) async {
    final lrcPath = audioFilePath.replaceAll(RegExp(r'\.\w+$'), '.lrc');
    final file = File(lrcPath);
    await file.writeAsString(lyrics);
  }
}
