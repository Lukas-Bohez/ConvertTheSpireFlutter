import 'dart:io';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:shared_preferences/shared_preferences.dart';

/// Speed, the sleep timer, and long files opening where they were left
/// (issue #41), with the real players.
///
///   flutter test -d windows integration_test/player_playback_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PlayerState player;

  setUpAll(() {
    MediaKit.ensureInitialized();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('player_playback_test');
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

  Future<String> file(String name, int seconds) async {
    final path = '${dir.path}${Platform.pathSeparator}$name.wav';
    await File(path).writeAsBytes(_silenceWav(seconds));
    return path;
  }

  Future<void> waitFor(bool Function() condition, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('at 2x two seconds play in one', (tester) async {
    final path = await file('song', 30);
    await player.setLibrary([MediaItem(path, MediaType.audio, title: 'song')]);
    await player.setSpeed(2.0);
    await player.playFileDirect(path);
    await waitFor(() => player.position > const Duration(seconds: 1),
        const Duration(seconds: 5));
    final from = player.position;
    await Future<void>.delayed(const Duration(seconds: 3));
    final played = (player.position - from).inMilliseconds / 1000;
    expect(played, inInclusiveRange(4.8, 7.2), reason: '3 s at 2x: $played');
  });

  testWidgets('the sleep timer pauses playback', (tester) async {
    final path = await file('song', 30);
    await player.setLibrary([MediaItem(path, MediaType.audio, title: 'song')]);
    await player.playFileDirect(path);
    await waitFor(() => player.isPlaying, const Duration(seconds: 5));
    expect(player.isPlaying, isTrue);
    player.setSleepTimer(const Duration(seconds: 2));
    expect(player.sleepAt, isNotNull);
    await waitFor(() => !player.isPlaying, const Duration(seconds: 5));
    expect(player.isPlaying, isFalse);
    expect(player.sleepAt, isNull);
  });

  testWidgets('a long file opens where it was left', (tester) async {
    final film = await file('film', 12 * 60);
    final song = await file('song', 30);
    await player.setLibrary([
      MediaItem(film, MediaType.audio, title: 'film'),
      MediaItem(song, MediaType.audio, title: 'song'),
    ]);
    final resumed = <Duration>[];
    final sub = player.resumedAt.listen(resumed.add);
    addTearDown(sub.cancel);

    await player.playFileDirect(film);
    await waitFor(() => player.duration != null && player.isPlaying,
        const Duration(seconds: 5));
    await player.seek(const Duration(minutes: 5));
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(resumed, isEmpty, reason: 'it had not been played before');

    // Something else, then the film again.
    await player.playFileDirect(song);
    await Future<void>.delayed(const Duration(seconds: 1));
    await player.playFileDirect(film);
    await waitFor(() => resumed.isNotEmpty, const Duration(seconds: 5));
    expect(resumed, hasLength(1));
    expect(resumed.single.inSeconds, inInclusiveRange(299, 305));
    await waitFor(() => player.position > const Duration(minutes: 4),
        const Duration(seconds: 5));
    expect(player.position.inSeconds, inInclusiveRange(299, 310));

    // Started over: next time it opens at the start.
    await player.seek(Duration.zero);
    await Future<void>.delayed(const Duration(seconds: 3));
    await player.playFileDirect(song);
    await Future<void>.delayed(const Duration(seconds: 1));
    await player.playFileDirect(film);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(resumed, hasLength(1));
    expect(player.position, lessThan(const Duration(seconds: 10)));
  });
}

/// [seconds] of silence as an 8 kHz WAV file.
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
