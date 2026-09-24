import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, visibleForTesting;
import 'package:metadata_god/metadata_god.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import '../models/search_result.dart';
import 'log_service.dart';
import 'platform_dirs.dart';
import 'yt_dlp_service.dart' show YtDlpService;

/// Handles playlist fetching, M3U generation, and smart folder comparison.
class PlaylistService {
  final YoutubeExplode _yt;
  final YtDlpService? _ytDlp;
  final String? _ytDlpPath;
  final LogService? _logs;

  // Inactivity timeout per playlist page. Large playlists over slower/mobile
  // connections (Android) can idle past 60s between pages, so give room.
  static const Duration _playlistStreamTimeout = Duration(seconds: 180);

  String? _lastPlaylistDiagnostics;
  String? get lastPlaylistDiagnostics => _lastPlaylistDiagnostics;

  PlaylistService({required YoutubeExplode yt, YtDlpService? ytDlp, String? ytDlpPath, LogService? logs})
      : _yt = yt, _ytDlp = ytDlp, _ytDlpPath = ytDlpPath, _logs = logs;

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
          _logs?.add('Playlist fetched via yt-dlp: ${ytDlpTracks.length} tracks');
          if (expectedCount > 0 && ytDlpTracks.length < expectedCount) {
            _lastPlaylistDiagnostics =
                'Loaded ${ytDlpTracks.length} of reported $expectedCount playlist entries. '
                'This mismatch usually means some videos are private, deleted, region-restricted, '
                'or temporarily unavailable through the API.';
          }
          return ytDlpTracks;
        }
      } catch (e) {
        _logs?.add('yt-dlp playlist fetch failed: $e');
      }
    }

    // --- Step 2: Fallback to youtube_explode_dart (mobile / no yt-dlp) ---
    // yt-dlp is desktop-only; on Android/iOS every playlist runs through here.
    // Per-video logging below pinpoints the actual failure shape (slow trickle
    // vs. immediate empty page vs. exception) on large playlists.
    _lastPlaylistDiagnostics = null;
    try {
      final playlist = await _yt.playlists.get(playlistId);
      expectedCount = playlist.videoCount ?? 0;
    } catch (e) {
      _logs?.add('youtube_explode_dart playlist.get failed: $e');
    }
    // --- Step 2a: Direct lockupViewModel parser --------------------------------
    // YouTube migrated playlist pages from `playlistVideoRenderer` to the new
    // `lockupViewModel` format. youtube_explode_dart 3.1.0 only parses the
    // legacy renderer, so its getVideos() stream yields 0 videos for every
    // playlist - the "0/800" bug on Android/iOS (no yt-dlp fallback there).
    // This parser walks the page JSON for lockups with
    // contentType=LOCKUP_CONTENT_TYPE_VIDEO, which is position-independent:
    // it keeps working even if YouTube reshuffles the surrounding containers.
    try {
      final lockupVideos =
          await _fetchPlaylistViaLockupParser(playlistId, cap, expectedCount);
      for (final video in lockupVideos) {
        videosById[video.id.value] = video;
      }
      _logs?.add(
          'Lockup parser: ${lockupVideos.length} videos (total ${videosById.length}, expected ~$expectedCount)');
    } catch (e) {
      _logs?.add('Lockup parser failed: $e');
    }

    // --- Step 2b: Legacy youtube_explode_dart stream (old-format pages) -------
    if (videosById.isEmpty) {
      try {
        const maxAttempts = 5;
        final stopwatch = Stopwatch()..start();
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          final before = videosById.length;
          int emittedThisAttempt = 0;
          final stream = _yt.playlists
              .getVideos(playlistId)
              .timeout(_playlistStreamTimeout);
          try {
            await for (final video in stream) {
              videosById[video.id.value] = video;
              emittedThisAttempt++;
              if (attempt == 1 && emittedThisAttempt % 25 == 0) {
                _logs?.add(
                    'Playlist loading: ${videosById.length} videos in '
                    '${stopwatch.elapsed.inSeconds}s...');
              }
              if (cap != null && videosById.length >= cap) break;
            }
          } on TimeoutException {
            _logs?.add(
                'Playlist stream idle >${_playlistStreamTimeout.inSeconds}s on '
                'attempt $attempt after ${videosById.length} videos; '
                '${stopwatch.elapsed.inSeconds}s elapsed - will retry from start');
          }
          final reachedCap = cap != null && videosById.length >= cap;
          final reachedExpected =
              expectedCount > 0 && videosById.length >= expectedCount;
          if (reachedCap || reachedExpected) break;
          // No net progress this attempt - don't keep re-treading the same pages.
          if (videosById.length == before) {
            _logs?.add(
                'Playlist attempt $attempt made no progress (${videosById.length} '
                'videos) - stopping retries');
            break;
          }
        }
        _logs?.add(
            'Playlist fetched via youtube_explode_dart: ${videosById.length} '
            'tracks in ${stopwatch.elapsed.inSeconds}s (expected ~$expectedCount)');
      } catch (e) {
        _logs?.add('youtube_explode_dart playlist fetch error: $e');
      }
    }

    final videos = videosById.values.toList();
    _logs?.add('Playlist fetched via youtube_explode_dart: ${videos.length} tracks');

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

  // --─ Lockup parser (new YouTube playlist page format) ────────────────────

  /// Fetches playlist videos by walking the page JSON for `lockupViewModel`
  /// entries with `contentType == LOCKUP_CONTENT_TYPE_VIDEO`. Handles the new
  /// YouTube page format that youtube_explode_dart 3.1.0 cannot parse, and
  /// follows `continuationItemViewModel` tokens through the innertube browse
  /// API for large playlists (800+ entries).
  Future<List<Video>> _fetchPlaylistViaLockupParser(
      PlaylistId playlistId, int? cap, int expectedCount) async {
    final results = <Video>[];
    final client = HttpClient();
    try {
      client.userAgent =
          'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
      // --- Primary first page: Innertube browse API with browseId.
      // YouTube serves its EU/EEA "before you continue" consent interstitial
      // to the HTML /playlist page (a consent shell with no ytInitialData),
      // so HTML scraping returns 0 of ~800 entries on phones. The JSON
      // innertube browse API with a browseId is not subject to that wall and
      // returns the same lockupViewModel structures the continuation pages
      // already use - so we get the first page the same way we get the rest.
      _logs?.add('Lockup parser: fetching first page via browse API (browseId)');
      dynamic root =
          await _browseFirstPage(client, playlistId.value, null);
      // --- Fallback: legacy HTML scraping (works where the API is blocked).
      if (root == null) {
        _logs?.add(
            'Lockup parser: browse API returned no data; falling back to HTML scrape');
        final html = await _httpGetString(client,
            'https://www.youtube.com/playlist?list=${playlistId.value}&hl=en&persist_hl=1');
        root = _extractYtInitialData(html);
        if (root == null) {
          _logs?.add(
              'Lockup parser: ytInitialData not found in playlist HTML; retrying with consent params');
          final retryHtml = await _httpGetString(client,
              'https://www.youtube.com/playlist?list=${playlistId.value}&hl=en&persist_hl=1&has_verified=1&bpctr=9999999999');
          root = _extractYtInitialData(retryHtml);
          if (root == null) {
            _logs?.add(
                'Lockup parser: YouTube returned a consent/blocked page (no data). '
                'Check VPN/region or retry; cannot enumerate playlist entries.');
            return const [];
          }
        }
      }
      final visitorData = _digString(root, const [
        'responseContext',
        'webResponseContextExtensionData',
        'ytConfigData',
        'visitorData',
      ]);
      var page = 1;
      // 1000 pages x ~100 entries. Pagination ends on its own when YouTube runs
      // out of continuation tokens; this is only a runaway guard.
      const maxPages = 1000;
      final seenIds = <String>{};
      final spentTokens = <String>{};
      while (root != null && page <= maxPages) {
        var added = 0;
        for (final video in _videosFromPage(root)) {
          if (!seenIds.add(video.id.value)) continue;
          results.add(video);
          added++;
          if (cap != null && results.length >= cap) return results;
        }
        _logs?.add('Lockup parser page $page: +$added videos '
            '(total ${results.length})');
        if (cap != null && results.length >= cap) break;
        if (expectedCount > 0 && results.length >= expectedCount) break;
        final tokens = <String>[];
        _collectContinuationTokens(root, tokens);
        // Spend each token once. A response that repeats a token we already
        // used would otherwise loop forever re-fetching the same entries.
        String? next;
        for (final token in tokens) {
          if (spentTokens.add(token)) {
            next = token;
            break;
          }
        }
        if (next == null) {
          if (expectedCount > 0 && results.length < expectedCount) {
            _logs?.add('Lockup parser: no further continuation token after '
                '${results.length}/$expectedCount entries.');
          }
          break;
        }
        root = await _browseContinuation(client, next, visitorData);
        page++;
      }

      // The WEB client caps at ~200 entries on large playlists. If we came up
      // short, enumerate again with the YouTube Music client, which pages all
      // the way, and merge anything new in.
      if (cap == null && (expectedCount == 0 || results.length < expectedCount)) {
        final before = results.length;
        await _appendViaMusicClient(
            client, playlistId, seenIds, results, expectedCount);
        if (results.length > before) {
          _logs?.add('Music client added ${results.length - before} more '
              'entries (total ${results.length}).');
        }
      }
    } finally {
      client.close(force: true);
    }
    return results;
  }

  /// Enumerates [playlistId] with the WEB_REMIX client and appends every video
  /// not already in [results]. Used when the WEB client stops early.
  Future<void> _appendViaMusicClient(
      HttpClient client,
      PlaylistId playlistId,
      Set<String> seenIds,
      List<Video> results,
      int expectedCount) async {
    try {
      dynamic root = await _browseFirstPage(client, playlistId.value, null,
          clientContext: _musicClientContext);
      if (root == null) return;
      final visitorData = _digString(root, const [
        'responseContext',
        'webResponseContextExtensionData',
        'ytConfigData',
        'visitorData',
      ]);
      final spent = <String>{};
      var page = 1;
      const maxPages = 1000;
      while (root != null && page <= maxPages) {
        for (final video in _videosFromPage(root)) {
          if (!seenIds.add(video.id.value)) continue;
          results.add(video);
        }
        if (expectedCount > 0 && results.length >= expectedCount) break;
        final tokens = <String>[];
        _collectContinuationTokens(root, tokens);
        String? next;
        for (final token in tokens) {
          if (spent.add(token)) {
            next = token;
            break;
          }
        }
        if (next == null) break;
        root = await _browseContinuation(client, next, visitorData,
            clientContext: _musicClientContext);
        page++;
      }
    } catch (e) {
      _logs?.add('Music-client playlist pass failed: $e');
    }
  }

  /// Posts to the innertube `browse` API with a playlist [browseId]
  /// (`VL<playlistId>`) and returns the parsed JSON of the FIRST page, or null
  /// on any failure. Not subject to the HTML consent interstitial that breaks
  /// playlist scraping on EEA/mobile networks.
  /// Innertube client contexts.
  ///
  /// The plain WEB client stops handing out continuation tokens after two
  /// pages (200 entries) on large playlists - verified against an 863-entry
  /// playlist where page 2 comes back with no continuation item at all. The
  /// WEB_REMIX (YouTube Music) client pages the same playlist to the end, so
  /// it is used as the deep-pagination fallback.
  static const Map<String, dynamic> _webClientContext = {
    'clientName': 'WEB',
    'clientVersion': '2.20250101.00.00',
    'hl': 'en',
    'gl': 'US',
  };
  static const Map<String, dynamic> _musicClientContext = {
    'clientName': 'WEB_REMIX',
    'clientVersion': '1.20240724.00.00',
    'hl': 'en',
    'gl': 'US',
  };

  Future<dynamic> _browseFirstPage(
      HttpClient client, String playlistId, String? visitorData,
      {Map<String, dynamic> clientContext = _webClientContext}) async {
    final request = await client.postUrl(Uri.parse(
        'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'));
    request.headers.set('content-type', 'application/json');
    request.headers.set('accept', 'application/json');
    request.headers.set('accept-language', 'en-US,en;q=0.9');
    request.headers.set('cookie', 'SOCS=CAI');
    if (visitorData != null && visitorData.isNotEmpty) {
      request.headers.set('x-goog-visitor-id', visitorData);
    }
    request.write(jsonEncode({
      'context': {'client': clientContext},
      'browseId': 'VL$playlistId',
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Parses a YouTube playlist HTML page and returns the video titles/ids it
  /// contains in document order. Public solely so the Lockup parser can be
  /// verified against offline fixtures (no live YouTube needed) - the same
  /// pattern as [BrowserScreen.buildSearchUrl].
  static List<Video> parsePlaylistHtmlForTesting(String html) {
    final root = _extractYtInitialData(html);
    if (root == null) return const [];
    return _videosFromPage(root);
  }

  /// Returns the pagination tokens found in a YouTube playlist HTML page.
  /// Test-support hook mirroring [parsePlaylistHtmlForTesting].
  static List<String> continuationTokensForTesting(String html) {
    final root = _extractYtInitialData(html);
    if (root == null) return const [];
    final tokens = <String>[];
    _collectContinuationTokens(root, tokens);
    return tokens;
  }

  // -- Lockup parser helpers ------------------------------------------------

  /// GET [url] and return the body decoded as UTF-8 (follows redirects).
  Future<String> _httpGetString(HttpClient client, String url) async {
    final request = await client.getUrl(Uri.parse(url));
        request.headers.set('accept-language', 'en-US,en;q=0.9');
    request.headers.set(
        'accept', 'text/html,application/xhtml+xml,application/xml');
    // Bypasses YouTube's EU/UK "before you continue" cookie-consent
    // interstitial, which serves a consent page with no ytInitialData
    // instead of the playlist to any request made from an EEA-geolocated
    // IP that lacks this cookie. The old CONSENT cookie this used to take
    // is no longer honored; SOCS=CAI ("accept all") is the current bypass
    // - see https://github.com/yt-dlp/yt-dlp/issues/7774. The bpctr/
    // has_verified retry below predates this and targets a different,
    // now largely inactive bot-check page, so it stays as a harmless
    // second-chance fallback rather than the primary fix.
    request.headers.set('cookie', 'SOCS=CAI');
    final response = await request.close();
    return response.transform(utf8.decoder).join();
  }

  /// Post to the innertube `browse` API with a continuation token and return
  /// the parsed JSON response (or null on any failure).
  Future<dynamic> _browseContinuation(
      HttpClient client, String token, String? visitorData,
      {Map<String, dynamic> clientContext = _webClientContext}) async {
    final request = await client.postUrl(Uri.parse(
        'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'));
        request.headers.set('content-type', 'application/json');
    request.headers.set('accept', 'application/json');
    // Same EU consent-wall bypass as _httpGetString - continuation pages
    // are a separate request and need it too.
    request.headers.set('cookie', 'SOCS=CAI');
    if (visitorData != null && visitorData.isNotEmpty) {
      request.headers.set('x-goog-visitor-id', visitorData);
    }
    request.write(jsonEncode({
      'context': {'client': clientContext},
      'continuation': token,
    }));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Extracts the `ytInitialData` JSON object from a YouTube HTML page.
  /// Handles both `var ytInitialData = {...};` and
  /// `window["ytInitialData"] = {...};` embeds via brace matching so
  /// truncated/HTML-escaped surroundings can't break the parse.
  static dynamic _extractYtInitialData(String html) {
    const markerFull = 'var ytInitialData = ';
    const markerAlt = 'window["ytInitialData"] = ';
    var start = html.indexOf(markerFull);
    if (start < 0) start = html.indexOf(markerAlt);
    if (start < 0) return null;
    start = html.indexOf('{', start);
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < html.length; i++) {
      final ch = html[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          try {
            return jsonDecode(html.substring(start, i + 1));
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Walks [root] following [path] however it is nested - through maps,
  /// lists, or any combination - returning the first string found at the
  /// end of the walk, or null.
  static String? _digString(dynamic root, List<String> path) {
    dynamic node = root;
    for (final key in path) {
      node = _jsonNextKey(node, key);
      if (node == null) return null;
    }
    return node is String ? node : null;
  }

  /// Deep first-[key] value search across nested maps and lists.
  static dynamic _jsonNextKey(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final r = _jsonNextKey(v, key);
        if (r != null) return r;
      }
      return null;
    }
    if (node is List) {
      for (final item in node) {
        final r = _jsonNextKey(item, key);
        if (r != null) return r;
      }
      return null;
    }
    return null;
  }

  /// Collects every `lockupViewModel` whose contentType is a video, in
  /// document order. Position-independent: does not depend on wrapper
  /// renderer names, so it survives YouTube reshuffling its containers.
  static void _collectVideoLockups(dynamic node, List<Map<String, dynamic>> out) {
    if (node is Map) {
      final lockup = node['lockupViewModel'];
      if (lockup is Map &&
          lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
        out.add(lockup.cast<String, dynamic>());
      }
      for (final entry in node.entries) {
        if (entry.key == 'lockupViewModel') continue;
        _collectVideoLockups(entry.value, out);
      }
    } else if (node is List) {
      for (final item in node) {
        _collectVideoLockups(item, out);
      }
    }
  }
/// Collects every continuation token for pagination.
  /// Collects the "next page" tokens from a playlist page or a continuation
  /// response.
  ///
  /// YouTube ships this marker in more than one shape and switches between
  /// them without notice:
  ///   * `continuationItemViewModel.continuationViewModel.continuation`
  ///   * `continuationItemRenderer.continuationEndpoint.continuationCommand.token`
  ///   * a bare `continuationCommand.token`
  /// Only the first was recognised before, so a playlist whose page used the
  /// renderer shape stopped dead after the first page - that is the "playlists
  /// only load 100 videos" bug on Android, which has no yt-dlp fallback.
  static void _collectContinuationTokens(dynamic node, List<String> out) {
    if (node is Map) {
      for (final path in const [
        ['continuationItemViewModel', 'continuationViewModel', 'continuation'],
        [
          'continuationItemRenderer',
          'continuationEndpoint',
          'continuationCommand',
          'token'
        ],
        ['continuationCommand', 'token'],
        ['continuationEndpoint', 'continuationCommand', 'token'],
      ]) {
        final token = _digString(node, path);
        if (token != null && token.isNotEmpty && !out.contains(token)) {
          out.add(token);
        }
      }
      for (final entry in node.entries) {
        if (entry.key == 'continuationItemViewModel' ||
            entry.key == 'continuationItemRenderer' ||
            entry.key == 'continuationCommand') {
          continue;
        }
        _collectContinuationTokens(entry.value, out);
      }
    } else if (node is List) {
      for (final item in node) {
        _collectContinuationTokens(item, out);
      }
    }
  }

  /// Every video on one page, in document order, whichever item shape YouTube
  /// used. Continuation pages often fall back to the classic
  /// `playlistVideoRenderer` even when page 1 used the new `lockupViewModel`.
  static List<Video> _videosFromPage(dynamic root) {
    final videos = <Video>[];
    final lockups = <Map<String, dynamic>>[];
    _collectVideoLockups(root, lockups);
    for (final lockup in lockups) {
      final video = _videoFromLockup(lockup);
      if (video != null) videos.add(video);
    }
    final renderers = <Map<String, dynamic>>[];
    _collectPlaylistVideoRenderers(root, renderers);
    for (final renderer in renderers) {
      final video = _videoFromPlaylistRenderer(renderer);
      if (video != null) videos.add(video);
    }
    final musicItems = <Map<String, dynamic>>[];
    _collectMusicItems(root, musicItems);
    for (final item in musicItems) {
      final video = _videoFromMusicItem(item);
      if (video != null) videos.add(video);
    }
    return videos;
  }

  static void _collectPlaylistVideoRenderers(
      dynamic node, List<Map<String, dynamic>> out) {
    if (node is Map) {
      final renderer = node['playlistVideoRenderer'];
      if (renderer is Map) out.add(renderer.cast<String, dynamic>());
      for (final entry in node.entries) {
        if (entry.key == 'playlistVideoRenderer') continue;
        _collectPlaylistVideoRenderers(entry.value, out);
      }
    } else if (node is List) {
      for (final item in node) {
        _collectPlaylistVideoRenderers(item, out);
      }
    }
  }

  /// Builds a [Video] from the classic `playlistVideoRenderer` shape.
  static Video? _videoFromPlaylistRenderer(Map<String, dynamic> renderer) {
    try {
      final videoIdRaw = (renderer['videoId'] ?? '').toString().trim();
      if (videoIdRaw.length != 11) return null;
      final title = _rendererText(renderer['title']);
      if (title == null || title.isEmpty) return null;
      var author = _rendererText(renderer['shortBylineText']) ??
          _rendererText(renderer['longBylineText']) ??
          _rendererText(renderer['ownerText']);
      if (author != null && author.startsWith('@')) {
        author = author.substring(1);
      }
      Duration? duration;
      final seconds =
          int.tryParse((renderer['lengthSeconds'] ?? '').toString().trim());
      if (seconds != null && seconds > 0) {
        duration = Duration(seconds: seconds);
      } else {
        duration = _parseDurationText(_rendererText(renderer['lengthText']));
      }
      // _digString searches recursively, so this finds browseId nested under
      // runs[0].navigationEndpoint.browseEndpoint without naming each hop.
      final channelIdStr =
          _digString(renderer, const ['shortBylineText', 'browseId']) ?? '';
      final channelId =
          (channelIdStr.startsWith('UC') && channelIdStr.length == 24)
              ? ChannelId(channelIdStr)
              : ChannelId('UCdddddddddddddddddddddd');
      return Video(
        VideoId(videoIdRaw),
        title,
        author ?? '',
        channelId,
        null,
        null,
        null,
        '',
        duration,
        ThumbnailSet(videoIdRaw),
        null,
        const Engagement(0, null, null),
        false,
      );
    } catch (_) {
      return null;
    }
  }

  static void _collectMusicItems(
      dynamic node, List<Map<String, dynamic>> out) {
    if (node is Map) {
      final item = node['musicResponsiveListItemRenderer'];
      if (item is Map) out.add(item.cast<String, dynamic>());
      for (final entry in node.entries) {
        if (entry.key == 'musicResponsiveListItemRenderer') continue;
        _collectMusicItems(entry.value, out);
      }
    } else if (node is List) {
      for (final item in node) {
        _collectMusicItems(item, out);
      }
    }
  }

  /// Text of one `flexColumns` / `fixedColumns` entry.
  static String? _musicColumnText(dynamic column) {
    if (column is! Map) return null;
    for (final key in const [
      'musicResponsiveListItemFlexColumnRenderer',
      'musicResponsiveListItemFixedColumnRenderer',
    ]) {
      final renderer = column[key];
      if (renderer is Map) {
        final text = _rendererText(renderer['text']);
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return null;
  }

  /// Builds a [Video] from a YouTube Music `musicResponsiveListItemRenderer`:
  /// title in flexColumns[0], artist in flexColumns[1], duration in
  /// fixedColumns[0].
  static Video? _videoFromMusicItem(Map<String, dynamic> item) {
    try {
      final videoIdRaw =
          (_digString(item, const ['playlistItemData', 'videoId']) ??
                  _digString(item, const ['watchEndpoint', 'videoId']) ??
                  '')
              .trim();
      if (videoIdRaw.length != 11) return null;

      final flex = item['flexColumns'];
      String? title;
      String? author;
      if (flex is List && flex.isNotEmpty) {
        title = _musicColumnText(flex[0]);
        if (flex.length > 1) author = _musicColumnText(flex[1]);
      }
      if (title == null || title.isEmpty) return null;
      if (author != null && author.startsWith('@')) {
        author = author.substring(1);
      }

      Duration? duration;
      final fixed = item['fixedColumns'];
      if (fixed is List && fixed.isNotEmpty) {
        duration = _parseDurationText(_musicColumnText(fixed[0]));
      }

      // Scoped to the artist column on purpose: a bare recursive search for
      // browseId would just as happily return an album or menu-entry id.
      final channelIdStr = (flex is List && flex.length > 1)
          ? (_digString(flex[1], const ['browseEndpoint', 'browseId']) ?? '')
          : '';
      final channelId =
          (channelIdStr.startsWith('UC') && channelIdStr.length == 24)
              ? ChannelId(channelIdStr)
              : ChannelId('UCdddddddddddddddddddddd');

      return Video(
        VideoId(videoIdRaw),
        title,
        author ?? '',
        channelId,
        null,
        null,
        null,
        '',
        duration,
        ThumbnailSet(videoIdRaw),
        null,
        const Engagement(0, null, null),
        false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads YouTube's `{runs:[{text:..}]}` / `{simpleText:..}` text shapes.
  static String? _rendererText(dynamic node) {
    if (node is String) return node;
    if (node is! Map) return null;
    final simple = node['simpleText'];
    if (simple is String && simple.isNotEmpty) return simple;
    final runs = node['runs'];
    if (runs is List) {
      final buffer = StringBuffer();
      for (final run in runs) {
        if (run is Map && run['text'] is String) buffer.write(run['text']);
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// Builds a [Video] from a video lockupViewModel, tolerating the several
  /// naming layouts YouTube has shipped for title/author/duration/thumbnail.
  static Video? _videoFromLockup(Map<String, dynamic> lockup) {
    try {
      dynamic content = lockup['content'];
      if (content is! Map) content = lockup;
      final videoIdRaw = (content['contentId'] ??
              lockup['contentId'] ??
              content['videoId'] ??
              '')
          .toString()
          .trim();
      if (videoIdRaw.length != 11) {
        return null;
      }
      final videoId = VideoId(videoIdRaw);
      // Title: try the real YouTube structure first
      // (metadata.lockupMetadataViewModel.title.content), then fall back to
      // older/alternate layouts.
      var title = _digString(
          content, const ['metadata', 'lockupMetadataViewModel', 'title', 'content']);
      if (title == null || title.isEmpty) {
        title = _digString(content, const ['metadata', 'title', 'content']);
      }
      if (title == null || title.isEmpty) {
        title = _digString(content, const ['title', 'content']);
      }
      if (title == null || title.isEmpty) {
        title = _digString(content, const ['title']);
      }
      if (title == null || title.isEmpty) return null;
      // Author: try the real YouTube structure first
      // (metadata.contentMetadataViewModel.metadataRows[0].metadataParts[0].text.content),
      // then fall back to older/alternate layouts.
      var author = _extractAuthorFromContentMetadata(content);
      if (author == null || author.isEmpty) {
        author = _digString(content, const ['channelName', 'content']);
      }
      if (author == null || author.isEmpty) {
        author =
            _digString(content, const ['metadata', 'secondaryText', 'content']);
      }
      if (author == null || author.isEmpty) {
        author = _digString(content, const ['secondaryText', 'content']);
      }
      if (author != null && author.startsWith('@')) {
        author = author.substring(1);
      }
      // Duration: try the real YouTube structure first, then fall back.
      var durationText =
          _digString(content, const ['metadata', 'thirdText', 'content']);
      if (durationText == null || durationText.isEmpty) {
        durationText = _digString(content, const ['viewText', 'content']);
      }
      final duration = _parseDurationText(durationText);
      final channelIdStr = _digString(content, const ['channelId']) ?? '';
      // ChannelId() throws on ids that do not match the strict UC+24 format
      // (most lockup payloads omit channelId entirely). Fall back to a
      // well-formed placeholder so a missing/malformed channel id cannot
      // cause the whole video to be dropped.
      final channelId = (channelIdStr.isNotEmpty &&
              channelIdStr.startsWith('UC') &&
              channelIdStr.length == 24)
          ? ChannelId(channelIdStr)
          : ChannelId('UCdddddddddddddddddddddd');
      return Video(
        videoId,
        title,
        author ?? '',
        channelId,
        null,
        null,
        null,
        '',
        duration,
        ThumbnailSet(videoIdRaw),
        null,
        const Engagement(0, null, null),
        false,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts the author/channel name from the contentMetadataViewModel
  /// structure that YouTube uses in the new lockupViewModel format:
  /// metadata.contentMetadataViewModel.metadataRows[N].metadataParts[M].text.content
  static String? _extractAuthorFromContentMetadata(dynamic content) {
    try {
      final metadata = content is Map ? content['metadata'] : null;
      if (metadata is! Map) return null;
      final contentMetadata = metadata['contentMetadataViewModel'];
      if (contentMetadata is! Map) return null;
      final rows = contentMetadata['metadataRows'];
      if (rows is! List || rows.isEmpty) return null;
      // The author is typically in the first row, first part.
      for (final row in rows) {
        if (row is! Map) continue;
        final parts = row['metadataParts'];
        if (parts is! List || parts.isEmpty) continue;
        for (final part in parts) {
          if (part is! Map) continue;
          final text = part['text'];
          if (text is Map && text['content'] is String) {
            final candidate = text['content'] as String;
            if (candidate.isNotEmpty) return candidate;
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parses "4:05" / "1:02:03" style duration strings. Returns null for
  /// anything non-numeric (e.g. "LIVE").
  static Duration? _parseDurationText(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final parts = text.trim().split(':');
    if (parts.length < 2) return null;
    var seconds = 0;
    for (final part in parts) {
      final n = int.tryParse(part.trim());
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return Duration(seconds: seconds);
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
    final stderrText = await process.stderr.transform(utf8.decoder).join();
    if (stderrText.trim().isNotEmpty) {
      _logs?.add('yt-dlp count stderr: $stderrText');
    }
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      _logs?.add('yt-dlp count exited with code $exitCode');
      return null;
    }
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
      final stderrText = await process.stderr.transform(utf8.decoder).join();
      if (stderrText.trim().isNotEmpty) {
        _logs?.add('yt-dlp tracks stderr (chunk $start-$end): $stderrText');
      }
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        _logs?.add('yt-dlp tracks chunk $start-$end exited with code $exitCode');
        break;
      }

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
  ///
  /// Uses fallback API clients because the default [androidSdkless] client
  /// frequently returns empty manifests on mobile.
  Future<String> getAudioUrl(String videoId) async {
    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 15));
      if (manifest.streams.isEmpty) throw Exception('empty manifest');
    } catch (_) {
      manifest = await _yt.videos.streamsClient
          .getManifest(videoId, ytClients: [
        YoutubeApiClient.safari,
        YoutubeApiClient.androidVr,
        YoutubeApiClient.tv
      ]).timeout(const Duration(seconds: 30));
    }
    // Prefer audio-only (saves bandwidth), fall back to muxed
    final stream = manifest.audioOnly.isNotEmpty
        ? manifest.audioOnly.withHighestBitrate()
        : manifest.muxed.withHighestBitrate();
    return stream.url.toString();
  }

  // --─ M3U generation ------------------------------------------------------

  /// An M3U that lists each track under the name the app downloads it as.
  String buildM3U(List<SearchResult> tracks, {String format = 'mp3'}) {
    final ext = format.toLowerCase();
    final buf = StringBuffer('#EXTM3U\n');
    for (final track in tracks) {
      buf.writeln(
          '#EXTINF:${track.duration.inSeconds},${track.artist} - ${track.title}');
      buf.writeln('${track.artist}/${track.title}.$ext');
    }
    return buf.toString();
  }

  /// An M3U with the real local file of every matched track, so it plays
  /// straight away when a playlist has been compared against a folder.
  String buildM3UFromMatches(List<TrackMatch> matches) {
    final buf = StringBuffer('#EXTM3U\n');
    for (final m in matches) {
      buf.writeln(
          '#EXTINF:${m.track.duration.inSeconds},${m.track.artist} - ${m.track.title}');
      buf.writeln(m.filePath);
    }
    return buf.toString();
  }

  /// Track names, one per line.
  String buildTrackList(List<SearchResult> tracks, {bool includeArtist = true}) {
    final buf = StringBuffer();
    for (final t in tracks) {
      buf.writeln(includeArtist ? '${t.artist} - ${t.title}' : t.title);
    }
    return buf.toString();
  }

  // --─ Smart playlist ↔ folder comparison -----------------------------------

  /// Scans [folderPath] recursively and cross-references every playlist track
  /// against the files found.  Uses multi-strategy fuzzy matching so renamed,
  /// reformatted, or differently-cased files are still recognised.
  ///
  /// Unlike the prior audio-only scan, [compareToFolder] now indexes **every**
  /// file (including video/container files such as `.mp4`/`.webm`) so the Extras
  /// tab can surface incomplete downloads (files whose name contains the
  /// `.temp.` infix) and wrong-format files alongside genuinely untracked media.
  Future<PlaylistFolderComparison> compareToFolder(
    List<SearchResult> playlistTracks,
    String folderPath, {
    double matchThreshold = 0.55,
    bool recursive = true,
  }) async {
    // -- 1. Index every file in the folder ---------------------------------
    // Composite of a broad "media-like" set (audio + video containers that
    // the app can download) plus a wide generic catch-all.  An extension that
    // is not in either set is still indexed so temp files and weird one-offs
    // are visible to the extras tab; only truly metadata-unreadable files are
    // skipped at the metadata layer, not at the scan layer.
    final mediaExtensions = <String>{
      '.mp3',
      '.flac',
      '.m4a',
      '.opus',
      '.ogg',
      '.wav',
      '.aac',
      '.wma',
      '.webm', // audio-only webm / video webm both appear here
    };
    final videoContainerExtensions = <String>{
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.wmv',
      '.m4v',
    };
    final indexedExtensions = mediaExtensions.union(videoContainerExtensions);

    final localFiles = <_LocalFile>[];

    // Files with no extension or only a temp infix (no real ext) are still
    // indexed so they can be flagged as incomplete downloads.
    bool indexed(String ext) =>
        indexedExtensions.contains(ext) ||
        _partialExtensions.contains(ext) ||
        ext.isEmpty;

    if (folderPath.startsWith('content://')) {
      // An Android folder from the system picker is a SAF tree, not a path:
      // Directory() cannot see it, which used to make Compare report every
      // track as missing on phones. The native side lists the tree instead.
      // Matching uses file names; tags would need every file copied out
      // first, and the app names its downloads "Artist - Title" anyway.
      final entries = await listSafTree(folderPath);
      for (final entry in entries) {
        final uri = entry['uri'] ?? '';
        final name = entry['name'] ?? '';
        if (uri.isEmpty || name.isEmpty) continue;
        final ext = _extensionOf(name).toLowerCase();
        if (!indexed(ext)) continue;
        localFiles.add(_localFileFor(
          path: uri,
          fileName: _fileNameWithoutExt(name),
          metadataLabels: const [],
          extension: ext.isEmpty ? _guessTempExt(name) : ext,
        ));
      }
    } else {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        throw PlaylistCompareException(
            'That folder does not exist: $folderPath');
      }
      // An unreadable subfolder (Android/data, a system folder on a USB
      // drive) is an error event on the listing stream; skip it rather than
      // abandoning the whole scan.
      final listing = dir
          .list(recursive: recursive, followLinks: false)
          .handleError((Object e) => debugPrint('[Compare] skipped: $e'));
      await for (final entity in listing) {
        if (entity is! File) continue;
        final path = entity.path;
        final ext = _extensionOf(path).toLowerCase();
        if (!indexed(ext)) continue;

        final metadataLabels =
            await _labelsFromMetadata(path, ext.isEmpty ? '.bin' : ext);
        localFiles.add(_localFileFor(
          path: path,
          fileName: _fileNameWithoutExt(path),
          metadataLabels: metadataLabels,
          extension: ext.isEmpty ? _guessTempExt(path) : ext,
        ));
      }
    }

    return _matchInBackground(
      playlistTracks,
      localFiles,
      folderPath: folderPath,
      threshold: matchThreshold,
      mediaExtensions: mediaExtensions,
    );
  }

  /// Track × file pairs above which matching runs on a background isolate,
  /// so comparing a big playlist with a big folder does not freeze the
  /// screen. Small compares stay inline, where an isolate costs more than it
  /// saves.
  static const int _backgroundMatchPairs = 20000;

  // Static, so the isolate closure cannot capture the service (whose HTTP
  // client could not be sent to another isolate).
  static Future<PlaylistFolderComparison> _matchInBackground(
    List<SearchResult> playlistTracks,
    List<_LocalFile> localFiles, {
    required String folderPath,
    required double threshold,
    required Set<String> mediaExtensions,
  }) async {
    PlaylistFolderComparison run() => _matchAndCategorise(
          playlistTracks,
          localFiles,
          folderPath: folderPath,
          threshold: threshold,
          mediaExtensions: mediaExtensions,
        );
    if (!kIsWeb &&
        playlistTracks.length * localFiles.length > _backgroundMatchPairs) {
      return Isolate.run(run);
    }
    return run();
  }

  static PlaylistFolderComparison _matchAndCategorise(
    List<SearchResult> playlistTracks,
    List<_LocalFile> localFiles, {
    required String folderPath,
    required double threshold,
    required Set<String> mediaExtensions,
  }) {
    final matchThreshold = threshold;
    // Every label's normalised form, pointing at its files, so a file named
    // exactly like the track (every file this app downloads) is found without
    // scanning the folder.
    final exactIndex = <String, List<int>>{};
    for (var i = 0; i < localFiles.length; i++) {
      final f = localFiles[i];
      if (f.incomplete) continue;
      for (final forms in f.labelForms) {
        if (forms.agg.isEmpty) continue;
        (exactIndex[forms.agg] ??= <int>[]).add(i);
      }
    }

    // -- 2. Match each playlist track to the best local file ----------------
    final usedFileIndices = <int>{};
    final matched = <TrackMatch>[];
    final missing = <SearchResult>[];

    for (final track in playlistTracks) {
      final result = _findBestMatch(
          track, localFiles, usedFileIndices, matchThreshold, exactIndex);
      if (result != null) {
        matched.add(result);
        usedFileIndices.add(result._fileIndex);
      } else {
        missing.add(track);
      }
    }

    // -- 3. Determine the dominant extension among MATCHED files ------------
    // Used to decide whether an extra file is "wrong format" vs "not in
    // playlist".  Audio extensions are preferred over video containers so a
    // folder that mixes `.mp3` + `.mp4` still reports `.mp3` as dominant.
    // Basing this on the playlist's own matched files keeps categorisation
    // stable in mixed-format folders the playlist doesn't reference.
    final matchedFiles = matched.map((m) => localFiles[m._fileIndex]).toList();
    final dominantExtension = _dominantExtension(matchedFiles, mediaExtensions);

    // -- 4. Categorise extra files not in the playlist ----------------------
    final extras = <ExtraFile>[];
    for (var i = 0; i < localFiles.length; i++) {
      if (usedFileIndices.contains(i)) continue;
      final f = localFiles[i];

      // Incomplete download: the file name carries the app's in-progress temp
      // infix (e.g. `Song Name.temp.mp4`, `Song Name.temp.webm`,
      // `Song Name.temp.video.mp4`, `Song Name.temp.audio.opus`).
      if (f.incomplete) {
        extras.add(ExtraFile(
          filePath: f.path,
          fileName: f.baseName,
          extension: f.extension,
          kind: PlaylistExtraKind.incompleteDownload,
        ));
        continue;
      }

      // Wrong format: the file has a recognised media/container extension but
      // it differs from the folder's dominant extension.
      if (dominantExtension.isNotEmpty &&
          f.extension.isNotEmpty &&
          f.extension != dominantExtension) {
        extras.add(ExtraFile(
          filePath: f.path,
          fileName: f.baseName,
          extension: f.extension,
          kind: PlaylistExtraKind.wrongFormat,
        ));
        continue;
      }

      // Not in playlist: matched format (or extensionless temp file, or a
      // genuinely weird file) that the playlist doesn't reference.
      extras.add(ExtraFile(
        filePath: f.path,
        fileName: f.baseName,
        extension: f.extension,
        kind: PlaylistExtraKind.notInPlaylist,
      ));
    }

    return PlaylistFolderComparison(
      total: playlistTracks.length,
      matched: matched,
      missing: missing,
      extras: extras,
      folderPath: folderPath,
      filesScanned: localFiles.length,
    );
  }

  /// Lists every file under an Android SAF tree as `uri`/`name` maps.
  /// Replaced in tests, which have no platform channel.
  @visibleForTesting
  static Future<List<Map<String, String>>> Function(String treeUri)
      listSafTree = PlatformDirs.listTree;

  static _LocalFile _localFileFor({
    required String path,
    required String fileName,
    required List<String> metadataLabels,
    required String extension,
  }) {
    final labels = <String>[fileName, ...metadataLabels];
    return _LocalFile(
      path: path,
      baseName: fileName,
      labels: labels,
      labelForms: [for (final label in labels) _TitleForms(label)],
      normalised: _normalise(fileName),
      tokens: {
        ..._tokenise(fileName),
        ...labels.expand(_tokenise),
      },
      extension: extension,
      incomplete: _isIncompleteDownload(fileName, extension),
    );
  }

  // --─ Matching engine ----------------------------------------------------─

  /// Tries multiple strategies (exact, normalised, token overlap, fuzzy) and
  /// returns the best match above [threshold], or null.
  ///
  /// Every normalised form of a file's labels is worked out once, when the
  /// folder is indexed, not once per track: a playlist of a thousand songs
  /// against a folder of a thousand files is a million comparisons.
  static TrackMatch? _findBestMatch(
    SearchResult track,
    List<_LocalFile> files,
    Set<int> usedIndices,
    double threshold,
    Map<String, List<int>> exactIndex,
  ) {
    final titleForms = _TitleForms(track.title);
    final fullForms = _TitleForms('${track.artist} ${track.title}');
    final artistNorm = _aggressiveNorm(_plainArtist(track.artist));

    TrackMatch exact(int i) => TrackMatch(
          track: track,
          filePath: files[i].path,
          fileName: files[i].baseName,
          confidence: 1.0,
          method: MatchMethod.exact,
          fileIndex: i,
        );

    // The file is named exactly like the track.
    for (final key in [titleForms.agg, fullForms.agg]) {
      for (final i in exactIndex[key] ?? const <int>[]) {
        if (!usedIndices.contains(i)) return exact(i);
      }
    }

    final trackTitle = titleForms.plain;
    final trackArtist = _normalise(track.artist);
    final trackFull = fullForms.plain;
    final trackTokens = {..._tokenise(track.title), ..._tokenise(track.artist)};
    // Remove extremely common words that hurt matching accuracy
    trackTokens.removeAll(_stopWords);

    int bestIndex = -1;
    double bestScore = 0;
    MatchMethod bestMethod = MatchMethod.fuzzy;

    for (var i = 0; i < files.length; i++) {
      if (usedIndices.contains(i)) continue;
      final f = files[i];
      if (f.incomplete) continue;

      for (final forms in f.labelForms) {
        if (_formsMatch(titleForms, forms, artistNorm) ||
            _formsMatch(fullForms, forms, artistNorm)) {
          return exact(i);
        }

        final normalisedLabel = forms.plain;
        // A label that is nothing but noise ("(Official Video)") normalises
        // to an empty string, which every title "contains".
        if (normalisedLabel.length < 2) continue;

        // Strategy 1 - exact normalised match
        if (normalisedLabel == trackFull ||
            (trackTitle.isNotEmpty && normalisedLabel == trackTitle)) {
          return exact(i);
        }

        // Strategy 2 - normalised containment (either direction), on word
        // boundaries so "love" is not found inside "glove"
        if (trackTitle.length >= 3 &&
            (_containsPhrase(normalisedLabel, trackTitle) ||
                _containsPhrase(trackTitle, normalisedLabel))) {
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
            trackTitle.isNotEmpty &&
            _containsPhrase(normalisedLabel, trackArtist) &&
            _containsPhrase(normalisedLabel, trackTitle)) {
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
          var intersection = 0;
          for (final token in trackTokens) {
            if (f.tokens.contains(token)) intersection++;
          }
          final union = trackTokens.length + f.tokens.length - intersection;
          final jaccard = intersection / union;
          if (jaccard > bestScore) {
            bestScore = jaccard;
            bestIndex = i;
            bestMethod = MatchMethod.tokenOverlap;
          }
        }

        // Strategy 5 - Levenshtein-based similarity. The length difference
        // alone caps the score it can reach; skip the expensive part when
        // that cap cannot beat what is already found.
        final la = trackFull.length, lb = normalisedLabel.length;
        final longest = max(la, lb);
        if (longest == 0) continue;
        final cap = 1.0 - (la - lb).abs() / longest;
        if (cap <= bestScore || cap < threshold) continue;
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

  /// Whether two titles name the same song closely enough to call it an
  /// exact match (confidence 100%).
  ///
  /// This used to accept almost any pair: each title's own full text was one
  /// of its "segments", so `a.contains(segment)` compared a title with itself,
  /// and "Northern Lights" matched "Glass Harbour.mp3". Compare then paired
  /// tracks with whatever files were left over and reported them as present.
  /// Anything short of the strict rules below now goes to the scored
  /// strategies in [_findBestMatch], whose confidence the Matched tab shows
  /// and flags for review.
  static bool _formsMatch(_TitleForms a, _TitleForms b, String artistNorm) {
    if (a.agg.isEmpty || b.agg.isEmpty) return false;
    if (a.agg == b.agg) return true;

    bool meaningful(String s) => s.runes.length >= 4 && s != artistNorm;
    // Words that may surround a title without making it another song: the
    // uploader, whatever sits in either title's artist slot, and video noise.
    bool decoration(String w) =>
        _decorationWords.contains(w) ||
        a.artistSlotWords.contains(w) ||
        b.artistSlotWords.contains(w) ||
        (artistNorm.isNotEmpty && _containsPhrase(artistNorm, w));

    // One side is the other plus decoration: "Artist - Title (Official
    // Video)" against "Title", or a file name cut at the length limit. A
    // short phrase only counts when everything around it is the artist or
    // video noise, so "Love" does not claim "Love Story".
    bool decoratedBy(String container, String phrase) {
      if (!meaningful(phrase) || !_containsPhrase(container, phrase)) {
        return false;
      }
      if (phrase.split(' ').length >= 3 || phrase.runes.length >= 15) {
        return true;
      }
      final rest = ' $container '.replaceFirst(' $phrase ', ' ').trim();
      return rest.isEmpty || rest.split(' ').every(decoration);
    }

    if (decoratedBy(a.agg, b.agg) || decoratedBy(b.agg, a.agg)) return true;

    // The song part agrees: "Artist - Title" against "Other - Title", or
    // "Title / Artist" (a common Japanese layout) against "Title". Only the
    // parts where the song name sits are compared, never the artist slot, so
    // two different songs by one artist do not match each other.
    for (final song in a.songs) {
      if (!meaningful(song)) continue;
      if (b.songs.contains(song) || decoratedBy(b.agg, song)) return true;
    }
    for (final song in b.songs) {
      if (meaningful(song) && decoratedBy(a.agg, song)) return true;
    }

    // Scripts written without spaces (Japanese, Chinese, Korean titles) have
    // no words to compare, so character pairs stand in for them there.
    if (a.cjk && _bigramSimilarity(a.agg, b.agg) >= 0.5) return true;

    return false;
  }

  /// Words that decorate a title without changing which song it is.
  static const Set<String> _decorationWords = {
    'official',
    'video',
    'audio',
    'music',
    'lyric',
    'lyrics',
    'mv',
    'hd',
    'hq',
    '4k',
    '1080p',
    'visualizer',
    'visualiser',
    'topic',
    'vevo',
    'clip',
    'officiel',
  };

  /// Channel names carry noise the artist's name does not: "Artist - Topic",
  /// "ArtistVEVO", "Artist Official".
  static String _plainArtist(String artist) => artist
      .replaceAll(RegExp(r'\s*-\s*topic\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'vevo$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\bofficial\b', caseSensitive: false), '')
      .trim();

  /// The parts of a title where the artist usually sits: before the first
  /// " - " and after the last " / ".
  static Iterable<String> _artistParts(String input) sync* {
    final dashed = input.split(' - ');
    if (dashed.length >= 2) yield _aggressiveNorm(dashed.first);
    final slashed = input.split(RegExp(r'\s+/\s+|／'));
    if (slashed.length >= 2) yield _aggressiveNorm(slashed.last);
  }

  static bool _containsPhrase(String container, String phrase) =>
      phrase.isNotEmpty && ' $container '.contains(' $phrase ');

  static bool _hasCjk(String s) => RegExp(
          r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]')
      .hasMatch(s);

  /// The parts of a title where the song name sits: after the first " - "
  /// ("Artist - Title - Remastered") and before the last " / " ("Title /
  /// Artist"). Noise such as "(Official Video)" is stripped.
  static Iterable<String> _songParts(String input) sync* {
    final dashed = input.split(' - ');
    if (dashed.length >= 2) {
      for (final part in dashed.skip(1)) {
        final norm = _normalise(part);
        if (norm.isNotEmpty) yield norm;
      }
    }
    final slashed = input.split(RegExp(r'\s+/\s+|／'));
    if (slashed.length >= 2) {
      for (final part in slashed.take(slashed.length - 1)) {
        final norm = _normalise(part);
        if (norm.isNotEmpty) yield norm;
      }
    }
  }

  static double _bigramSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    Set<String> bigrams(String s) {
      if (s.length < 2) return {s};
      return {for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2)};
    }
    final ba = bigrams(a), bb = bigrams(b);
    final overlap = ba.intersection(bb).length;
    return (2 * overlap) / (ba.length + bb.length);
  }

  // Punctuation becomes a word break, so "YOASOBI「夜に駆ける」Official"
  // keeps its words apart; apostrophes vanish, so "Don't" and "Dont" agree.
  static String _aggressiveNorm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\.\w{2,5}$'), '')
      .replaceAll(RegExp(r'\s*\[[a-zA-Z0-9_\-]{11}\]'), '')
      .replaceAll(RegExp("['’`]"), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
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
    // Whole words only: "shadow" and "birthday" keep their letters.
    s = s.replaceAll(
        RegExp(r'\b(hd|hq|4k|1080p)\b', caseSensitive: false), '');
    // Keep Unicode letters and digits so non-English titles still match;
    // other punctuation separates words, as in [_aggressiveNorm].
    s = s.replaceAll(RegExp("['’`]"), '');
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
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
    // Code units and two reusable rows: the old version built a list for
    // every cell and a one-character string for every comparison.
    final ca = a.codeUnits, cb = b.codeUnits;
    final lb = cb.length;
    var prev = Int32List(lb + 1);
    var curr = Int32List(lb + 1);
    for (var j = 0; j <= lb; j++) {
      prev[j] = j;
    }
    for (var i = 1; i <= ca.length; i++) {
      curr[0] = i;
      final ai = ca[i - 1];
      for (var j = 1; j <= lb; j++) {
        final substitution = prev[j - 1] + (ai == cb[j - 1] ? 0 : 1);
        final deletion = prev[j] + 1;
        final insertion = curr[j - 1] + 1;
        var best = substitution < deletion ? substitution : deletion;
        if (insertion < best) best = insertion;
        curr[j] = best;
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }

  // --─ Extra-file categorisation helpers ---------------------------------─

  /// Recognises an incomplete download: the name carries the app's `.temp.`
  /// infix used for in-progress downloads (e.g. `Song.temp.mp4`,
  /// `Song.temp.webm`, `Song.temp.video.mp4`, `Song.temp.audio.opus`).
  /// Partial files from a download that has not finished: the app's own
  /// `Song.temp.mp4` / `Song.temp.audio.opus`, and yt-dlp's `.part` files.
  static bool _isIncompleteDownload(String fileName, String extension) {
    final name = fileName.toLowerCase();
    return name.contains('.temp.') ||
        name.endsWith('.temp') ||
        extension.contains('.temp.') ||
        _partialExtensions.contains(extension);
  }

  static const Set<String> _partialExtensions = {'.part', '.temp', '.ytdl'};

  /// Picks the dominant (most common) extension among [files]. Audio media
  /// extensions are preferred over video containers so a folder mixing e.g.
  /// `.mp3` + `.mp4` still reports `.mp3` as dominant; within the same family
  /// the most frequent extension wins. Returns '' when nothing usable exists.
  static String _dominantExtension(
    List<_LocalFile> files,
    Set<String> preferred,
  ) {
    final counts = <String, int>{};
    for (final f in files) {
      if (f.extension.isEmpty) continue;
      counts[f.extension] = (counts[f.extension] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';

    String best = '';
    var bestCount = 0;
    for (final entry in counts.entries) {
      final isBetter = best.isEmpty ||
          entry.value > bestCount ||
          // Same count: prefer a "preferred" (audio) extension over secondary.
          (entry.value == bestCount &&
              preferred.contains(entry.key) &&
              !preferred.contains(best));
      if (isBetter) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  /// For extensionless temp files, recover a display extension from the
  /// `.temp.<ext>` infix so the Extras tab can label them accurately.
  static String _guessTempExt(String path) {
    final lower = path.toLowerCase();
    final idx = lower.lastIndexOf('.temp.');
    if (idx >= 0) {
      final after = lower.substring(idx + 6);
      final dot = after.lastIndexOf('.');
      if (dot >= 0) return after.substring(dot);
      if (after.isNotEmpty) return '.$after';
    }
    return '';
  }
}

// ══════════════════════════════════════════════════════════════════════════════╁E
// Data classes
// ══════════════════════════════════════════════════════════════════════════════╁E

/// Internal helper for indexing local files.
/// Every normalised form a title is compared in, worked out once.
class _TitleForms {
  _TitleForms(String raw)
      : agg = PlaylistService._aggressiveNorm(raw),
        plain = PlaylistService._normalise(raw),
        songs = PlaylistService._songParts(raw).toSet(),
        artistSlotWords = {
          for (final part in PlaylistService._artistParts(raw))
            ...part.split(' ').where((w) => w.isNotEmpty),
        };

  /// Lower case, punctuation as spaces, bracket text kept.
  final String agg;

  /// As [agg], with "(Official Video)" style noise removed.
  final String plain;

  /// The parts of the title where the song name sits.
  final Set<String> songs;

  /// Words in the title's artist slot.
  final Set<String> artistSlotWords;

  late final bool cjk = PlaylistService._hasCjk(agg);
}

class _LocalFile {
  final String path;
  final String baseName;
  final List<String> labels;
  final List<_TitleForms> labelForms;
  final String normalised;
  final Set<String> tokens;
  final String extension;

  /// A download that never finished. It is listed under Extras so it can be
  /// cleaned up, but never counts as having the track: "Song.temp" used to
  /// match "Song" and hide the track from the Missing tab.
  final bool incomplete;

  const _LocalFile({
    required this.path,
    required this.baseName,
    required this.labels,
    required this.labelForms,
    required this.normalised,
    required this.tokens,
    required this.extension,
    this.incomplete = false,
  });
}

bool _metadataGodDisabledForMatching = false;

bool get _metadataGodEnabledForMatching =>
    !kIsWeb && !Platform.isWindows && !Platform.isIOS;

/// Reads local audio metadata for playlist/local matching using the safe
/// engine for this platform. Mirrors `player.dart`'s `_readLocalTag`: native
/// `metadata_god` (Rust via flutter_rust_bridge) on Android, pure-Dart
/// `audio_metadata_reader` on Windows / iOS / web. On older Windows CPUs that
/// lack BMI2/AVX2 the native Rust lib can crash the whole process with an
/// illegal instruction, and that can't be caught by any Dart handler, so we
/// never load it on Windows. Only `title`/`artist` are used by the caller. A
/// runtime native failure disables the engine for the session and falls back
/// to the pure-Dart reader.
Future<dynamic> _readLocalTagForMatching(String path) async {
  if (_metadataGodEnabledForMatching && !_metadataGodDisabledForMatching) {
    try {
      await MetadataGod.initialize();
      return await MetadataGod.readMetadata(file: path);
    } catch (e) {
      _metadataGodDisabledForMatching = true;
      debugPrint('metadata_god disabled for matching session '
          '(native read failed, using pure-Dart fallback): $e');
      // fall through to the pure-Dart reader for the rest of the session.
    }
  }
  try {
    return readMetadata(File(path), getImage: false);
  } catch (_) {
    return null;
  }
}

Future<List<String>> _labelsFromMetadata(String path, String ext) async {
  try {
    if (!['.mp3', '.m4a', '.ogg', '.flac'].contains(ext)) {
      return const <String>[];
    }
    final metadata = await _readLocalTagForMatching(path);
    if (metadata == null) return const <String>[];
    final labels = <String>[];
    final title = metadata.title?.trim() ?? '';
    final artist = metadata.artist?.trim() ?? '';
    // No label for the artist on its own: as a "title" it matched every song
    // by that artist. Its words still reach matching through the combined
    // label below.
    if (title.isNotEmpty) labels.add(title);
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

/// Category for an extra file found during playlist↔folder comparison.
enum PlaylistExtraKind {
  /// File has a `.temp.` infix — an incomplete in-progress download.
  incompleteDownload,
  /// File's extension differs from the folder's dominant extension.
  wrongFormat,
  /// File matches the folder's dominant format but is not in the playlist.
  notInPlaylist,
}

/// A file in the folder that doesn't match any playlist track.
class ExtraFile {
  final String filePath;
  final String fileName;
  final String extension;
  final PlaylistExtraKind kind;

  const ExtraFile({
    required this.filePath,
    required this.fileName,
    required this.extension,
    required this.kind,
  });
}

/// Full result of cross-referencing a playlist against a local folder.
/// A Compare that could not run, with a message fit to show the user.
class PlaylistCompareException implements Exception {
  final String message;
  const PlaylistCompareException(this.message);

  @override
  String toString() => message;
}

class PlaylistFolderComparison {
  final int total;
  final List<TrackMatch> matched;
  final List<SearchResult> missing;
  final List<ExtraFile> extras;
  final String folderPath;

  /// Media files found in the folder. Zero with a non-empty playlist usually
  /// means the wrong folder, or one the app can no longer read, so the screen
  /// says so instead of just listing every track as missing.
  final int filesScanned;

  const PlaylistFolderComparison({
    required this.total,
    required this.matched,
    required this.missing,
    required this.extras,
    required this.folderPath,
    this.filesScanned = -1,
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
