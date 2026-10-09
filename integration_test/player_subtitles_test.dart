import 'dart:io';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:shared_preferences/shared_preferences.dart';

/// Subtitles with the real players (issue #41): a video's own tracks show
/// without a file, a file next to it goes first even when it is UTF-16, and
/// a film opened from outside the library has them too.
///
/// The video (fixtures/embedded_subtitles.mkv) has two subtitle tracks
/// inside it: French first, then English.
///
///   flutter test -d windows integration_test/player_subtitles_test.dart
/// Android plays video with video_player, which cannot show a file's own
/// subtitle tracks; media_kit (Windows, macOS, Linux) can.
final _noEmbeddedTracks = Platform.isAndroid;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PlayerState player;

  setUpAll(() {
    MediaKit.ensureInitialized();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('player_subtitles_test');
    SharedPreferences.setMockInitialValues({});
    player = PlayerState(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    player.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> video(String name) async {
    final path = '${dir.path}${Platform.pathSeparator}$name.mkv';
    await File('integration_test/fixtures/embedded_subtitles.mkv').copy(path);
    return path;
  }

  Future<void> waitFor(bool Function() condition, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets("a video's own English subtitles show without a file",
      (tester) async {
    final path = await video('film');
    await player.setLibrary([MediaItem(path, MediaType.video, title: 'film')]);
    await player.playFileDirect(path);
    await waitFor(
        () => player.subtitleLine.value != null, const Duration(seconds: 10));
    expect(player.subtitleLine.value, 'Hello from inside the video');
    expect(player.hasSubtitles, isTrue);
    expect(
        player.subtitleOptions
            .where((o) => o.startsWith(PlayerState.embeddedSubtitlePrefix)),
        hasLength(2));
    // Turned off, and on again.
    await player.setSubtitlesOn(false);
    expect(player.subtitleLine.value, isNull);
    await player.setSubtitlesOn(true);
    expect(player.subtitleLine.value, 'Hello from inside the video');
  }, skip: _noEmbeddedTracks);

  testWidgets('a UTF-16 file next to the video goes before its own tracks',
      (tester) async {
    final path = await video('film');
    const srt = '1\r\n00:00:00,300 --> 00:00:09,000\r\nFrom the file\r\n';
    await File(path.replaceAll('.mkv', '.srt')).writeAsBytes([
      0xFF, 0xFE, //
      for (final unit in srt.codeUnits) ...[unit & 0xFF, unit >> 8],
    ]);
    await player.setLibrary([MediaItem(path, MediaType.video, title: 'film')]);
    await player.playFileDirect(path);
    await waitFor(
        () => player.subtitleLine.value != null, const Duration(seconds: 10));
    expect(player.subtitleLine.value, 'From the file');
  });

  testWidgets('a song opened after a video plays from its start',
      (tester) async {
    final film = await video('opened');
    final song = '${dir.path}${Platform.pathSeparator}song.wav';
    await File(song).writeAsBytes(_silenceWav(30));
    await player.setLibrary(const []);
    await player.openExternalFile(film, name: 'opened.mkv', isVideo: true);
    await waitFor(() => player.position > const Duration(seconds: 2),
        const Duration(seconds: 10));
    await player.openExternalFile(song, name: 'song.wav', isVideo: false);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(player.isVideo, isFalse);
    expect(player.nowPlayingItem?.path, song);
    expect(player.isPlaying, isTrue);
    expect(player.position, lessThan(const Duration(seconds: 2)),
        reason: 'the song plays from its start, not where the video was');
  });

  testWidgets('a film opened from outside the library has its subtitles',
      (tester) async {
    final path = await video('opened');
    await player.setLibrary(const []);
    await player.openExternalFile(path, name: 'opened.mkv', isVideo: true);
    await waitFor(
        () => player.subtitleLine.value != null, const Duration(seconds: 10));
    expect(player.subtitleLine.value, 'Hello from inside the video');
    expect(player.nowPlayingItem?.path, path);
  }, skip: _noEmbeddedTracks);
}

/// Silent 16-bit mono WAV of [seconds].
Uint8List _silenceWav(int seconds) {
  const rate = 8000;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return data.buffer.asUint8List();
}
