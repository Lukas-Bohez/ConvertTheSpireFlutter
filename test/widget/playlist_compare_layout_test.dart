import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import 'package:convert_the_spire_reborn/src/models/search_result.dart';
import 'package:convert_the_spire_reborn/src/screens/playlist_screen.dart';
import 'package:convert_the_spire_reborn/src/services/playlist_service.dart';
import 'package:convert_the_spire_reborn/src/state/app_controller.dart';

/// A playlist service that answers from memory instead of YouTube.
class _FakePlaylistService extends PlaylistService {
  _FakePlaylistService() : super(yt: YoutubeExplode());

  static final tracks = [
    for (final (i, title) in [
      'Northern Lights',
      'Glass Harbour',
      'Paper Moon (Official Video)',
    ].indexed)
      SearchResult(
        id: 'video$i',
        title: title,
        artist: 'Some Artist With A Long Channel Name',
        duration: const Duration(minutes: 3, seconds: 30),
        thumbnailUrl: '',
        source: 'youtube',
      ),
  ];

  @override
  Future<PlaylistInfo> getPlaylistInfo(String playlistUrl) async =>
      const PlaylistInfo(
        title: 'A playlist with a fairly long title for a phone screen',
        author: 'Someone',
        description: '',
        videoCount: 3,
      );

  @override
  Future<List<SearchResult>> getYouTubePlaylistTracks(String playlistUrl,
          {int? maxVideos}) async =>
      tracks;
}

void main() {
  const tree =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic';
  final originalLister = PlaylistService.listSafTree;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlaylistService.listSafTree = (_) async => [
          {'uri': '$tree/document/1', 'name': 'Northern Lights.mp3'},
          {'uri': '$tree/document/2', 'name': 'Glass Harbour.mp3'},
          {'uri': '$tree/document/3', 'name': 'Some other song.mp3'},
        ];
  });
  tearDown(() => PlaylistService.listSafTree = originalLister);

  for (final size in const [Size(360, 740), Size(1280, 800)]) {
    final label = '${size.width.toInt()}px';

    testWidgets('Compare from a pasted playlist link at $label',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final downloads = <(int, String, String?)>[];
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: const TextScaler.linear(1.3)),
          child: Scaffold(
            body: PlaylistScreen(
              playlistService: _FakePlaylistService(),
              onDownloadMissing: (tracks, format, folder) =>
                  downloads.add((tracks.length, format, folder)),
              pendingRequest: ValueNotifier(const PendingPlaylistRequest(
                url: 'https://www.youtube.com/playlist?list=PLx',
                folder: tree,
                format: 'm4a',
              )),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The phone folder shows as a place, not a content:// URI.
      expect(find.text('Phone storage/Music'), findsOneWidget);
      // The format picked where the link was pasted survives.
      expect(find.text('M4A'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Compare jumped to Missing: one track is not in the folder.
      expect(find.textContaining('Download Selected (1/1)'), findsOneWidget);
      // Tapping the row, not only the checkbox, toggles it.
      await tester.tap(find.text('Paper Moon (Official Video)'));
      await tester.pump();
      expect(find.textContaining('Download Selected (0/1)'), findsOneWidget);
      await tester.tap(find.text('Paper Moon (Official Video)'));
      await tester.pump();
      await tester.tap(find.textContaining('Download Selected (1/1)'));
      await tester.pump();
      // Into the compared folder, in the chosen format.
      expect(downloads.single, (1, 'm4a', tree));
      expect(tester.takeException(), isNull);

      Finder tabNamed(String name) => find.descendant(
          of: find.byType(TabBar), matching: find.text(name));
      // On a phone the tab bar scrolls; bring the tab on screen first, the
      // way a person would swipe to it.
      Future<void> openTab(String name) async {
        await tester.ensureVisible(tabNamed(name));
        await tester.pumpAndSettle();
        await tester.tap(tabNamed(name));
        await tester.pumpAndSettle();
      }

      for (final tab in ['Matched', 'Extras', 'Overview']) {
        await openTab(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab tab at $label');
      }
      // Two of three songs matched; the unrelated file is an extra.
      await openTab('Matched');
      expect(find.text('Northern Lights'), findsWidgets);
      expect(find.text('Glass Harbour'), findsWidgets);
      expect(find.text('Paper Moon (Official Video)'), findsNothing);
    });
  }

  testWidgets('a folder with no music says so instead of "all missing"',
      (tester) async {
    PlaylistService.listSafTree = (_) async => const [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlaylistScreen(
          playlistService: _FakePlaylistService(),
          onDownloadMissing: (_, __, ___) {},
          pendingRequest: ValueNotifier(const PendingPlaylistRequest(
            url: 'https://www.youtube.com/playlist?list=PLx',
            folder: tree,
          )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('Overview')));
    await tester.pumpAndSettle();

    expect(find.text('No music files in Phone storage/Music.'), findsOneWidget);
    expect(find.text('Choose another folder'), findsOneWidget);
  });
}
