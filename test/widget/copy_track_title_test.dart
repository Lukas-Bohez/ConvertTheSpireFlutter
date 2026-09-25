import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:convert_the_spire_reborn/src/screens/player.dart';

void main() {
  String? copied;

  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> copy(WidgetTester tester, MediaItem item) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => copyTrackTitle(context, item),
            child: const Text('copy'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('copies the title the player shows, and says so',
      (tester) async {
    await copy(
      tester,
      MediaItem('/music/01 - track.mp3', MediaType.audio,
          title: 'Bohemian Rhapsody', artist: 'Queen'),
    );
    expect(copied, 'Bohemian Rhapsody');
    expect(find.text('Title copied'), findsOneWidget);
  });

  testWidgets('without a title tag, copies the file name without extension',
      (tester) async {
    await copy(
      tester,
      MediaItem('/music/Daft Punk - One More Time.m4a', MediaType.audio),
    );
    expect(copied, 'Daft Punk - One More Time');
  });

  testWidgets('a blank title tag counts as no title', (tester) async {
    await copy(
      tester,
      MediaItem('/videos/Holiday.mp4', MediaType.video, title: '   '),
    );
    expect(copied, 'Holiday');
  });
}
