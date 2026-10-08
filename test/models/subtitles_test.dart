import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/models/subtitles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Subtitles from SRT and WebVTT files, for videos and songs (issue #41),
/// and synced lyrics from LRC files.
void main() {
  Duration ms(int v) => Duration(milliseconds: v);

  test('SRT, with tags, two lines and a byte order mark', () {
    final subs = Subtitles.parse('﻿1\r\n'
        '00:00:01,000 --> 00:00:03,500\r\n'
        '<i>Hello</i> there\r\n'
        '{\\an8}second line\r\n'
        '\r\n'
        '2\r\n'
        '00:01:02,250 --> 00:01:04,000\r\n'
        'Tom &amp; Jerry\r\n');
    expect(subs.cues, [
      SubtitleCue(ms(1000), ms(3500), 'Hello there\nsecond line'),
      SubtitleCue(ms(62250), ms(64000), 'Tom & Jerry'),
    ]);
    expect(subs.textAt(ms(500)), isNull);
    expect(subs.textAt(ms(1000)), 'Hello there\nsecond line');
    expect(subs.textAt(ms(3499)), 'Hello there\nsecond line');
    expect(subs.textAt(ms(3500)), isNull);
    expect(subs.textAt(ms(63000)), 'Tom & Jerry');
    expect(subs.textAt(const Duration(hours: 2)), isNull);
  });

  test('WebVTT, without hours, and overlapping cues', () {
    final subs = Subtitles.parse('WEBVTT\n\n'
        '00:01.000 --> 00:05.000 line:90%\n'
        'Narrator\n\n'
        'cue-2\n'
        '00:02.500 --> 00:03.000\n'
        'Someone else\n');
    expect(subs.textAt(ms(2000)), 'Narrator');
    expect(subs.textAt(ms(2700)), 'Narrator\nSomeone else');
    expect(subs.textAt(ms(4000)), 'Narrator');
  });

  test('a broken cue is skipped, the rest kept', () {
    final subs =
        Subtitles.parse('1\n00:00:05,000 --> 00:00:01,000\nbackwards\n\n'
            '2\nnot a time\ntext\n\n'
            '3\n00:00:06,000 --> 00:00:07,000\nfine\n');
    expect(subs.cues.map((c) => c.text), ['fine']);
  });

  test('LRC lyrics: each line until the next, repeated lines, offset', () {
    final subs = Subtitles.parseLrc(const LineSplitter().convert('''
[ar:Night Signals]
[ti:Neon Rain]
[offset:+500]
[00:12.50]First line
[00:15.00][01:00.00]Chorus <00:15.40>with <00:15.90>words
[00:20]
[00:25.2]Last line
''').join('\r\n'));
    expect(subs.cues, [
      SubtitleCue(ms(12000), ms(14500), 'First line'),
      SubtitleCue(ms(14500), ms(19500), 'Chorus with words'),
      SubtitleCue(ms(24700), ms(59500), 'Last line'),
      SubtitleCue(ms(59500), ms(67500), 'Chorus with words'),
    ]);
    // The empty time ends the chorus: nothing shows until the last line.
    expect(subs.textAt(ms(21000)), isNull);
  });

  group('files', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('subs'));
    tearDown(() async => dir.delete(recursive: true));

    Future<void> touch(String relative, [String body = '']) async {
      final f = File(p.join(dir.path, relative));
      await f.parent.create(recursive: true);
      await f.writeAsString(body);
    }

    test('next to the film, then in its Subs folder, English first', () async {
      await touch('Die Hard.mkv');
      await touch('Die Hard.en.srt');
      await touch('Die Hard.srt');
      await touch('Other.srt');
      await touch('Subs/3_French.srt');
      await touch('Subs/2_English.srt');
      final found = await Subtitles.findFor(p.join(dir.path, 'Die Hard.mkv'));
      expect(found.map(p.basename),
          ['Die Hard.srt', 'Die Hard.en.srt', '2_English.srt', '3_French.srt']);
    });

    test('a folder per episode: only this episode', () async {
      await touch('Show.S01E01.mkv');
      await touch('Subs/Show.S01E01/English.srt');
      await touch('Subs/Show.S01E02/English.srt');
      final found =
          await Subtitles.findFor(p.join(dir.path, 'Show.S01E01.mkv'));
      expect(found, hasLength(1));
      expect(found.single, contains('S01E01'));
    });

    test('lyrics next to a song are found and read as LRC', () async {
      await touch('Neon Rain.mp3');
      await touch('Neon Rain.lrc', '''
[00:01.00]Hello
[00:03.00]World
''');
      final found = await Subtitles.findFor(p.join(dir.path, 'Neon Rain.mp3'));
      expect(found.map(p.basename), ['Neon Rain.lrc']);
      final subs = await Subtitles.load(found.single);
      expect(subs.textAt(ms(2000)), 'Hello');
      expect(subs.textAt(ms(4000)), 'World');
    });

    test('a file that is not UTF-8 is read as Latin-1', () async {
      final path = p.join(dir.path, 'old.srt');
      await File(path).writeAsBytes(latin1
          .encode('1\n00:00:01,000 --> 00:00:02,000\nCafé à la française\n'));
      final subs = await Subtitles.load(path);
      expect(subs.cues.single.text, 'Café à la française');
    });
  });
}
