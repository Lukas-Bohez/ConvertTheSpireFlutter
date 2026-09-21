import 'package:convert_the_spire_reborn/src/services/loudness_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoudnessService.computeGainDb', () {
    test('a track at the target level needs no gain', () {
      expect(LoudnessService.computeGainDb(-20, -3), closeTo(0, 1e-9));
    });

    test('loud tracks are turned down', () {
      // mean -12 dB is 8 dB above the -20 dB target.
      expect(LoudnessService.computeGainDb(-12, -0.5), closeTo(-8, 1e-9));
    });

    test('quiet tracks are boosted when there is peak headroom', () {
      // mean -26 dB -> +6 dB wanted; peak -10 dB leaves 9 dB of headroom.
      expect(LoudnessService.computeGainDb(-26, -10), closeTo(6, 1e-9));
    });

    test('boost never pushes the peak past the ceiling (no clipping)', () {
      // +10 dB wanted but the peak is -4 dB: only 3 dB of headroom to -1 dB.
      expect(LoudnessService.computeGainDb(-30, -4), closeTo(3, 1e-9));
    });

    test('a track already at the ceiling is not boosted at all', () {
      expect(LoudnessService.computeGainDb(-30, 0), closeTo(0, 1e-9));
    });

    test('gain is clamped to the safe range', () {
      expect(LoudnessService.computeGainDb(-50, -60),
          closeTo(LoudnessService.maxBoostDb, 1e-9));
      expect(LoudnessService.computeGainDb(0, 0),
          closeTo(LoudnessService.maxCutDb, 1e-9));
    });

    test('unknown peak still allows a boost within limits', () {
      expect(LoudnessService.computeGainDb(-26, null), closeTo(6, 1e-9));
    });
  });
}
