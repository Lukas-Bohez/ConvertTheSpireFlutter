import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'platform_dirs.dart';

class InstallerService {
  Future<String> installFfmpeg({
    required Uri url,
    String? checksumSha256,
    void Function(int percent, String message)? onProgress,
  }) async {
    if (kIsWeb) {
      throw Exception('FFmpeg installation is not available on web.');
    }
    var support = await PlatformDirs.getAppSupportDir();
    support ??= await PlatformDirs.getFilesDir();
    support ??= await Directory.systemTemp.createTemp('ffmpeg_install');
    final downloadDir = Directory('${support.path}${Platform.pathSeparator}ffmpeg');
    await downloadDir.create(recursive: true);
    final zipPath = '${downloadDir.path}${Platform.pathSeparator}ffmpeg.zip';

    onProgress?.call(0, 'Downloading');
    final bytes = await _download(url, onProgress: onProgress);
    await File(zipPath).writeAsBytes(bytes, flush: true);

    if (checksumSha256 != null && checksumSha256.trim().isNotEmpty) {
      final digest = sha256.convert(bytes).toString();
      if (digest.toLowerCase() != checksumSha256.toLowerCase()) {
        throw Exception('Checksum mismatch');
      }
    }

    onProgress?.call(60, 'Extracting');
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final outPath = '${downloadDir.path}${Platform.pathSeparator}${file.name}';
      if (file.isFile) {
        final data = file.content as List<int>;
        await File(outPath).create(recursive: true);
        await File(outPath).writeAsBytes(data, flush: true);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    final ffmpegExe = await _findFfmpegExe(downloadDir);
    if (ffmpegExe == null) {
      throw Exception('ffmpeg.exe not found after extraction');
    }

    onProgress?.call(100, 'Complete');
    return ffmpegExe.path;
  }

  Future<Uint8List> _download(Uri url, {void Function(int percent, String message)? onProgress}) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', url))
          .timeout(const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException('FFmpeg download request timed out'));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed: ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;
      // Add stall detection: abort if no data for 60 seconds
      final streamData = response.stream.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(TimeoutException('FFmpeg download stalled – no data for 60 seconds'));
          sink.close();
        },
      );
      await for (final chunk in streamData) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = ((received / total) * 100).clamp(0, 100).toInt();
          onProgress?.call(pct, 'Downloading');
        }
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  Future<File?> _findFfmpegExe(Directory root) async {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('ffmpeg.exe')) {
        return entity;
      }
    }
    return null;
  }
}
