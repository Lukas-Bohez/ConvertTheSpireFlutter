import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import 'package:convert_the_spire_reborn/src/models/search_result.dart';
import 'package:convert_the_spire_reborn/src/services/playlist_service.dart';

SearchResult _track(String id, String title, {String artist = 'Artist'}) =>
    SearchResult(
      id: id,
      title: title,
      artist: artist,
      duration: const Duration(minutes: 3),
      thumbnailUrl: '',
      source: 'youtube',
    );

void main() {
  late PlaylistService service;
  late YoutubeExplode yt;
  final originalLister = PlaylistService.listSafTree;

  setUp(() {
    yt = YoutubeExplode();
    service = PlaylistService(yt: yt);
  });

  tearDown(() {
    yt.close();
    PlaylistService.listSafTree = originalLister;
  });

  final playlist = [
    _track('aaaaaaaaaaa', 'Northern Lights'),
    _track('bbbbbbbbbbb', 'Glass Harbour'),
    _track('ccccccccccc', 'Paper Moon'),
  ];

  group('Compare against an Android folder (SAF tree)', () {
    const tree =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic';

    test('lists the tree instead of reporting every track missing', () async {
      PlaylistService.listSafTree = (uri) async {
        expect(uri, tree);
        return [
          {'uri': '$tree/document/1', 'name': 'Artist - Northern Lights.mp3'},
          {'uri': '$tree/document/2', 'name': 'Glass Harbour.mp3'},
          {'uri': '$tree/document/3', 'name': 'cover.jpg'},
        ];
      };

      final result = await service.compareToFolder(playlist, tree);

      expect(result.matched.map((m) => m.track.id),
          containsAll(['aaaaaaaaaaa', 'bbbbbbbbbbb']));
      expect(result.missing.map((t) => t.id), ['ccccccccccc']);
      // The image is not media, so only the two songs were indexed.
      expect(result.filesScanned, 2);
      // Matches keep the document URI, which the Extras actions and the
      // player can open.
      expect(result.matched.first.filePath, startsWith('content://'));
    });

    test('an empty or unreadable tree reports zero files scanned', () async {
      PlaylistService.listSafTree = (_) async => const [];

      final result = await service.compareToFolder(playlist, tree);

      expect(result.filesScanned, 0);
      expect(result.missingCount, playlist.length);
    });
  });

  group('Compare against a folder on disk', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('compare_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<void> touch(String name) =>
        File('${dir.path}${Platform.pathSeparator}$name').writeAsString('x');

    test('a half-finished download does not count as having the track',
        () async {
      await touch('Artist - Northern Lights.opus');
      await touch('Glass Harbour.opus');
      // The downloader's partial file for the third track.
      await touch('Paper Moon.temp.mp4');

      final result = await service.compareToFolder(playlist, dir.path);

      expect(result.missing.map((t) => t.id), ['ccccccccccc']);
      final incomplete = result.extras
          .where((e) => e.kind == PlaylistExtraKind.incompleteDownload)
          .map((e) => e.fileName);
      expect(incomplete, ['Paper Moon.temp']);
    });

    test('yt-dlp .part files are flagged as incomplete too', () async {
      await touch('Paper Moon.webm.part');

      final result = await service.compareToFolder(playlist, dir.path);

      expect(result.matched, isEmpty);
      expect(
          result.extras.single.kind, PlaylistExtraKind.incompleteDownload);
    });

    test('files in unrelated formats are ignored, not counted', () async {
      await touch('notes.txt');
      await touch('Glass Harbour.opus');

      final result = await service.compareToFolder(playlist, dir.path);

      expect(result.filesScanned, 1);
      expect(result.matched.single.track.id, 'bbbbbbbbbbb');
    });

    test('a folder that does not exist is an error, not "all missing"',
        () async {
      final gone = '${dir.path}${Platform.pathSeparator}nope';

      expect(
        () => service.compareToFolder(playlist, gone),
        throwsA(isA<PlaylistCompareException>()),
      );
    });
  });

  group('Matching names', () {
    const tree = 'content://tree/music';

    /// Compares one playlist track against a folder holding [files] and
    /// returns the matched file name, or null when the track is missing.
    Future<TrackMatch?> matchOne(SearchResult track, List<String> files) async {
      PlaylistService.listSafTree = (_) async => [
            for (var i = 0; i < files.length; i++)
              {'uri': '$tree/document/$i', 'name': files[i]},
          ];
      final result = await service.compareToFolder([track], tree);
      return result.matched.isEmpty ? null : result.matched.single;
    }

    test('a different song is never an exact match', () async {
      final m = await matchOne(
          _track('a', 'Northern Lights'), ['Glass Harbour.mp3']);
      expect(m, isNull);
    });

    test('two songs by the same artist are told apart', () async {
      final m = await matchOne(
        _track('a', 'Coldplay - Yellow', artist: 'Coldplay'),
        ['Coldplay - Fix You.mp3'],
      );
      expect(m?.method, isNot(MatchMethod.exact));
    });

    test('shared "(Official Video)" noise is not a match', () async {
      final m = await matchOne(
        _track('a', 'Paper Moon (Official Video)'),
        ['Glass Harbour (Official Video).mp3'],
      );
      expect(m, isNull);
    });

    test('a one-word title does not claim a longer different title',
        () async {
      final m =
          await matchOne(_track('a', 'Love', artist: 'X'), ['Love Story.mp3']);
      expect(m?.method, isNot(MatchMethod.exact));
    });

    test('the file the app downloaded matches exactly', () async {
      final m = await matchOne(
        _track('a', 'AC/DC - Thunderstruck (Official Video)'),
        ['AC_DC - Thunderstruck (Official Video).mp3'],
      );
      expect(m?.method, MatchMethod.exact);
    });

    test('an "Artist - Title" file matches a Topic-channel track', () async {
      final m = await matchOne(
        _track('a', 'Believer', artist: 'Imagine Dragons - Topic'),
        ['Imagine Dragons - Believer.mp3'],
      );
      expect(m?.method, MatchMethod.exact);
    });

    test('a bare title file matches the decorated YouTube title', () async {
      final m = await matchOne(
        _track('a', 'Queen - Bohemian Rhapsody (Official Video Remastered)'),
        ['Bohemian Rhapsody.mp3'],
      );
      expect(m?.method, MatchMethod.exact);
    });

    test('the song part matches across different decorations', () async {
      final m = await matchOne(
        _track('a', 'Daft Punk - Get Lucky (Official Audio)'),
        ['Daft Punk ft. Pharrell - Get Lucky [Lyrics].mp3'],
      );
      expect(m, isNotNull);
    });

    test('Japanese titles still match without spaces', () async {
      final m = await matchOne(
        _track('a', '夜に駆ける / YOASOBI'),
        ['YOASOBI「夜に駆ける」Official Music Video.mp3'],
      );
      expect(m, isNotNull);
    });

    test('noise-stripping keeps letters inside words', () async {
      final m = await matchOne(
          _track('a', 'Shadow of the Day'), ['Shadow of the Day.mp3']);
      expect(m?.method, MatchMethod.exact);
    });
  });
}
