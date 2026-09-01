// cinematic_thumbnail_capture.dart
//
// Starter utility: render the cinematic ambient shader off-screen and
// capture it as a PNG, for use as an auto-generated thumbnail on
// library items that don't have one — primarily audio-only tracks,
// which video_thumbnail can't help with since there's no video frame
// to extract.
//
// No new pubspec dependencies. PNG encoding uses dart:ui's built-in
// encoder (Image.toByteData(format: ImageByteFormat.png)) — nothing
// from the `image` package is needed for this file, though it stays
// available if you want further raster manipulation later (resizing,
// letterboxing, overlays). Canvas/Paint/Rect are pulled unprefixed
// from material.dart and ui.* is used explicitly for the rest, matching
// the existing style in lib/src/widgets/ambient_scene.dart.
//
// See bitplayer_cinematic_view_v2_technical_reference.md §7 for why
// this renders off-screen instead of a RepaintBoundary on the live
// CinematicViewScreen widget, and §7 of the masterprompt for how the
// deterministic per-track seeding is meant to be used.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Paint, Rect;
import 'package:path_provider/path_provider.dart';

/// Small, dependency-free, stable string hash. Not for anything
/// security-sensitive — just needs to be the same for the same input
/// every time the app runs, which Dart's built-in String.hashCode
/// isn't documented to guarantee. Used both to seed the generated
/// scene and to name the cached thumbnail file, so both stay in sync
/// for a given track path/id.
int stableHash(String input) {
  int h = 0;
  for (final codeUnit in input.codeUnits) {
    h = (h * 31 + codeUnit) & 0x7fffffff;
  }
  return h;
}

double _frac(int seed, int salt) {
  final v = ((seed ^ salt) * 2654435761) & 0x7fffffff;
  return (v % 10000) / 10000.0;
}

/// Deterministic per-track scene parameters for thumbnail generation:
/// the same track path/id always produces the same parameters, so
/// regenerating a thumbnail later doesn't change how it looks, and
/// different tracks land on visibly different scenes.
///
/// Deliberately biased toward clear/lightly-clouded, low-rain scenes —
/// a thumbnail that's mostly grey rain reads poorly at library-grid
/// size. The live cinematic view's own weather system (masterprompt
/// §1) is unbiased across the same range; these are two independent
/// seeded choices and don't need to match each other.
class ThumbnailSceneParams {
  final double time;
  final double dayPhase;
  final double cloudAmount;
  final double rainAmount;

  const ThumbnailSceneParams({
    required this.time,
    required this.dayPhase,
    required this.cloudAmount,
    required this.rainAmount,
  });

  factory ThumbnailSceneParams.forTrack(String trackPathOrId) {
    final h = stableHash(trackPathOrId);
    return ThumbnailSceneParams(
      // A fixed mid-cycle point rather than 0 — early frames of a
      // noise-driven scene tend to look sparse before enough motion
      // has accumulated (stars/clouds barely settled in).
      time: 40.0 + _frac(h, 1) * 120.0,
      dayPhase: _frac(h, 2),
      // Square the draw so low (clear) values are more common than high.
      cloudAmount: _frac(h, 3) * _frac(h, 3) * 0.6,
      // Only ~1 in 6 tracks gets any rain at all, and even then it's capped low.
      rainAmount: _frac(h, 4) > 0.83 ? _frac(h, 5) * 0.35 : 0.0,
    );
  }
}

/// Renders assets/shaders/ambient_scene.frag at [width]x[height] with
/// the given scene parameters and returns PNG-encoded bytes. Works
/// without a mounted widget or BuildContext, so it can run as part of
/// a background pass over the whole library, not just while cinematic
/// view happens to be open.
Future<Uint8List> captureAmbientFrame({
  required ui.FragmentShader shader,
  required ThumbnailSceneParams params,
  int width = 512,
  int height = 288, // 16:9 — match whatever aspect the rest of the app's thumbnails use
}) async {
  shader
    ..setFloat(0, width.toDouble())
    ..setFloat(1, height.toDouble())
    ..setFloat(2, params.time)
    ..setFloat(3, params.dayPhase)
    ..setFloat(4, params.cloudAmount)
    ..setFloat(5, params.rainAmount);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..shader = shader,
  );
  final picture = recorder.endRecording();

  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();

  if (byteData == null) {
    throw StateError('Failed to encode ambient scene frame to PNG.');
  }
  return byteData.buffer.asUint8List();
}

/// Where generated thumbnails live. getApplicationSupportDirectory()
/// (rather than a newer path_provider method) is used deliberately —
/// it's been stable across path_provider 2.x, which is what's pinned
/// in pubspec.yaml today.
Future<Directory> _thumbnailCacheDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/cinematic_thumbnails');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _saveThumbnail(String itemPathOrId, Uint8List pngBytes) async {
  final dir = await _thumbnailCacheDir();
  // Same stable hash used for seeding, so re-running this for the same
  // track overwrites its own file instead of accumulating duplicates.
  final safeName = stableHash(itemPathOrId).toRadixString(16);
  final file = File('${dir.path}/$safeName.png');
  await file.writeAsBytes(pngBytes, flush: true);
  return file;
}

/// High-level single-item entry point: generate and save a thumbnail
/// for one library item, returning the saved file (or null on failure).
///
/// Wire this in as the fallback specifically for items where the
/// existing thumbnail pipeline (video_thumbnail, embedded artwork,
/// metadata_service lookups, etc.) comes back empty.
Future<File?> generateThumbnailForItem({
  required String itemPathOrId,
  required Future<ui.FragmentProgram> Function() loadShaderProgram,
}) async {
  ui.FragmentShader? shader;
  try {
    final program = await loadShaderProgram();
    shader = program.fragmentShader();
    final params = ThumbnailSceneParams.forTrack(itemPathOrId);
    final pngBytes = await captureAmbientFrame(shader: shader, params: params);
    return await _saveThumbnail(itemPathOrId, pngBytes);
  } catch (e, st) {
    // Non-fatal: a missing generated thumbnail should never block
    // playback or library loading. Fold into whatever logging pattern
    // the rest of the app uses rather than a bare print — the codebase
    // already has an existing debugPrint('[AMBIENT] ...') convention in
    // ambient_scene.dart worth matching here.
    // ignore: avoid_print
    print('[CINEMATIC_THUMBNAIL] Failed for $itemPathOrId: $e\n$st');
    return null;
  } finally {
    shader?.dispose();
  }
}

/// Batch helper: fill in missing thumbnails across a list of items.
/// Loads the shader program once and reuses it, runs sequentially with
/// a small delay between items since this is background housekeeping,
/// not something a user is actively waiting on — tune or parallelize
/// if a first-run, whole-library pass turns out too slow in practice.
Future<int> backfillMissingThumbnails({
  required List<String> itemPathsMissingThumbnails,
  required Future<ui.FragmentProgram> Function() loadShaderProgram,
}) async {
  final program = await loadShaderProgram();
  var succeeded = 0;

  for (final path in itemPathsMissingThumbnails) {
    final shader = program.fragmentShader();
    try {
      final params = ThumbnailSceneParams.forTrack(path);
      final pngBytes = await captureAmbientFrame(shader: shader, params: params);
      await _saveThumbnail(path, pngBytes);
      succeeded++;
    } catch (_) {
      // Skip and continue — one bad item shouldn't stop the batch.
    } finally {
      shader.dispose();
    }
    await Future.delayed(const Duration(milliseconds: 15));
  }

  return succeeded;
}
