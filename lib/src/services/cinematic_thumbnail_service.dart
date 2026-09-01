import 'dart:typed_data';
import 'dart:ui';

import '../widgets/ambient_scene.dart';

/// Generates a still PNG thumbnail from the cinematic ambient shader, for
/// tracks/videos that don't have any artwork of their own.
///
/// This paints `AmbientScenePainter` straight onto an offscreen
/// [PictureRecorder] -- no widget tree, no `RepaintBoundary`, no
/// `BuildContext`. That matters for two reasons:
///   1. It can be called from plain state/service code (e.g. from
///      `requestThumbnailForIndex` in player.dart) exactly like the
///      existing embedded-art and video-frame fallbacks.
///   2. It never touches a video decoder or platform view, so it doesn't
///      carry the desktop stability risk that `_generateVideoThumbnailSafe`
///      was written to avoid -- this is pure Skia/Impeller rendering.
///
/// Usage sketch (see MASTERPROMPT.md for the exact hook point):
///
/// ```dart
/// thumb ??= await CinematicThumbnailService.generate(
///   width: 320,
///   height: 320,
///   seed: path,
/// );
/// ```
class CinematicThumbnailService {
  CinematicThumbnailService._();

  static FragmentProgram? _program;

  /// Loads and caches the compiled shader program. Optional -- call this
  /// once at app start (e.g. after the first frame) if you'd rather pay
  /// the one-time shader-compile cost up front instead of on the first
  /// generated thumbnail. [generate] will lazy-load it either way.
  static Future<void> preload() async {
    _program ??= await FragmentProgram.fromAsset(
      'assets/shaders/ambient_scene.frag',
    );
  }

  /// Renders one still frame of the ambient scene and returns it as PNG
  /// bytes, or null if the shader couldn't be loaded/rendered -- in which
  /// case callers should treat it exactly like any other failed thumbnail
  /// fetch (fall through to the existing placeholder icon).
  ///
  /// [seed] picks *which* moment of the day/night/weather cycle gets
  /// rendered. Pass something stable per-track (its file path works well)
  /// so the same track always regenerates the same look, but different
  /// tracks land on different moments -- some daytime, some starry night,
  /// occasionally mid-storm with puddles -- instead of every generated
  /// thumbnail being an identical frame.
  static Future<Uint8List?> generate({
    required double width,
    required double height,
    required Object seed,
    double timeRangeSeconds = 600.0,
  }) async {
    try {
      _program ??= await FragmentProgram.fromAsset(
        'assets/shaders/ambient_scene.frag',
      );
      final shader = _program!.fragmentShader();
      try {
        final time =
            (seed.hashCode.abs() % 100000) / 100000.0 * timeRangeSeconds;
        final painter = AmbientScenePainter(shader: shader, time: time);

        final recorder = PictureRecorder();
        final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
        painter.paint(canvas, Size(width, height));
        final picture = recorder.endRecording();

        try {
          final image = await picture.toImage(width.round(), height.round());
          try {
            final byteData =
                await image.toByteData(format: ImageByteFormat.png);
            return byteData?.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        } finally {
          picture.dispose();
        }
      } finally {
        shader.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
