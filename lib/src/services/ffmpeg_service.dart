import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class FfmpegService {
  Future<void> run(List<String> args, {required String? ffmpegPath}) async {
    if (kIsWeb) {
      throw Exception('FFmpeg is not supported on web.');
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      if (code == null || !ReturnCode.isSuccess(code)) {
        final output = await session.getOutput();
        throw Exception('FFmpeg failed: $output');
      }
      return;
    }

    if (ffmpegPath == null || ffmpegPath.trim().isEmpty) {
      throw Exception('FFmpeg path not configured');
    }

    final result = await Process.run(ffmpegPath, args, runInShell: false)
        .timeout(const Duration(minutes: 30), onTimeout: () {
      throw Exception('FFmpeg timed out after 30 minutes');
    });
    if (result.exitCode != 0) {
      final stderr = result.stderr?.toString().trim() ?? '';
      final stdout = result.stdout?.toString().trim() ?? '';
      final details = [stderr, stdout].where((text) => text.isNotEmpty).join(' ');
      throw Exception(details.isEmpty ? 'FFmpeg failed with exit code ${result.exitCode}' : 'FFmpeg failed: $details');
    }
  }

  /// Resolves a working FFmpeg path.
  /// Returns the configured path if it exists, or `'ffmpeg'` if FFmpeg
  /// is available on the system PATH, or `null` if not found anywhere.
  Future<String?> resolveAvailablePath(String? configuredPath) async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) return configuredPath;

    // 1. Check configured path
    if (configuredPath != null && configuredPath.trim().isNotEmpty) {
      if (await File(configuredPath).exists()) return configuredPath;
    }

    // 2. Check system PATH
    try {
      final result = await Process.run('ffmpeg', ['-version'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) return 'ffmpeg';
    } catch (_) {}

    return null;
  }

  Future<bool> isAvailable(String? ffmpegPath) async {
    return await resolveAvailablePath(ffmpegPath) != null;
  }
}
