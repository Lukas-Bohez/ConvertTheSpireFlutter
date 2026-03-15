import 'dart:io';

import 'package:media_kit/media_kit.dart';

// This is a standalone script to generate a single video thumbnail.
// It is designed to be called from the main application to isolate the
// potentially unstable native media_kit code.
//
// Usage: dart run tools/thumbnailer.dart <input_video_path> <output_png_path>

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tools/thumbnailer.dart <input_video_path> <output_png_path>');
    exit(1);
  }

  final inputPath = args[0];
  final outputPath = args[1];

  // Must be called for standalone Dart scripts.
  MediaKit.ensureInitialized();

  final player = Player();

  try {
    // Mute the player to avoid any audio output.
    await player.setVolume(0);

    // Open the media file without starting playback.
    await player.open(Media(Uri.file(inputPath).toString()), play: false);

    // Wait for the duration to become available.
    final duration = await player.stream.duration.firstWhere((d) => d > Duration.zero,
        orElse: () => Duration.zero).timeout(const Duration(seconds: 10));

    // Seek to 10% of the video duration, or max 15 seconds in.
    if (duration > Duration.zero) {
      final seekPosition = Duration(milliseconds: (duration.inMilliseconds * 0.1).round().clamp(0, 15000));
      await player.seek(seekPosition);
    }
    
    // A short delay may be necessary for the frame to be ready after seeking.
    await Future.delayed(const Duration(milliseconds: 500));

    // Take the screenshot.
    final screenshotBytes = await player.screenshot();

    if (screenshotBytes != null) {
      final file = File(outputPath);
      await file.writeAsBytes(screenshotBytes);
    } else {
      // Exit with an error code if screenshot fails
      exit(2);
    }
  } catch (e) {
    stderr.writeln('Thumbnail generation failed: $e');
    exit(3);
  } finally {
    // Ensure the player is disposed to release native resources.
    await player.dispose();
  }
  
  // Success
  exit(0);
}
