import 'dart:io';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:convert_the_spire_reborn/src/services/loudness_service.dart';
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

  // The player opens a file as "C:/dir/a.wav" (or file:///..., when that
  // fails): the same file either way.
  String? sameForm(String? uriOrPath) => uriOrPath
      ?.replaceFirst(RegExp(r'^file:///?'), '')
      .replaceAll('\\', '/')
      .toLowerCase();

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

  testWidgets('replaying a tagged song preserves volume with leveling off',
      (tester) async {
    final path = await file('tagged-song', 30);
    final item = MediaItem(path, MediaType.audio, title: 'tagged-song');
    item.trackGainDb = -12;
    await player.setLibrary([item]);
    player.library[0].trackGainDb = -12;
    expect(player.volumeLeveling, isFalse);
    await player.select(0);
    await waitFor(() => player.isPlaying, const Duration(seconds: 5));
    final firstVolume = player.nativeAudioVolumeForTesting;
    expect(firstVolume, closeTo(90, 0.01));
    await player.select(0);
    expect(player.nativeAudioVolumeForTesting, closeTo(firstVolume!, 0.01));
  }, skip: !Platform.isWindows);

  // Leveling is switched on in the player setUp made: disposing a player
  // right after it was made and making another froze the test (media_kit,
  // with the video output still starting). The app makes one for good.
  testWidgets('slow leveling uses the same native gain on first and second play',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    player.loudnessServiceForTesting = _SlowLoudness(prefs);
    player.setVolumeLeveling(true);
    final path = await file('leveling', 30);
    await player.setLibrary([MediaItem(path, MediaType.audio)]);
    await player.select(0);
    await waitFor(() => player.isPlaying, const Duration(seconds: 5));
    final first = player.nativeAudioVolumeForTesting!;
    // Old behavior started at 90 after 2.5 seconds, before the -12 dB
    // measurement arrived, then replayed at a lower volume.
    expect(first, lessThan(70));
    await Future<void>.delayed(const Duration(seconds: 1));
    await player.select(0);
    expect(player.nativeAudioVolumeForTesting, closeTo(first, 0.01));
    player.setVolumeLeveling(false);
    await waitFor(() => (player.nativeAudioVolumeForTesting! - 90).abs() < 0.01,
        const Duration(seconds: 3));
    expect(player.nativeAudioVolumeForTesting, closeTo(90, 0.01));
  }, skip: !Platform.isWindows);

  testWidgets('a measurement slower than the wait fades in instead of a jump',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    player.loudnessServiceForTesting =
        _SlowLoudness(prefs, const Duration(seconds: 12));
    player.setVolumeLeveling(true);
    final path = await file('long-video-like', 40);
    await player.setLibrary([MediaItem(path, MediaType.audio)]);
    final selected = player.select(0);
    // Playback does not wait for ever: it starts after 10 s, unleveled.
    await waitFor(() => player.isPlaying, const Duration(seconds: 14));
    await selected;
    expect(player.nativeAudioVolumeForTesting, closeTo(90, 0.01));
    // The measurement (-12 dB) lands at 12 s and is faded to over 2 s.
    await waitFor(() => player.nativeAudioVolumeForTesting! < 89,
        const Duration(seconds: 4));
    final during = player.nativeAudioVolumeForTesting!;
    final leveled = PlayerState.mkVolumeFor(0.9, 0.2511886431509580);
    expect(during, greaterThan(leveled + 1), reason: 'a fade, not a step');
    await waitFor(
        () => (player.nativeAudioVolumeForTesting! - leveled).abs() < 0.01,
        const Duration(seconds: 4));
    await player.select(0);
    expect(player.nativeAudioVolumeForTesting, closeTo(leveled, 0.01));
  }, skip: !Platform.isWindows);

  testWidgets('rapid selections finish on the last requested track',
      (tester) async {
    final paths = [
      await file('first', 30),
      await file('second', 30),
      await file('third', 30),
    ];
    await player.setLibrary([
      for (final path in paths) MediaItem(path, MediaType.audio),
    ]);
    await Future.wait([player.select(0), player.select(1), player.select(2)]);
    await waitFor(() => player.isPlaying, const Duration(seconds: 5));
    expect(player.currentItem?.path, paths.last);
    if (Platform.isWindows) {
      expect(sameForm(player.nativeAudioUriForTesting), sameForm(paths.last));
    }
    expect(player.isPlaying, isTrue);
    expect(player.duration?.inSeconds, 30);
  });

  const playlistFolder = String.fromEnvironment('TEST_MEDIA_FOLDER');
  testWidgets('large local playlist: repeat, seek and rapid selection',
      (tester) async {
    final paths = await Directory(playlistFolder)
        .list(recursive: true, followLinks: false)
        .where((entry) =>
            entry is File && entry.path.toLowerCase().endsWith('.mp3'))
        .map((entry) => entry.path)
        .toList();
    paths.sort();
    expect(paths.length, greaterThan(1000));
    await player.setLibrary([
      for (final path in paths) MediaItem(path, MediaType.audio),
    ]);
    for (var i = 0; i < 24; i++) {
      final index = (i * 47) % paths.length;
      await player.select(index);
      await waitFor(
          () => player.isPlaying && player.position.inMilliseconds > 100,
          const Duration(seconds: 8));
      expect(player.currentItem?.path, paths[index]);
      expect(player.isPlaying, isTrue);
      final firstVolume = player.nativeAudioVolumeForTesting;
      await player.select(index);
      expect(player.nativeAudioVolumeForTesting, closeTo(firstVolume!, 0.01));
      await player.seek(const Duration(seconds: 10));
    }
    await Future.wait(
        [player.select(0), player.select(400), player.select(1000)]);
    expect(player.currentItem?.path, paths[1000]);
    expect(sameForm(player.nativeAudioUriForTesting), sameForm(paths[1000]));
    expect(player.isPlaying, isTrue);
  },
      skip: playlistFolder.isEmpty || !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 8)));

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

class _SlowLoudness extends LoudnessService {
  _SlowLoudness(super.prefs, [this.delay = const Duration(milliseconds: 3200)]);

  final Duration delay;

  @override
  double? cachedGainDb(String localPath) => null;

  @override
  Future<double?> gainDbFor(String localPath) async {
    await Future<void>.delayed(delay);
    return -12;
  }
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
