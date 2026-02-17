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
    try {
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }

  void dispose() {
    _autoStopTimer?.cancel();
    _player?.dispose();
  }
}
