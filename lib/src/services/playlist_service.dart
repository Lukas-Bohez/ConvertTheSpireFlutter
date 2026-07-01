import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:metadata_god/metadata_god.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import '../models/search_result.dart';
import 'yt_dlp_service.dart' show YtDlpService;

/// Handles playlist fetching, M3U generation, and smart folder comparison.
class PlaylistService {
  final YoutubeExplode _yt;
  final YtDlpService? _ytDlp;
  final String? _ytDlpPath;

  static const Duration _playlistStreamTimeout = Duration(seconds: 25);

  String? _lastPlaylistDiagnostics;
  String? get lastPlaylistDiagnostics => _lastPlaylistDiagnostics;

  PlaylistService({required YoutubeExplode yt, YtDlpService? ytDlp, String? ytDlpPath})
      : _yt = yt, _ytDlp = ytDlp, _ytDlpPath = ytDlpPath;

  // --─ YouTube playlists --------------------------------------------------─

  Future<List<SearchResult>> getYouTubePlaylistTracks(String playlistUrl,
      {int? maxVideos}) async {
    final playlistId = PlaylistId(playlistUrl);
    final cap = maxVideos;
    final videosById = <String, Video>{};
    _lastPlaylistDiagnostics = null;
    int expectedCount = 0;

    // --- Step 1: yt-dlp is the primary fetcher (handles large playlists reliably)
    // youtube_explode_dart times out on playlists >100 videos. yt-dlp's
    // flat-playlist mode returns all entries in seconds.
    if (await _resolveYtDlpAtCallTime() != null) {
      try {
        final count = await _fetchPlaylistCountViaYtDlp(playlistUrl);
        if (count != null && count > 0) expectedCount = count;
        final ytDlpTracks = await _fetchPlaylistTracksViaYtDlp(playlistUrl, cap: cap);
        if (ytDlpTracks.isNotEmpty) {
          _lastPlaylistDiagnostics = null;
          if (expectedCount > 0 && ytDlpTracks.length < expectedCount) {
            _lastPlaylistDiagnostics =
                'Loaded ${ytDlpTracks.length} of reported $expectedCount playlist entries. '
                'This mismatch usually means some videos are private, deleted, region-restricted, '
                'or temporarily unavailable through the API.';
          }
          return ytDlpTracks;
        }
      } catch (_) {}
    }

    // --- Step 2: Fallback to youtube_explode_dart (mobile / no yt-dlp) ---
    try {
      final playlist = await _yt.playlists.get(playlistId);
      expectedCount = playlist.videoCount ?? 0;
    } catch (_) {}
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final before = videosById.length;
        final stream =
            _yt.playlists.getVideos(playlistId).timeout(_playlistStreamTimeout);
        await for (final video in stream) {
          videosById[video.id.value] = video;
          if (cap != null && videosById.length >= cap) break;
        }
        final reachedCap = cap != null && videosById.length >= cap;
        final reachedExpected =
            expectedCount > 0 && videosById.length >= expectedCount;
        if (reachedCap || reachedExpected) break;
        if (videosById.length == before) break;
      }
    } on TimeoutException catch (_) {
      // Stream stalled; return whatever we've collected so far.
    } catch (_) {}

    final videos = videosById.values.toList();

    if (expectedCount > 0 && videos.length < expectedCount) {
      _lastPlaylistDiagnostics =
          'Loaded ${videos.length} of reported $expectedCount playlist entries. '
          'This mismatch usually means some videos are private, deleted, region-restricted, '
          'or temporarily unavailable through the API.';
    }

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

  /// Get playlist metadata (title, author, description, video count).
  Future<PlaylistInfo> getPlaylistInfo(String playlistUrl) async {
    final playlistId = PlaylistId(playlistUrl);
    final playlist = await _yt.playlists.get(playlistId);
    var videoCount = playlist.videoCount ?? 0;
    // yt-dlp fallback if youtube_explode_dart returns 0 (YouTube page change).
    if (videoCount == 0 && await _resolveYtDlpAtCallTime() != null) {
      try {
        final count = await _fetchPlaylistCountViaYtDlp(playlistUrl);
        if (count != null && count > 0) videoCount = count;
      } catch (_) {}
    }
    return PlaylistInfo(
      title: playlist.title,
      author: playlist.author,
      description: playlist.description,
      videoCount: videoCount,
    );
  }

  /// Resolve the yt-dlp path at call time so it works even when the binary
  /// is downloaded asynchronously after construction (e.g. on first launch).
  /// If the binary is not found, attempts to download it on demand via
  /// ensureAvailable() so playlist fetching never fails due to a missing binary.
  Future<String?> _resolveYtDlpAtCallTime() async {
    if (_ytDlp == null) return null;
    if (_ytDlpPath != null && _ytDlpPath!.isNotEmpty) {
      final resolved = await _ytDlp!.resolveAvailablePath(_ytDlpPath);
      if (resolved != null) return resolved;
    }
    // Try to find it at the app support dir or PATH
    final autoResolved = await _ytDlp!.resolveAvailablePath(null);
    if (autoResolved != null) return autoResolved;
    // Last resort: download yt-dlp on demand. This handles the case where
    // the app was just installed or the binary was deleted/moved.
    // Timeout: 90 seconds — enough to download ~15MB even on slow connections.
    try {
      return await _ytDlp!
          .ensureAvailable()
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      return null;
    }
  }

  /// Fallback: fetch playlist video count via yt-dlp --dump-json --flat-playlist.
  /// yt-dlp is far more resilient to YouTube page structure changes than
  /// youtube_explode_dart's HTML parser.
  Future<int?> _fetchPlaylistCountViaYtDlp(String playlistUrl) async {
    final ytDlpPath = await _resolveYtDlpAtCallTime();
    if (ytDlpPath == null) return null;
    final args = <String>[
      '--dump-json',
      '--flat-playlist',
      '--playlist-end',
      '1',
      '--no-warnings',
      '--no-mtime',
      '--extractor-retries',
      '3',
      playlistUrl,
    ];
    final process = await Process.start(ytDlpPath, args,
        workingDirectory: Directory.systemTemp.path,
        runInShell: false);
    final output = await process.stdout.transform(utf8.decoder).join();
    await process.stderr.drain();
    final exitCode = await process.exitCode;
    if (exitCode != 0) return null;
    final lines = output.trim().split('\n');
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        if (json.containsKey('playlist_count')) {
          final count = json['playlist_count'];
          if (count is int && count > 0) return count;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Fetch playlist tracks via yt-dlp --dump-json --flat-playlist.
  /// yt-dlp's flat-playlist caps at ~101 entries per page regardless of
  /// --playlist-end. We paginate in chunks of 100 entries to work around this.
  Future<List<SearchResult>> _fetchPlaylistTracksViaYtDlp(String playlistUrl,
      {int? cap}) async {
    final ytDlpPath = await _resolveYtDlpAtCallTime();
    if (ytDlpPath == null) return const [];

    // Determine how many entries to fetch. If no cap, fetch everything by
    // resolving the count first, then paginate in 100-entry chunks.
    final int totalToFetch;
    if (cap != null && cap > 0) {
      totalToFetch = cap;
    } else {
      // Resolve count first so we know how many chunks to loop
      final count = await _fetchPlaylistCountViaYtDlp(playlistUrl);
      if (count == null || count <= 0) return const [];
      totalToFetch = count;
    }

    const int chunkSize = 100;
    final results = <SearchResult>[];

    for (int start = 1; start <= totalToFetch; start += chunkSize) {
      final end = (start + chunkSize - 1).clamp(1, totalToFetch);
      final args = <String>[
        '--dump-json',
        '--flat-playlist',
        '--playlist-start', start.toString(),
        '--playlist-end', end.toString(),
        '--no-warnings',
        '--no-mtime',
        '--extractor-retries', '3',
        playlistUrl,
      ];

      final process = await Process.start(ytDlpPath, args,
          workingDirectory: Directory.systemTemp.path,
          runInShell: false);
      final output = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.drain();
      final exitCode = await process.exitCode;
      if (exitCode != 0) break;

      final lines = output.trim().split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final id = json['id'] as String?;
          final title = json['title'] as String? ?? 'Unknown';
          final artist = json['channel'] as String? ?? json['uploader'] as String? ?? 'Unknown';
          final durationSec = json['duration'] as int? ?? 0;
          final thumbnail = json['thumbnail'] as String? ?? '';
          results.add(SearchResult(
            id: id ?? '',
            title: title,
            artist: artist,
            duration: Duration(seconds: durationSec),
            thumbnailUrl: thumbnail,
            source: 'youtube',
          ));
        } catch (_) {
          continue;
        }
      }
    }
    return results;
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

  // --─ M3U generation ------------------------------------------------------

  Future<void> generateM3U(List<SearchResult> tracks, String outputPath,
      {String format = 'mp3'}) async {
    final ext = format.toLowerCase();
    final buf = StringBuffer('#EXTM3U\n');
    for (final track in tracks) {
      buf.writeln(
          '#EXTINF:${track.duration.inSeconds},${track.artist} - ${track.title}');
      buf.writeln('${track.artist}/${track.title}.$ext');
    }
    final file = File(outputPath);
    await file.writeAsString(buf.toString());
  }

  /// Generate an M3U using actual local file paths from `TrackMatch` results.
  /// This ensures the M3U contains real file locations (with correct extensions)
  /// when a playlist has been compared against a folder.
  Future<void> generateM3UFromMatches(
      List<TrackMatch> matches, String outputPath) async {
    final buf = StringBuffer('#EXTM3U\n');
    for (final m in matches) {
      buf.writeln(
          '#EXTINF:${m.track.duration.inSeconds},${m.track.artist} - ${m.track.title}');
      buf.writeln(m.filePath);
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

  // --─ Smart playlist ↁEfolder comparison ----------------------------------

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

    // -- 1. Index all audio files in the folder --------------------------
    final audioExtensions = {
      '.mp3',
      '.flac',
      '.m4a',
      '.opus',
      '.ogg',
      '.wav',
      '.aac',
      '.wma',
      '.webm'
    };
    final localFiles = <_LocalFile>[];

    await for (final entity in dir.list(recursive: recursive)) {
      if (entity is File) {
        final path = entity.path;
        final ext = _extensionOf(path);
        if (!audioExtensions.contains(ext)) continue;

        final fileName = _fileNameWithoutExt(path);
        final metadataLabels = await _labelsFromMetadata(path, ext);
        final labels = <String>{fileName, ...metadataLabels}.toList();
        localFiles.add(_LocalFile(
          path: path,
          baseName: fileName,
          labels: labels,
          normalised: _normalise(fileName),
          tokens: {
            ..._tokenise(fileName),
            ...labels.expand(_tokenise),
          },
        ));
      }
    }

    // -- 2. Match each playlist track to the best local file ------------─
    final usedFileIndices = <int>{};
    final matched = <TrackMatch>[];
    final missing = <SearchResult>[];

    for (final track in playlistTracks) {
      final result =
          _findBestMatch(track, localFiles, usedFileIndices, matchThreshold);
      if (result != null) {
        matched.add(result);
        usedFileIndices.add(result._fileIndex);
      } else {
        missing.add(track);
      }
    }

    // -- 3. Detect extra files not in the playlist ----------------------─
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

  // --─ Matching engine ----------------------------------------------------─

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
      final labels = f.labels.isEmpty ? [f.baseName] : f.labels;

      for (final label in labels) {
        final normalisedLabel = _normalise(label);

        if (_titlesMatch(track.title, label) ||
            _titlesMatch('${track.artist} ${track.title}', label)) {
          return TrackMatch(
            track: track,
            filePath: f.path,
            fileName: f.baseName,
            confidence: 1.0,
            method: MatchMethod.exact,
            fileIndex: i,
          );
        }

        // Strategy 1 - exact normalised match
        if (normalisedLabel == trackFull || normalisedLabel == trackTitle) {
          return TrackMatch(
            track: track,
            filePath: f.path,
            fileName: f.baseName,
            confidence: 1.0,
            method: MatchMethod.exact,
            fileIndex: i,
          );
        }

        // Strategy 2 - normalised containment (either direction)
        if (normalisedLabel.contains(trackTitle) ||
            trackTitle.contains(normalisedLabel)) {
          final score = 0.90;
          if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
            bestMethod = MatchMethod.contains;
          }
          continue;
        }

        // Strategy 3 - artist-title both found somewhere in filename/metadata
        if (trackArtist.isNotEmpty &&
            normalisedLabel.contains(trackArtist) &&
            normalisedLabel.contains(trackTitle)) {
          final score = 0.92;
          if (score > bestScore) {
            bestScore = score;
            bestIndex = i;
            bestMethod = MatchMethod.artistTitle;
          }
          continue;
        }

        // Strategy 4 - token overlap (Jaccard similarity)
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

        // Strategy 5 - Levenshtein-based similarity
        final levSim = _levenshteinSimilarity(trackFull, normalisedLabel);
        if (levSim > bestScore) {
          bestScore = levSim;
          bestIndex = i;
          bestMethod = MatchMethod.fuzzy;
        }
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

  // --─ String helpers ------------------------------------------------------─

  static bool _titlesMatch(String playlistTitle, String localFilename) {
    final a = _aggressiveNorm(playlistTitle);
    final b = _aggressiveNorm(localFilename);
    if (a.isNotEmpty &&
        b.isNotEmpty &&
        (a == b || a.contains(b) || b.contains(a))) {
      return true;
    }

    final subtitles = <String>{
      ..._titleSegments(playlistTitle),
      ..._titleSegments(localFilename),
    }.where((s) => s.length >= 4).toList();
    for (final sa in subtitles) {
      if (a.contains(sa) ||
          b.contains(sa) ||
          sa.contains(a) ||
          sa.contains(b)) {
        return true;
      }
    }

    final wordsA = a.split(' ').where((w) => w.length >= 3).toSet();
    final wordsB = b.split(' ').where((w) => w.length >= 3).toSet();
    if (wordsA.isNotEmpty && wordsB.isNotEmpty) {
      final overlap = wordsA.intersection(wordsB).length;
      final minLen =
          wordsA.length < wordsB.length ? wordsA.length : wordsB.length;
      if (minLen > 0 && overlap / minLen >= 0.6) return true;
    }

    return false;
  }

  static Iterable<String> _titleSegments(String input) sync* {
    final parts = <String>[input];
    if (input.contains('/')) {
      parts.addAll(input.split('/'));
    }
    if (input.contains(' - ')) {
      parts.addAll(input.split(' - '));
    }
    final paren = RegExp(r'\(([^)]+)\)').firstMatch(input)?.group(1);
    if (paren != null && paren.isNotEmpty) {
      parts.add(paren);
    }
    for (final part in parts) {
      final norm = _aggressiveNorm(part);
      if (norm.isNotEmpty) yield norm;
    }
  }

  static String _aggressiveNorm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\.\w{2,5}$'), '')
      .replaceAll(RegExp(r'\s*\[[a-zA-Z0-9_\-]{11}\]'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Normalise a string for comparison: lowercase, strip accents, remove
  /// common noise like "(Official Audio)", brackets, punctuation.
  static String _normalise(String input) {
    var s = input.toLowerCase();
    s = s.replaceAll(RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s*\[[a-zA-Z0-9_\-]{11}\]'), '');
    // Remove bracketed/parenthesised noise
    s = s.replaceAll(RegExp(r'\(.*?\)'), '');
    s = s.replaceAll(RegExp(r'\[.*?\]'), '');
    // Remove common YouTube suffixes
    s = s.replaceAll(
        RegExp(r'official\s*(music\s*)?video', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'official\s*audio', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'lyrics?\s*video', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'visuali[sz]er', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'hd|hq|4k|1080p', caseSensitive: false), '');
    // Keep Unicode letters and digits so non-English titles still match.
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '');
    // Collapse whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Tokenise into unique lowercase words ≥ 2 chars.
  static Set<String> _tokenise(String input) {
    final n = _normalise(input);
    return n.split(' ').where((w) => w.length >= 2).toSet();
  }

  static const _stopWords = <String>{
    'the',
    'and',
    'for',
    'feat',
    'featuring',
    'with',
    'from',
    'remix',
    'mix',
    'edit',
    'version',
    'original',
    'extended',
    'radio',
    'live',
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

  /// Levenshtein distance ↁEsimilarity ratio in 0..1.
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

// ══════════════════════════════════════════════════════════════════════════════╁E
// Data classes
// ══════════════════════════════════════════════════════════════════════════════╁E

/// Internal helper for indexing local files.
class _LocalFile {
  final String path;
  final String baseName;
  final List<String> labels;
  final String normalised;
  final Set<String> tokens;

  const _LocalFile({
    required this.path,
    required this.baseName,
    required this.labels,
    required this.normalised,
    required this.tokens,
  });
}

Future<List<String>> _labelsFromMetadata(String path, String ext) async {
  try {
    if (!['.mp3', '.m4a', '.ogg', '.flac'].contains(ext)) {
      return const <String>[];
    }
    await MetadataGod.initialize();
    final metadata = await MetadataGod.readMetadata(file: path);
    final labels = <String>[];
    final title = metadata.title?.trim() ?? '';
    final artist = metadata.artist?.trim() ?? '';
    if (title.isNotEmpty) labels.add(title);
    if (artist.isNotEmpty) labels.add(artist);
    if (title.isNotEmpty && artist.isNotEmpty) {
      labels.add('$artist - $title');
    }
    return labels;
  } catch (_) {
    return const <String>[];
  }
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
  final double confidence; // 0..1
  final MatchMethod method;
  final int _fileIndex; // internal index for de-duplication

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
