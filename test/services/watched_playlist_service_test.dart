import 'package:convert_the_spire_reborn/src/models/search_result.dart';
import 'package:convert_the_spire_reborn/src/services/watched_playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SearchResult makeTrack(String id) => SearchResult(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
      duration: const Duration(seconds: 10),
      thumbnailUrl: '',
      source: 'youtube',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WatchedPlaylistService entry model', () {
    test('allows the same URL to be watched twice with different folders', () async {
      final fetches = <String>[];
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async {
          fetches.add(url);
          return [makeTrack('a'), makeTrack('b')];
        },
        onNewPlaylistTrack: (url, track, {folder, format}) async {},
      );

      const url = 'https://www.youtube.com/playlist?list=AAA';
      final e1 = await service.addEntry(url: url, folder: '/mp3', format: 'mp3');
      final e2 = await service.addEntry(url: url, folder: '/m4a', format: 'm4a');

      // Two distinct entries, both with unique ids.
      expect(e1.id, isNot(equals(e2.id)));
      expect(e1.url, url);
      expect(e2.url, url);

      final entries = await service.getEntries();
      expect(entries.length, 2);

      // The shared URL snapshot is only fetched once (first watcher seeds it).
      expect(fetches, [url]);
    });

    test('updateEntry changes folder/format in place, keeping id', () async {
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async => [],
        onNewPlaylistTrack: (url, track, {folder, format}) async {},
      );

      final e = await service.addEntry(url: 'U1', format: 'mp3');
      await service.updateEntry(e.id, folder: '/new-dir', format: 'mp4');

      final entries = await service.getEntries();
      expect(entries.single.id, e.id);
      expect(entries.single.url, 'U1');
      expect(entries.single.folder, '/new-dir');
      expect(entries.single.format, 'mp4');
    });

    test('removeEntry cleans shared per-URL state only for the last watcher',
        () async {
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async => [makeTrack('a')],
        onNewPlaylistTrack: (url, track, {folder, format}) async {},
      );

      await service.addEntry(url: 'U1');
      await service.addEntry(url: 'U1');
      final entries = await service.getEntries();
      expect(entries.length, 2);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pl_hash_U1'), isNotNull,
          reason: 'snapshot seeded by first watcher');

      // Removing the first watcher keeps the shared snapshot (second watcher).
      await service.removeEntry(entries[0].id);
      expect(prefs.getString('pl_hash_U1'), isNotNull,
          reason: 'another entry still watches U1 -> shared state kept');

      // Removing the last watcher clears it.
      await service.removeEntry(entries[1].id);
      expect(prefs.getString('pl_hash_U1'), isNull,
          reason: 'last watcher removed -> shared state cleaned');
      expect(await service.getEntries(), isEmpty);
    });
  });
group('legacy migration', () {
    test('converts URL list + per-format folder keys into entries', () async {
      SharedPreferences.setMockInitialValues({
        'watched_playlists': ['https://youtube.com/playlist?list=AAA'],
        'pl_folder_https://youtube.com/playlist?list=AAA':
            r'C:\music\default',
        'pl_folder_mp3_https://youtube.com/playlist?list=AAA':
            r'C:\music\mp3',
      });
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async => [],
        onNewPlaylistTrack: (url, track, {folder, format}) async {},
      );

      final entries = await service.getEntries();
      expect(entries.length, 2, reason: 'default folder + mp3 folder entries');

      final defaultEntry = entries.singleWhere((e) => e.format == null);
      expect(defaultEntry.folder, r'C:\music\default');
      expect(defaultEntry.url, 'https://youtube.com/playlist?list=AAA');

      final mp3Entry = entries.singleWhere((e) => e.format == 'mp3');
      expect(mp3Entry.folder, r'C:\music\mp3');

      // Legacy keys are intentionally left in place.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('watched_playlists'), isNotNull);
      expect(prefs.getString('pl_folder_https://youtube.com/playlist?list=AAA'),
          isNotNull);
    });

    test('migrates a URL with all four folders into four entries', () async {
      SharedPreferences.setMockInitialValues({
        'watched_playlists': ['U1'],
        'pl_folder_U1': 'D',
        'pl_folder_mp3_U1': 'M3',
        'pl_folder_m4a_U1': 'M4',
        'pl_folder_mp4_U1': 'P4',
      });
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async => [],
        onNewPlaylistTrack: (url, track, {folder, format}) async {},
      );

      final entries = await service.getEntries();
      expect(entries.length, 4);
      expect(entries.map((e) => e.format).toSet(), {null, 'mp3', 'm4a', 'mp4'});
      expect(entries.singleWhere((e) => e.format == null).folder, 'D');
      expect(entries.singleWhere((e) => e.format == 'mp4').folder, 'P4');
    });

    test('URL with no folder becomes a single default entry', () async {
      SharedPreferences.setMockInitialValues({
        'watched_playlists': ['U1'],
      });
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async => [],
        onNewPlaylistTrack: (url, track, {folder, format}) async {},
      );

      final entries = await service.getEntries();
      expect(entries.single.url, 'U1');
      expect(entries.single.folder, isNull);
      expect(entries.single.format, isNull);
    });
  });

  group('checkAllPlaylists fan-out', () {
    test('fetches each URL once and delivers new tracks to every entry',
        () async {
      var tracks = <SearchResult>[makeTrack('a'), makeTrack('b')];
      final fetches = <String>[];
      final deliveries = <List<dynamic>>[];
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async {
          fetches.add(url);
          return tracks;
        },
        onNewPlaylistTrack: (url, track, {folder, format}) async {
          deliveries.add([url, track.id, folder, format]);
        },
      );

      // Two watchers of U1 (already snapshot in addEntry), one of U2.
      await service.addEntry(url: 'U1', folder: 'F1', format: 'mp3');
      await service.addEntry(url: 'U1', folder: 'F2', format: 'm4a');
      await service.addEntry(url: 'U2');
      fetches.clear();

      // U1 gains a new track; U2 also gains it vs its own snapshot.
      tracks = [makeTrack('a'), makeTrack('b'), makeTrack('c')];
      final newCount = await service.checkAllPlaylists();

      expect(fetches, ['U1', 'U2'],
          reason: 'each unique URL fetched exactly once per cycle');
      expect(newCount, 2);

      // The new track is delivered to BOTH watchers of U1 with their
      // own folder/format…
      final u1Deliveries = deliveries.where((d) => d[0] == 'U1').toList();
      expect(u1Deliveries.length, 2);
      expect(u1Deliveries.map((d) => d[1]).toSet(), {'c'});
      expect(u1Deliveries.map((d) => d[2]).toSet(), {'F1', 'F2'});
      expect(u1Deliveries.map((d) => d[3]).toSet(), {'mp3', 'm4a'});

      // …and once to the single U2 watcher with the app defaults.
      final u2Deliveries = deliveries.where((d) => d[0] == 'U2').toList();
      expect(u2Deliveries.length, 1);
      expect(u2Deliveries.single[1], 'c');
      expect(u2Deliveries.single[2], isNull);
      expect(u2Deliveries.single[3], isNull);
    });

    test('no change produces no deliveries', () async {
      final deliveries = <List<dynamic>>[];
      final service = WatchedPlaylistService(
        fetchPlaylistTracks: (url) async => [makeTrack('a'), makeTrack('b')],
        onNewPlaylistTrack: (url, track, {folder, format}) async {
          deliveries.add([url, track.id, folder, format]);
        },
      );
      await service.addEntry(url: 'U1'); // snapshots [a, b]
      final newCount = await service.checkAllPlaylists();
      expect(newCount, 0);
      expect(deliveries, isEmpty);
    });
  });
}