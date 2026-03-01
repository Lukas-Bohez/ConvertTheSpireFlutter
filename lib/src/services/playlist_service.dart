import 'dart:io';
import 'dart:math';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import '../models/search_result.dart';

/// Handles playlist fetching, M3U generation, and smart folder comparison.
class PlaylistService {
  final YoutubeExplode _yt;

  PlaylistService({required YoutubeExplode yt}) : _yt = yt;

  // ─── YouTube playlists ───────────────────────────────────────────────────

  Future<List<SearchResult>> getYouTubePlaylistTracks(String playlistUrl) async {
    final playlistId = PlaylistId(playlistUrl);
    final videos = await _yt.playlists.getVideos(playlistId).toList();

    return videos.map((video) {
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

  /// Get playlist metadata (title, author, description).
  Future<PlaylistInfo> getPlaylistInfo(String playlistUrl) async {
    final playlistId = PlaylistId(playlistUrl);
    final playlist = await _yt.playlists.get(playlistId);
    return PlaylistInfo(
      title: playlist.title,
      author: playlist.author,
      description: playlist.description,
      videoCount: playlist.videoCount ?? 0,
    );
  }

  /// Get the audio URL for a given YouTube video id.
  Future<String> getAudioUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    // Prefer audio-only (saves bandwidth), fall back to muxed
    final stream = manifest.audioOnly.isNotEmpty
        ? manifest.audioOnly.withHighestBitrate()
        : manifest.muxed.withHighestBitrate();
    return stream.url.toString();
  }

  // ─── M3U generation ──────────────────────────────────────────────────────

  Future<void> generateM3U(List<SearchResult> tracks, String outputPath, {String format = 'mp3'}) async {
    final ext = format.toLowerCase();
    final buf = StringBuffer('#EXTM3U\n');
    for (final track in tracks) {
      buf.writeln('#EXTINF:${track.duration.inSeconds},${track.artist} - ${track.title}');
      buf.writeln('${track.artist}/${track.title}.$ext');
    }
    final file = File(outputPath);
    await file.writeAsString(buf.toString());
  }

  /// Export a list of track titles to a plain text file (one per line).
  Future<void> exportTrackList(
    List<SearchResult> tracks,
    String outputPath, {
    bool includeArtist = true,
  }) async {
    final buf = StringBuffer();
    for (final t in tracks) {
      buf.writeln(includeArtist ? '${t.artist} - ${t.title}' : t.title);
    }
    await File(outputPath).writeAsString(buf.toString());
  }

  // ─── Smart playlist ↔ folder comparison ──────────────────────────────────

  /// Scans [folderPath] recursively and cross-references every playlist track
  /// against the files found.  Uses multi-strategy fuzzy matching so renamed,
  /// reformatted, or differently-cased files are still recognised.
  Future<PlaylistFolderComparison> compareToFolder(
    List<SearchResult> playlistTracks,
    String folderPath, {
    double matchThreshold = 0.55,
    bool recursive = true,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      return PlaylistFolderComparison(
        total: playlistTracks.length,
        matched: [],
        missing: List.of(playlistTracks),
        extras: [],
        folderPath: folderPath,
      );
    }

    // ── 1. Index all audio files in the folder ──────────────────────────
    final audioExtensions = {'.mp3', '.flac', '.m4a', '.opus', '.ogg', '.wav', '.aac', '.wma', '.webm'};
    final localFiles = <_LocalFile>[];

    await for (final entity in dir.list(recursive: recursive)) {
      if (entity is File) {
        final path = entity.path;
        final ext = _extensionOf(path);
        if (!audioExtensions.contains(ext)) continue;

        final fileName = _fileNameWithoutExt(path);
        localFiles.add(_LocalFile(
          path: path,
          baseName: fileName,
          normalised: _normalise(fileName),
          tokens: _tokenise(fileName),
        ));
      }
    }

    // ── 2. Match each playlist track to the best local file ─────────────
    final usedFileIndices = <int>{};
    final matched = <TrackMatch>[];
    final missing = <SearchResult>[];

    for (final track in playlistTracks) {
      final result = _findBestMatch(track, localFiles, usedFileIndices, matchThreshold);
      if (result != null) {
        matched.add(result);
        usedFileIndices.add(result._fileIndex);
      } else {
        missing.add(track);
      }
    }

    // ── 3. Detect extra files not in the playlist ───────────────────────
    final extras = <ExtraFile>[];
    for (var i = 0; i < localFiles.length; i++) {
      if (!usedFileIndices.contains(i)) {
        extras.add(ExtraFile(
          filePath: localFiles[i].path,
          fileName: localFiles[i].baseName,
        ));
      }
    }

    return PlaylistFolderComparison(
      total: playlistTracks.length,
      matched: matched,
      missing: missing,
      extras: extras,
      folderPath: folderPath,
    );
  }

  // ─── Matching engine ─────────────────────────────────────────────────────

  /// Tries multiple strategies (exact, normalised, token overlap, fuzzy) and
  /// returns the best match above [threshold], or null.
  TrackMatch? _findBestMatch(
    SearchResult track,
    List<_LocalFile> files,
    Set<int> usedIndices,
    double threshold,
  ) {
    final trackTitle = _normalise(track.title);
    final trackArtist = _normalise(track.artist);
    final trackFull = _normalise('${track.artist} ${track.title}');
    final trackTokens = {..._tokenise(track.title), ..._tokenise(track.artist)};
    // Remove extremely common words that hurt matching accuracy
    trackTokens.removeAll(_stopWords);

    int bestIndex = -1;
    double bestScore = 0;
    MatchMethod bestMethod = MatchMethod.fuzzy;

    for (var i = 0; i < files.length; i++) {
      if (usedIndices.contains(i)) continue;
      final f = files[i];

      // Strategy 1 – exact normalised match
      if (f.normalised == trackFull || f.normalised == trackTitle) {
        return TrackMatch(
          track: track,
          filePath: f.path,
          fileName: f.baseName,
          confidence: 1.0,
          method: MatchMethod.exact,
          fileIndex: i,
        );
      }

      // Strategy 2 – normalised containment (either direction)
      if (f.normalised.contains(trackTitle) || trackTitle.contains(f.normalised)) {
        final score = 0.90;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
          bestMethod = MatchMethod.contains;
        }
        continue;
      }

      // Strategy 3 – artist-title both found somewhere in filename
      if (trackArtist.isNotEmpty &&
          f.normalised.contains(trackArtist) &&
          f.normalised.contains(trackTitle)) {
        final score = 0.92;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
          bestMethod = MatchMethod.artistTitle;
        }
        continue;
      }

      // Strategy 4 – token overlap (Jaccard similarity)
      if (trackTokens.isNotEmpty && f.tokens.isNotEmpty) {
        final intersection = trackTokens.intersection(f.tokens).length;
        final union = trackTokens.union(f.tokens).length;
        final jaccard = intersection / union;
        if (jaccard > bestScore) {
          bestScore = jaccard;
          bestIndex = i;
          bestMethod = MatchMethod.tokenOverlap;
        }
      }

      // Strategy 5 – Levenshtein-based similarity
      final levSim = _levenshteinSimilarity(trackFull, f.normalised);
      if (levSim > bestScore) {
        bestScore = levSim;
        bestIndex = i;
        bestMethod = MatchMethod.fuzzy;
      }
    }

    if (bestIndex >= 0 && bestScore >= threshold) {
      return TrackMatch(
        track: track,
        filePath: files[bestIndex].path,
        fileName: files[bestIndex].baseName,
        confidence: bestScore,
        method: bestMethod,
        fileIndex: bestIndex,
      );
    }
    return null;
  }

  // ─── String helpers ───────────────────────────────────────────────────────

  /// Normalise a string for comparison: lowercase, strip accents, remove
  /// common noise like "(Official Audio)", brackets, punctuation.
  static String _normalise(String input) {
    var s = input.toLowerCase();
    // Remove bracketed/parenthesised noise
    s = s.replaceAll(RegExp(r'\(.*?\)'), '');
    s = s.replaceAll(RegExp(r'\[.*?\]'), '');
    // Remove common YouTube suffixes
    s = s.replaceAll(RegExp(r'official\s*(music\s*)?video', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'official\s*audio', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'lyrics?\s*video', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'visuali[sz]er', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'hd|hq|4k|1080p', caseSensitive: false), '');
    // Strip non-alphanumeric (keep spaces)
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    // Collapse whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Tokenise into unique lowercase words ≥ 2 chars.
  static Set<String> _tokenise(String input) {
    final n = _normalise(input);
    return n
        .split(' ')
        .where((w) => w.length >= 2)
        .toSet();
  }

  static const _stopWords = <String>{
    'the', 'and', 'for', 'feat', 'featuring', 'with', 'from', 'remix',
    'mix', 'edit', 'version', 'original', 'extended', 'radio', 'live',
  };

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot).toLowerCase();
  }

  static String _fileNameWithoutExt(String path) {
    // Handle both / and \
    final sep = path.lastIndexOf(RegExp(r'[/\\]'));
    var name = sep < 0 ? path : path.substring(sep + 1);
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    return name;
  }

  /// Levenshtein distance → similarity ratio in 0..1.
  static double _levenshteinSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxLen = max(a.length, b.length);
    final dist = _levenshtein(a, b);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String a, String b) {
    final la = a.length, lb = b.length;
    var prev = List.generate(lb + 1, (i) => i);
    var curr = List.filled(lb + 1, 0);
    for (var i = 1; i <= la; i++) {
      curr[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          prev[j] + 1,
          curr[j - 1] + 1,
          prev[j - 1] + cost,
        ].reduce(min);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════════════

/// Internal helper for indexing local files.
class _LocalFile {
  final String path;
  final String baseName;
  final String normalised;
  final Set<String> tokens;

  const _LocalFile({
    required this.path,
    required this.baseName,
    required this.normalised,
    required this.tokens,
  });
}

/// How a track was matched to a local file.
enum MatchMethod { exact, contains, artistTitle, tokenOverlap, fuzzy }

/// Basic playlist metadata.
class PlaylistInfo {
  final String title;
  final String author;
  final String description;
  final int videoCount;

  const PlaylistInfo({
    required this.title,
    required this.author,
    required this.description,
    required this.videoCount,
  });
}

/// A playlist track that was matched to a local file.
class TrackMatch {
  final SearchResult track;
  final String filePath;
  final String fileName;
  final double confidence;     // 0..1
  final MatchMethod method;
  final int _fileIndex;        // internal index for de-duplication

  const TrackMatch({
    required this.track,
    required this.filePath,
    required this.fileName,
    required this.confidence,
    required this.method,
    required int fileIndex,
  }) : _fileIndex = fileIndex;

  String get confidenceLabel {
    if (confidence >= 0.95) return 'Exact';
    if (confidence >= 0.80) return 'High';
    if (confidence >= 0.65) return 'Medium';
    return 'Low';
  }
}

/// A file in the folder that doesn't match any playlist track.
class ExtraFile {
  final String filePath;
  final String fileName;

  const ExtraFile({required this.filePath, required this.fileName});
}

/// Full result of cross-referencing a playlist against a local folder.
class PlaylistFolderComparison {
  final int total;
  final List<TrackMatch> matched;
  final List<SearchResult> missing;
  final List<ExtraFile> extras;
  final String folderPath;

  const PlaylistFolderComparison({
    required this.total,
    required this.matched,
    required this.missing,
    required this.extras,
    required this.folderPath,
  });

  int get downloadedCount => matched.length;
  int get missingCount => missing.length;
  int get extraCount => extras.length;

  double get completionPercentage =>
      total == 0 ? 100 : (downloadedCount / total) * 100;

  /// Matched tracks with confidence below a threshold (potential mismatches).
  List<TrackMatch> uncertainMatches({double below = 0.70}) =>
      matched.where((m) => m.confidence < below).toList();
}
