import 'dart:math';

import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:convert_the_spire_reborn/src/services/loudness_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoudnessService.computeGainDb', () {
    test('a track at the target level needs no gain', () {
      expect(LoudnessService.computeGainDb(-16, -3), closeTo(0, 1e-9));
    });

    test('loud tracks are turned down', () {
      // mean -10 dB is 6 dB above the -16 dB target.
      expect(LoudnessService.computeGainDb(-10, -0.5), closeTo(-6, 1e-9));
    });

    test('quiet tracks are boosted when there is peak headroom', () {
      // mean -22 dB -> +6 dB wanted; peak -10 dB leaves 9 dB of headroom.
      expect(LoudnessService.computeGainDb(-22, -10), closeTo(6, 1e-9));
    });

    test('boost never pushes the peak past the ceiling (no clipping)', () {
      // +10 dB wanted but the peak is -4 dB: only 3 dB of headroom to -1 dB.
      expect(LoudnessService.computeGainDb(-26, -4), closeTo(3, 1e-9));
    });

    test('a track already at the ceiling is not boosted at all', () {
      expect(LoudnessService.computeGainDb(-26, 0), closeTo(0, 1e-9));
    });

    test('gain is clamped to the safe range', () {
      expect(LoudnessService.computeGainDb(-50, -60),
          closeTo(LoudnessService.maxBoostDb, 1e-9));
      expect(LoudnessService.computeGainDb(0, 0),
          closeTo(LoudnessService.maxCutDb, 1e-9));
    });

    test('unknown peak still allows a boost within limits', () {
      expect(LoudnessService.computeGainDb(-22, null), closeTo(6, 1e-9));
    });
  });

  group('desktop player volume (mpv, cubic)', () {
    // mpv plays volume v at amplitude (v / 100)^3.
    double playedDb(double mpvVolume) =>
        20 * log(pow(mpvVolume / 100, 3)) / ln10;
    double linear(double db) => pow(10, db / 20).toDouble();

    test('a leveling gain plays at exactly that many dB', () {
      for (final db in [-12.0, -6.0, -1.0, 0.0, 3.0, 9.0]) {
        final full = PlayerState.mkVolumeFor(1.0, 1.0);
        final leveled = PlayerState.mkVolumeFor(1.0, linear(db));
        expect(playedDb(leveled) - playedDb(full), closeTo(db, 1e-6));
      }
    });

    test('the slider keeps its own curve', () {
      expect(PlayerState.mkVolumeFor(0.5, 1.0), closeTo(50, 1e-9));
      expect(PlayerState.mkVolumeFor(1.8, 1.0), closeTo(180, 1e-9));
    });
  });
}
