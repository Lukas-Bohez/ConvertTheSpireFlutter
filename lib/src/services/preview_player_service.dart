import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// Lightweight service for previewing audio streams.
class PreviewPlayerService {
  AudioPlayer? _player;
  Timer? _autoStopTimer;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// Play a 30-second preview from [url].
  Future<void> previewAudio(String url, {int previewSeconds = 30}) async {
    await stopPreview();
    _player = AudioPlayer();
    try {
      await _player!.setUrl(url);
      await _player!.play();
      _isPlaying = true;

      _autoStopTimer = Timer(Duration(seconds: previewSeconds), () {
        stopPreview();
      });
    } catch (e) {
      _isPlaying = false;
      rethrow;
    }
  }

  /// Preview a local file for [previewSeconds].
  Future<void> previewFile(String filePath, {int previewSeconds = 30}) async {
    await stopPreview();
    _player = AudioPlayer();
    try {
      await _player!.setFilePath(filePath);
      await _player!.play();
      _isPlaying = true;

      _autoStopTimer = Timer(Duration(seconds: previewSeconds), () {
        stopPreview();
      });
    } catch (e) {
      _isPlaying = false;
      rethrow;
    }
  }

  Future<void> stopPreview() async {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _isPlaying = false;
    // Capture and null-out before any await to prevent a stale timer
    // callback from disposing a newly created player.
    final player = _player;
    _player = null;
    try {
      await player?.stop();
      await player?.dispose();
    } catch (_) {}
  }

  void dispose() {
    _autoStopTimer?.cancel();
    final player = _player;
    _player = null;
    player?.stop();
    player?.dispose();
  }
}
