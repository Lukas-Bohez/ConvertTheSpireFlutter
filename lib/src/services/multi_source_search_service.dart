import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import '../models/search_result.dart';
import '../utils/safe_json.dart';

// --─ YouTube searcher --------------------------------------------------------

class YouTubeSearcher {
  final YoutubeExplode _yt;
  final http.Client? _http;

  YouTubeSearcher({required YoutubeExplode yt, http.Client? httpClient})
      : _yt = yt,
        _http = httpClient;

  /// youtube_explode's search first; when that fails or finds nothing,
  /// YouTube's own results page (issue #45, fix 10). One failing way used
  /// to fail the whole Multi-Search.
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    try {
      final results = await _yt.search.search(query);
      final found = results.take(limit).map((video) {
        return SearchResult(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          duration: video.duration ?? Duration.zero,
          thumbnailUrl: video.thumbnails.mediumResUrl,
          source: 'youtube',
        );
      }).toList();
      if (found.isNotEmpty) return found;
    } catch (e) {
      debugPrint('YouTubeSearcher: youtube_explode search failed ($e); '
          'trying the results page');
    }
    return searchResultsPage(query, limit: limit);
  }

  /// Reads YouTube's results page: the videos are in its `ytInitialData`.
  Future<List<SearchResult>> searchResultsPage(String query,
      {int limit = 10}) async {
    final uri = Uri.https('www.youtube.com', '/results', {
      'search_query': query,
      'sp': 'EgIQAQ%3D%3D', // videos only
      'hl': 'en',
    });
    final client = _http ?? http.Client();
    try {
      final response = await client.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
        // Skips the EU cookie-consent page, which has no results.
        'Cookie': 'CONSENT=YES+cb; SOCS=CAI',
      });
      if (response.statusCode != 200) {
        throw HttpException('YouTube results page: ${response.statusCode}');
      }
      return parseResultsPage(response.body, limit: limit);
    } finally {
      if (_http == null) client.close();
    }
  }

  /// The videos in a YouTube results page, from its `ytInitialData` JSON.
  static List<SearchResult> parseResultsPage(String html, {int limit = 10}) {
    final match = RegExp(
      r'ytInitialData\s*=\s*(\{.*?\});\s*</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return const [];
    final data = safeJsonDecode<Map<String, dynamic>>(match.group(1)!);
    if (data == null) return const [];
    final renderers = <Map<String, dynamic>>[];
    void collect(dynamic node) {
      if (renderers.length >= limit) return;
      if (node is Map) {
        final renderer = node['videoRenderer'];
        if (renderer is Map) renderers.add(renderer.cast<String, dynamic>());
        for (final entry in node.entries) {
          if (entry.key != 'videoRenderer') collect(entry.value);
        }
      } else if (node is List) {
        for (final item in node) {
          collect(item);
        }
      }
    }

    collect(data);
    final results = <SearchResult>[];
    for (final r in renderers) {
      final id = (r['videoId'] ?? '').toString();
      final title = _text(r['title']);
      if (id.length != 11 || title == null || title.isEmpty) continue;
      results.add(SearchResult(
        id: id,
        title: title,
        artist: _text(r['ownerText']) ?? _text(r['longBylineText']) ?? '',
        duration: _parseLength(_text(r['lengthText'])),
        thumbnailUrl: 'https://i.ytimg.com/vi/$id/mqdefault.jpg',
        source: 'youtube',
      ));
    }
    return results;
  }

  static String? _text(dynamic node) {
    if (node is! Map) return null;
    final simple = node['simpleText'];
    if (simple is String) return simple;
    final runs = node['runs'];
    if (runs is List) {
      return runs
          .whereType<Map>()
          .map((run) => run['text']?.toString() ?? '')
          .join();
    }
    return null;
  }

  static Duration _parseLength(String? text) {
    if (text == null) return Duration.zero;
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.contains(null)) return Duration.zero;
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + part!;
    }
    return Duration(seconds: seconds);
  }

  Future<String> getAudioUrl(String videoId) async {
    // The default androidSdkless client often fails on mobile; try fallback
    // clients if the first manifest is empty or throws.
    StreamManifest manifest;
    try {
      manifest = await _yt.videos.streamsClient.getManifest(videoId);
      if (manifest.streams.isEmpty) throw Exception('empty manifest');
    } catch (_) {
      manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.safari, YoutubeApiClient.androidVr],
      );
    }
    // Prefer muxed stream (reliable), fall back to audio-only
    final stream = manifest.muxed.isNotEmpty
        ? manifest.muxed.withHighestBitrate()
        : manifest.audioOnly.withHighestBitrate();
    return stream.url.toString();
  }
}

// --─ SoundCloud searcher ----------------------------------------------------─

class SoundCloudSearcher {
  /// SoundCloud's public web client id. It was never set, so SoundCloud
  /// found nothing on any device (issue #45, fix 10); now it is read from
  /// SoundCloud's own scripts, the way yt-dlp does, and kept for a day.
  String? clientId;
  DateTime _clientIdUntil = DateTime.fromMillisecondsSinceEpoch(0);

  SoundCloudSearcher({this.clientId}) {
    if (clientId != null) {
      _clientIdUntil = DateTime.now().add(const Duration(days: 365));
    }
  }

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  Future<String?> _ensureClientId() async {
    final current = clientId;
    if (current != null &&
        current.isNotEmpty &&
        DateTime.now().isBefore(_clientIdUntil)) {
      return current;
    }
    final home = await http.get(Uri.parse('https://soundcloud.com/'),
        headers: const {'User-Agent': _userAgent});
    final scripts = RegExp(r'<script[^>]+src="([^"]+\.js)"')
        .allMatches(home.body)
        .map((m) => m.group(1)!)
        .toList()
        .reversed;
    for (final src in scripts) {
      final js = await http.get(Uri.parse(src),
          headers: const {'User-Agent': _userAgent});
      final match =
          RegExp(r'client_id\s*:\s*"([0-9a-zA-Z]{32})"').firstMatch(js.body);
      if (match != null) {
        clientId = match.group(1);
        _clientIdUntil = DateTime.now().add(const Duration(hours: 24));
        return clientId;
      }
    }
    throw StateError('SoundCloud client id not found');
  }

  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = await _ensureClientId();
      final url = Uri.https('api-v2.soundcloud.com', '/search/tracks', {
        'q': query,
        'client_id': id,
        'limit': '$limit',
      });
      final response =
          await http.get(url, headers: const {'User-Agent': _userAgent});
      if (response.statusCode == 401 || response.statusCode == 403) {
        // The id was changed: read it again, once.
        clientId = null;
        continue;
      }
      if (response.statusCode != 200) {
        throw HttpException('SoundCloud search: ${response.statusCode}');
      }
      final data = safeJsonDecode<Map<String, dynamic>>(response.body);
      final collection = data?['collection'] as List? ?? const [];
      return collection.whereType<Map>().map<SearchResult>((track) {
        return SearchResult(
          id: track['id'].toString(),
          title: (track['title'] ?? '').toString(),
          artist: (track['user']?['username'] ?? '').toString(),
          duration:
              Duration(milliseconds: (track['duration'] as num?)?.toInt() ?? 0),
          thumbnailUrl: (track['artwork_url'] ?? '').toString(),
          source: 'soundcloud',
          pageUrl: track['permalink_url']?.toString(),
        );
      }).toList();
    }
    throw StateError('SoundCloud refused the client id');
  }
}


// --─ Other sites, through their public search APIs --------------------------
//
// These used to go through yt-dlp ("rumble:search:", "dmsearch:",
// "odysee:search:"), which has no such searches: they never found anything,
// and only on desktops with yt-dlp at that (issue #45, fix 10). Their sites'
// own search APIs need no key and work on every platform; downloading what
// they find still takes yt-dlp.

const _browserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

class DailymotionSearcher {
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final uri = Uri.https('api.dailymotion.com', '/videos', {
      'search': query,
      'fields': 'id,title,owner.screenname,duration,thumbnail_240_url,url',
      'limit': '$limit',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException('Dailymotion search: ${response.statusCode}');
    }
    final list =
        safeJsonDecode<Map<String, dynamic>>(response.body)?['list'] as List? ??
            const [];
    return [
      for (final v in list.whereType<Map>())
        SearchResult(
          id: v['id'].toString(),
          title: (v['title'] ?? '').toString(),
          artist: (v['owner.screenname'] ?? '').toString(),
          duration: Duration(seconds: (v['duration'] as num?)?.toInt() ?? 0),
          thumbnailUrl: (v['thumbnail_240_url'] ?? '').toString(),
          source: 'dailymotion',
          pageUrl: v['url']?.toString(),
        ),
    ];
  }
}

class OdyseeSearcher {
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final uri = Uri.https('lighthouse.odysee.tv', '/search', {
      's': query,
      'size': '$limit',
      'mediaType': 'video,audio',
      'include': 'channel,title,thumbnail_url,duration',
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw HttpException('Odysee search: ${response.statusCode}');
    }
    // Odysee's Content-Type header is malformed, so the body is decoded
    // from its bytes rather than through response.body.
    final list = safeJsonDecode<List<dynamic>>(
            utf8.decode(response.bodyBytes, allowMalformed: true)) ??
        const [];
    return [
      for (final c in list.whereType<Map>())
        if (c['name'] != null && c['claimId'] != null)
          SearchResult(
            id: c['claimId'].toString(),
            title: (c['title'] ?? c['name']).toString(),
            artist: (c['channel'] ?? '').toString().replaceFirst('@', ''),
            duration: Duration(seconds: (c['duration'] as num?)?.toInt() ?? 0),
            thumbnailUrl: (c['thumbnail_url'] ?? '').toString(),
            source: 'odysee',
            pageUrl: 'https://odysee.com/${c['name']}:${c['claimId']}',
          ),
    ];
  }
}

class BiliSearcher {
  String? _buvid3;

  /// Bilibili answers searches only with a visitor cookie.
  Future<String> _cookie() async {
    final known = _buvid3;
    if (known != null) return known;
    final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
        headers: const {'User-Agent': _browserUserAgent});
    final data = safeJsonDecode<Map<String, dynamic>>(response.body);
    final b3 = (data?['data'] as Map?)?['b_3']?.toString();
    if (b3 == null || b3.isEmpty) throw StateError('Bilibili visitor cookie');
    return _buvid3 = b3;
  }

  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    final uri = Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
      'search_type': 'video',
      'keyword': query,
      'page': '1',
    });
    final response = await http.get(uri, headers: {
      'User-Agent': _browserUserAgent,
      'Referer': 'https://www.bilibili.com/',
      'Cookie': 'buvid3=${await _cookie()}',
    });
    final data = safeJsonDecode<Map<String, dynamic>>(response.body);
    if (response.statusCode != 200 || data?['code'] != 0) {
      _buvid3 = null;
      throw HttpException(
          'Bilibili search: ${response.statusCode} ${data?['code']}');
    }
    final list = (data?['data'] as Map?)?['result'] as List? ?? const [];
    return [
      for (final v in list.whereType<Map>().take(limit))
        if (v['bvid'] != null)
          SearchResult(
            id: v['bvid'].toString(),
            title: _plainText(v['title']),
            artist: (v['author'] ?? '').toString(),
            duration: _clockDuration(v['duration']),
            thumbnailUrl: _absoluteUrl(v['pic']),
            source: 'bilibili',
            pageUrl: 'https://www.bilibili.com/video/${v['bvid']}',
          ),
    ];
  }

  /// Bilibili marks the matched words in titles with HTML.
  static String _plainText(Object? html) => (html ?? '')
      .toString()
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  /// "4:13" or "1:02:03".
  static Duration _clockDuration(Object? text) {
    final parts = (text ?? '').toString().split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.contains(null)) return Duration.zero;
    return Duration(seconds: parts.fold<int>(0, (s, p) => s * 60 + p!));
  }

  static String _absoluteUrl(Object? url) {
    final s = (url ?? '').toString();
    return s.startsWith('//') ? 'https:$s' : s;
  }
}

// --─ Multi-source aggregator ------------------------------------------------─

/// What one source did for a search (issue #45, fix 10). Each source used
/// to run unguarded, so one that failed blanked the whole search with an
/// error, and one that was slow made it look empty.
enum SourceState {
  searching,
  found,
  nothing,
  timedOut,
  failed,

  /// Its results can't be downloaded here: everything but YouTube needs
  /// yt-dlp, which phones don't have.
  desktopOnly,

  /// Needs yt-dlp, which isn't installed on this computer.
  needsYtDlp,
}

class SourceStatus {
  const SourceStatus({
    required this.source,
    required this.label,
    required this.state,
    this.count = 0,
    this.error,
  });

  final String source;
  final String label;
  final SourceState state;
  final int count;
  final String? error;
}

/// Results so far, merged and ranked, with each source's status.
class SearchProgress {
  const SearchProgress({
    required this.results,
    required this.sources,
    required this.done,
  });

  final List<SearchResult> results;
  final List<SourceStatus> sources;
  final bool done;
}

class _Source {
  const _Source(this.id, this.label, this.run, {this.needsYtDlp = true});

  final String id;
  final String label;
  final Future<List<SearchResult>> Function(String query, int limit) run;
  final bool needsYtDlp;
}

class MultiSourceSearchService {
  final YouTubeSearcher youtubeSearcher;
  final SoundCloudSearcher soundcloudSearcher;
  final BiliSearcher? biliSearcher;
  final DailymotionSearcher? dailymotionSearcher;
  final OdyseeSearcher? odyseeSearcher;
  final Duration perSourceTimeout;
  final Duration globalTimeout;

  /// Whether results other than YouTube's can be downloaded on this device:
  /// they take yt-dlp. Asked on every search, so a yt-dlp installed or set
  /// in Settings counts without a restart. Null: never (phones).
  final Future<bool> Function()? canDownloadOtherSites;

  MultiSourceSearchService({
    required this.youtubeSearcher,
    required this.soundcloudSearcher,
    this.biliSearcher,
    this.dailymotionSearcher,
    this.odyseeSearcher,
    this.canDownloadOtherSites,
    this.perSourceTimeout = const Duration(seconds: 15),
    this.globalTimeout = const Duration(seconds: 20),
  });

  List<_Source> get _sources => [
        _Source(
            'youtube', 'YouTube', (q, n) => youtubeSearcher.search(q, limit: n),
            needsYtDlp: false),
        _Source('soundcloud', 'SoundCloud',
            (q, n) => soundcloudSearcher.search(q, limit: n)),
        if (biliSearcher != null)
          _Source('bilibili', 'Bilibili',
              (q, n) => biliSearcher!.search(q, limit: n)),
        if (dailymotionSearcher != null)
          _Source('dailymotion', 'Dailymotion',
              (q, n) => dailymotionSearcher!.search(q, limit: n)),
        if (odyseeSearcher != null)
          _Source('odysee', 'Odysee',
              (q, n) => odyseeSearcher!.search(q, limit: n)),
      ];

  /// Searches every source at once. Each one is on its own: a source that
  /// fails or is slow says so in its status, and the others' results still
  /// come. Results arrive as each source answers, ranked as a whole.
  Stream<SearchProgress> searchAllStream(String query,
      {int limitPerSource = 10}) {
    final controller = StreamController<SearchProgress>();
    unawaited(_run(query, limitPerSource, controller));
    return controller.stream;
  }

  Future<void> _run(String query, int limit,
      StreamController<SearchProgress> controller) async {
    bool? otherSites;
    try {
      otherSites = await canDownloadOtherSites?.call();
    } catch (_) {
      otherSites = false;
    }
    final sources = _sources;
    final statuses = <String, SourceStatus>{};
    final found = <String, List<SearchResult>>{};

    void emit({bool done = false}) {
      if (controller.isClosed) return;
      controller.add(SearchProgress(
        results: rank(query, [for (final s in sources) ...?found[s.id]]),
        sources: [for (final s in sources) statuses[s.id]!],
        done: done,
      ));
    }

    final running = <Future<void>>[];
    for (final source in sources) {
      if (source.needsYtDlp && otherSites != true) {
        statuses[source.id] = SourceStatus(
          source: source.id,
          label: source.label,
          state: otherSites == null
              ? SourceState.desktopOnly
              : SourceState.needsYtDlp,
        );
        continue;
      }
      statuses[source.id] = SourceStatus(
          source: source.id, label: source.label, state: SourceState.searching);
      running.add(_runOne(source, query, limit).then((status) {
        statuses[source.id] = status.$1;
        if (status.$2 != null) found[source.id] = status.$2!;
        emit();
      }));
    }

    emit();
    await Future.wait(running).timeout(globalTimeout, onTimeout: () {
      statuses.updateAll((id, s) => s.state == SourceState.searching
          ? SourceStatus(
              source: s.source, label: s.label, state: SourceState.timedOut)
          : s);
      return const [];
    });
    emit(done: true);
    await controller.close();
  }

  Future<(SourceStatus, List<SearchResult>?)> _runOne(
      _Source source, String query, int limit) async {
    final watch = Stopwatch()..start();
    SourceStatus status;
    List<SearchResult>? results;
    try {
      results = await source.run(query, limit).timeout(perSourceTimeout);
      status = SourceStatus(
        source: source.id,
        label: source.label,
        state: results.isEmpty ? SourceState.nothing : SourceState.found,
        count: results.length,
      );
    } on TimeoutException {
      status = SourceStatus(
          source: source.id, label: source.label, state: SourceState.timedOut);
    } catch (e) {
      status = SourceStatus(
        source: source.id,
        label: source.label,
        state: SourceState.failed,
        error: '$e',
      );
    }
    debugPrint('Search ${source.label}: ${status.state.name} '
        '(${status.count}) in ${watch.elapsedMilliseconds} ms'
        '${status.error == null ? '' : ': ${status.error}'}');
    return (status, results);
  }

  /// Every source's results together, once all have answered. Never
  /// throws: sources that fail just add nothing.
  Future<List<SearchResult>> searchAll(String query,
      {int limitPerSource = 10}) async {
    final last =
        await searchAllStream(query, limitPerSource: limitPerSource).last;
    return last.results;
  }

  /// Exact title matches first, then YouTube (it downloads everywhere),
  /// then the other sites, each in the order its site gave.
  static List<SearchResult> rank(String query, List<SearchResult> results) {
    final queryLower = query.toLowerCase();
    const sourceOrder = {
      'youtube': 0,
      'soundcloud': 1,
      'dailymotion': 2,
      'odysee': 3,
      'bilibili': 4,
    };
    final indexed = results.asMap().entries.toList()
      ..sort((a, b) {
        final aExact = a.value.title.toLowerCase() == queryLower;
        final bExact = b.value.title.toLowerCase() == queryLower;
        if (aExact != bExact) return aExact ? -1 : 1;
        final bySource = (sourceOrder[a.value.source] ?? 9)
            .compareTo(sourceOrder[b.value.source] ?? 9);
        return bySource != 0 ? bySource : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }
}
