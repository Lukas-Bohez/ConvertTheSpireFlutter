import 'package:convert_the_spire_reborn/src/services/pip_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #45, fix 11: the little window only for a playing video.
void main() {
  test('only a playing video, with the setting on, may open it', () {
    for (final enabled in [true, false]) {
      for (final isVideo in [true, false]) {
        for (final isPlaying in [true, false]) {
          expect(
            PipService.allowedFor(
                enabled: enabled, isVideo: isVideo, isPlaying: isPlaying),
            enabled && isVideo && isPlaying,
            reason: 'enabled=$enabled video=$isVideo playing=$isPlaying',
          );
        }
      }
    }
  });
}
