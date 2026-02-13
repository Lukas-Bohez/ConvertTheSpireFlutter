import 'dart:io';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';

class FfmpegService {
  Future<void> run(List<String> args, {required String? ffmpegPath}) async {
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

    final result = await Process.run(ffmpegPath, args, runInShell: false);
    if (result.exitCode != 0) {
      throw Exception('FFmpeg failed: ${result.stderr}');
    }
  }

  Future<bool> isAvailable(String? ffmpegPath) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return true;
    }
    if (ffmpegPath == null || ffmpegPath.trim().isEmpty) {
      return false;
    }
    return File(ffmpegPath).exists();
  }
}
