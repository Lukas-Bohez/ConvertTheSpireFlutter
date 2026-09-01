import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _initialized = false;

  Future<void> _play(String asset) async {
    if (!SettingsService.instance.soundEffectsEnabled) return;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // ignore: unawaited_futures
      HapticFeedback.lightImpact();
    }
    // On Windows, ensure the first sound is played after a short delay and on the main thread.
    if (Platform.isWindows && !_initialized) {
      _initialized = true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    void playOnMainThread() async {
      try {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await _player.setSource(AssetSource(asset));
            await _player.setVolume(0.85);
            await _player.resume();
          } catch (e) {
            debugPrint('Sound play error: $e');
          }
        });
      } catch (e) {
        debugPrint('Sound play error: $e');
      }
    }

    playOnMainThread();
  }

  Future<void> playClick() async => _play('sounds/click.mp3');
  Future<void> playSend() async => _play('sounds/send.mp3');
  Future<void> playNotification() async => _play('sounds/notification.mp3');
  Future<void> playMention() async => _play('sounds/mention.mp3');

  Future<void> startVoiceSession() async {
    // ramp up a sustained tone simulation (notification sound loop) for voice chat.
    if (!SettingsService.instance.soundEffectsEnabled) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _player.play(
            AssetSource('sounds/notification.mp3'),
            volume: 0.35,
          );
        } catch (e) {
          debugPrint('Voice session start failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Voice session start failed: $e');
    }
  }

  Future<void> stopVoiceSession() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
    } catch (e) {
      debugPrint('Voice session stop failed: $e');
    }
  }
}
