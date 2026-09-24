import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:convert_the_spire_reborn/src/widgets/video_or_playlist_dialog.dart';

void main() {
  Future<VideoOrPlaylist?> choose(WidgetTester tester, String? tap) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    VideoOrPlaylist? answer;
    var answered = false;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 740), textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await askVideoOrPlaylist(context,
                    videoTitle: 'A song with a long title (Official Video)');
                answered = true;
              },
              child: const Text('download'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('download'));
    await tester.pumpAndSettle();
    expect(find.text('A song with a long title (Official Video)'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(tap ?? 'Cancel'));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    return answer;
  }

  testWidgets('the video', (tester) async {
    expect(await choose(tester, 'Just this video'), VideoOrPlaylist.video);
  });

  testWidgets('the playlist', (tester) async {
    expect(
        await choose(tester, 'The whole playlist'), VideoOrPlaylist.playlist);
  });

  testWidgets('cancel downloads nothing', (tester) async {
    expect(await choose(tester, null), isNull);
  });
}
