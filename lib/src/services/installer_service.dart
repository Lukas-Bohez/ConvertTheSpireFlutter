import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
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
    final downloadDir =
        Directory('${support.path}${Platform.pathSeparator}ffmpeg');
    await downloadDir.create(recursive: true);
    final zipPath = '${downloadDir.path}${Platform.pathSeparator}ffmpeg.zip';

    onProgress?.call(0, 'Downloading');
    final zipFile = await _downloadToFile(url, zipPath, onProgress: onProgress);

    if (checksumSha256 != null && checksumSha256.trim().isNotEmpty) {
      final digestObj = await sha256.bind(zipFile.openRead()).first;
      final digest = digestObj.toString();
      if (digest.toLowerCase() != checksumSha256.toLowerCase()) {
        throw Exception('Checksum mismatch');
      }
    }

    onProgress?.call(60, 'Extracting');
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final outPath =
          '${downloadDir.path}${Platform.pathSeparator}${file.name}';
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

  Future<File> _downloadToFile(Uri url, String outPath,
      {void Function(int percent, String message)? onProgress}) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', url)).timeout(
          const Duration(seconds: 30),
          onTimeout: () =>
              throw TimeoutException('FFmpeg download request timed out'));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed: ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      final file = File(outPath);
      final dir = file.parent;
      await dir.create(recursive: true);
      final sink = file.openWrite();
      int received = 0;
      final streamData = response.stream.timeout(
        const Duration(seconds: 60),
        onTimeout: (sinkErr) {
          sinkErr.addError(TimeoutException(
              'FFmpeg download stalled – no data for 60 seconds'));
          sinkErr.close();
        },
      );
      await for (final chunk in streamData) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = ((received / total) * 100).clamp(0, 100).toInt();
          onProgress?.call(pct, 'Downloading');
        }
      }
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  Future<File?> _findFfmpegExe(Directory root) async {
    final isWindows = Platform.isWindows;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (isWindows && name == 'ffmpeg.exe') return entity;
      if (!isWindows && name == 'ffmpeg') return entity;
    }
    return null;
  }
}
