import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:just_audio/just_audio.dart';

/// Wraps [AudioPlayer] in an [AudioHandler] so that audio continues playing
/// on Android when the app is in the background.  The system media notification
/// (play/pause/next/previous) is handled automatically.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;

  /// Callbacks for skip actions — set by PlayerState.
  Future<void> Function()? onSkipToNext;
  Future<void> Function()? onSkipToPrevious;

  AppAudioHandler(this._player) {
    // Forward just_audio events → audio_service playback state.
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: 0,
    );
  }

  /// Update the metadata shown in the system notification.
  @override
  Future<void> updateMediaItem(MediaItem item) async {
    mediaItem.add(item);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipToPrevious?.call();
  }
}

/// Initialize audio_service on Android.  Returns `null` on non-Android
/// platforms where no background service is needed.
Future<AppAudioHandler?> initAudioService(AudioPlayer player) async {
  if (kIsWeb || !Platform.isAndroid) return null;

  try {
    final handler = await AudioService.init<AppAudioHandler>(
      builder: () => AppAudioHandler(player),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.orokaconner.convertthespire.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
      ),
    );
    debugPrint('AudioService initialized for background playback');
    return handler;
  } catch (e) {
    debugPrint('Failed to initialize AudioService: $e');
    return null;
  }
}
