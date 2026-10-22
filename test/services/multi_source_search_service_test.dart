import 'dart:async';

import 'package:convert_the_spire_reborn/src/models/search_result.dart';
import 'package:convert_the_spire_reborn/src/services/multi_source_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

/// Issue #45, fix 10: one failing or slow source must never blank the
/// search, and every source says how it went.
class _FakeYouTube extends YouTubeSearcher {
  _FakeYouTube(this.answer) : super(yt: YoutubeExplode());
  final Future<List<SearchResult>> Function() answer;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) =>
      answer();
}

class _FakeSoundCloud extends SoundCloudSearcher {
  _FakeSoundCloud(this.answer);
  final Future<List<SearchResult>> Function() answer;

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) =>
      answer();
}

SearchResult _result(String id, String source, [String title = 'Song']) =>
    SearchResult(
      id: id,
      title: title,
      artist: 'Artist',
      duration: Duration.zero,
      thumbnailUrl: '',
      source: source,
      pageUrl: source == 'youtube' ? null : 'https://example.com/$id',
    );

void main() {
  test('a failing source does not blank the others', () async {
    final service = MultiSourceSearchService(
      youtubeSearcher:
          _FakeYouTube(() async => [_result('aaaaaaaaaaa', 'youtube')]),
      soundcloudSearcher:
          _FakeSoundCloud(() async => throw StateError('no client id')),
      canDownloadOtherSites: () async => true,
    );
    final last = await service.searchAllStream('song').last;
    expect(last.done, isTrue);
    expect(last.results.map((r) => r.id), ['aaaaaaaaaaa']);
    final states = {for (final s in last.sources) s.source: s.state};
    expect(states['youtube'], SourceState.found);
    expect(states['soundcloud'], SourceState.failed);
  });

  test('a hanging source times out, and faster results come first',
      () async {
    final hang = Completer<List<SearchResult>>();
    final service = MultiSourceSearchService(
      youtubeSearcher:
          _FakeYouTube(() async => [_result('aaaaaaaaaaa', 'youtube')]),
      soundcloudSearcher: _FakeSoundCloud(() => hang.future),
      canDownloadOtherSites: () async => true,
      perSourceTimeout: const Duration(milliseconds: 200),
    );
    final updates = await service.searchAllStream('song').toList();
    expect(updates.any((u) => !u.done && u.results.isNotEmpty), isTrue,
        reason: 'YouTube results show before the slow source ends');
    final states = {for (final s in updates.last.sources) s.source: s.state};
    expect(states['soundcloud'], SourceState.timedOut);
    expect(updates.last.results, hasLength(1));
  });

  test('on a phone other sites are not searched, and say why', () async {
    var soundCloudAsked = false;
    final service = MultiSourceSearchService(
      youtubeSearcher:
          _FakeYouTube(() async => [_result('aaaaaaaaaaa', 'youtube')]),
      soundcloudSearcher: _FakeSoundCloud(() async {
        soundCloudAsked = true;
        return [];
      }),
    );
    final last = await service.searchAllStream('song').last;
    expect(soundCloudAsked, isFalse);
    expect(
        last.sources.firstWhere((s) => s.source == 'soundcloud').state,
        SourceState.desktopOnly);
  });

  test('a result of another site is queued by its own page, not as YouTube',
      () {
    expect(_result('123', 'soundcloud').url, 'https://example.com/123');
    expect(_result('aaaaaaaaaaa', 'youtube').url,
        'https://www.youtube.com/watch?v=aaaaaaaaaaa');
  });

  test("YouTube's results page is read when the library search fails", () {
    const html = '<script>var ytInitialData = {"contents":{"x":[{"videoRenderer":'
        '{"videoId":"bbbbbbbbbbb","title":{"runs":[{"text":"Sasaki"}]},'
        '"ownerText":{"runs":[{"text":"Channel"}]},'
        '"lengthText":{"simpleText":"4:13"}}}]}};</script>';
    final results = YouTubeSearcher.parseResultsPage(html);
    expect(results, hasLength(1));
    expect(results.single.id, 'bbbbbbbbbbb');
    expect(results.single.title, 'Sasaki');
    expect(results.single.artist, 'Channel');
    expect(results.single.duration, const Duration(minutes: 4, seconds: 13));
  });
}
