import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/models/loop_sections.dart';
import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:shared_preferences/shared_preferences.dart';

/// Looped parts with the real players (issue #41): playback stays in the
/// marked parts, goes from one to the next, and a part that runs to the
/// end of the track starts over at the first instead of stopping.
///
///   flutter test -d windows integration_test/player_loop_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PlayerState player;

  setUpAll(() {
    MediaKit.ensureInitialized();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('player_loop_test');
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

  Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

  /// Plays [seconds] of a tone with [parts] looping, and reports where
  /// playback was every 100 ms for [watch].
  Future<List<double>> playLooped(
      int seconds, List<LoopSection> parts, Duration watch) async {
    final path = '${dir.path}${Platform.pathSeparator}tone.wav';
    await File(path).writeAsBytes(_toneWav(seconds));
    await player.setLibrary([MediaItem(path, MediaType.audio, title: 'tone')]);
    await player.setLoopSettings(path, LoopSettings(on: true, sections: parts));
    await player.playFileDirect(path);
    final seen = <double>[];
    final end = DateTime.now().add(watch);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      seen.add(player.position.inMilliseconds / 1000);
    }
    return seen;
  }

  testWidgets('playback stays in a part and starts it over', (tester) async {
    final seen = await playLooped(
        20, [LoopSection(s(2), s(4))], const Duration(seconds: 7));
    // A moment to get from the start of the track into the part.
    final settled = seen.skip(10).toList();
    expect(settled, isNotEmpty);
    for (final at in settled) {
      expect(at, inInclusiveRange(1.9, 4.6), reason: 'left the part: $seen');
    }
    expect(settled.any((at) => at > 3.5), isTrue,
        reason: 'the part plays to its end: $seen');
    var wrapped = false;
    for (var i = 1; i < settled.length; i++) {
      if (settled[i - 1] > 3.5 && settled[i] < 2.6) wrapped = true;
    }
    expect(wrapped, isTrue, reason: 'it starts the part over: $seen');
  });

  testWidgets('a part at the end of the track goes back to the first',
      (tester) async {
    final seen = await playLooped(
        6,
        [LoopSection(s(1), s(2)), LoopSection(s(5), s(6))],
        const Duration(seconds: 8));
    final settled = seen.skip(10).toList();
    for (final at in settled) {
      final inFirst = at >= 0.9 && at <= 2.6;
      final inLast = at >= 4.9;
      expect(inFirst || inLast, isTrue, reason: 'left the parts: $seen');
    }
    expect(settled.any((at) => at >= 5.2), isTrue,
        reason: 'the last part plays: $seen');
    // After the end of the track it is back in the first part, playing.
    var restarted = false;
    for (var i = 1; i < settled.length; i++) {
      if (settled[i - 1] >= 5 && settled[i] < 2.6) restarted = true;
    }
    expect(restarted, isTrue, reason: 'it goes back to the first part: $seen');
    expect(player.isPlaying, isTrue);
  });
}

/// [seconds] of a 440 Hz tone as a WAV file.
Uint8List _toneWav(int seconds) {
  const rate = 22050;
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
  for (var i = 0; i < samples; i++) {
    final v = (sin(2 * pi * 440 * i / rate) * 3000).round();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}
