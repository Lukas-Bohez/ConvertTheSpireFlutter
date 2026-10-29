import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../config/build_flags.dart';
import '../utils/cpu_arch.dart';
import 'platform_dirs.dart';

class InstallerService {
  /// Where FFmpeg is downloaded from when the computer has none; null where
  /// the app does not download it (macOS: Homebrew).
  ///
  /// Linux gets BtbN's build with shared libraries: it runs on any
  /// distribution (the libraries come along in its lib folder) and is half
  /// the size of the static one.
  static Uri? ffmpegDownloadUrl({bool? windows, bool? linux, bool? arm64}) {
    if (windows ?? (!kIsWeb && Platform.isWindows)) {
      return Uri.parse(
          'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip');
    }
    if (linux ?? (!kIsWeb && Platform.isLinux)) {
      final arch = (arm64 ?? isLinuxArm64) ? 'linuxarm64' : 'linux64';
      return Uri.parse('https://github.com/BtbN/FFmpeg-Builds/releases/'
          'download/latest/ffmpeg-master-latest-$arch-gpl-shared.tar.xz');
    }
    return null;
  }

  Future<String> installFfmpeg({
    required Uri url,
    String? checksumSha256,
    void Function(int percent, String message)? onProgress,
  }) async {
    if (kIsWeb) {
      throw Exception('FFmpeg installation is not available on web.');
    }
    // FFmpeg comes in the package there (see FfmpegService.bundledPath).
    if (kMsStoreBuild) throw Exception(storeBuildNoDownloads);
    var support = await PlatformDirs.getAppSupportDir();
    support ??= await PlatformDirs.getFilesDir();
    support ??= await Directory.systemTemp.createTemp('ffmpeg_install');
    final downloadDir =
        Directory('${support.path}${Platform.pathSeparator}ffmpeg');
    await downloadDir.create(recursive: true);
    final isTarXz = url.path.endsWith('.tar.xz');
    final archivePath = '${downloadDir.path}${Platform.pathSeparator}'
        '${isTarXz ? 'ffmpeg.tar.xz' : 'ffmpeg.zip'}';

    onProgress?.call(0, 'Downloading');
    final archiveFile =
        await _downloadToFile(url, archivePath, onProgress: onProgress);

    if (checksumSha256 != null && checksumSha256.trim().isNotEmpty) {
      final digestObj = await sha256.bind(archiveFile.openRead()).first;
      final digest = digestObj.toString();
      if (digest.toLowerCase() != checksumSha256.toLowerCase()) {
        throw Exception('Checksum mismatch');
      }
    }

    onProgress?.call(60, 'Extracting');
    if (isTarXz) {
      await _extractTarXz(archiveFile, downloadDir);
    } else {
      final bytes = await archiveFile.readAsBytes();
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
    }

    final ffmpegExe = await _findFfmpegExe(downloadDir);
    if (ffmpegExe == null) {
      throw Exception(
          '${Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg'} not found after extraction');
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
              'FFmpeg download stalled - no data for 60 seconds'));
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

  /// Unpacks a Linux FFmpeg build. The system's tar keeps the library
  /// symlinks and the programs' permissions, and is much faster than
  /// decompressing the 70 MB in Dart; the archive package is the fallback.
  Future<void> _extractTarXz(File archive, Directory dir) async {
    try {
      final result =
          await Process.run('tar', ['-xJf', archive.path, '-C', dir.path]);
      if (result.exitCode == 0) {
        await archive.delete();
        return;
      }
    } catch (_) {}
    await extractFileToDisk(archive.path, dir.path);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.parent.path.endsWith('bin')) {
        await Process.run('chmod', ['+x', entity.path]);
      }
    }
    await archive.delete();
  }

  Future<File?> _findFfmpegExe(Directory root) async {
    final path = await findFfmpegIn(root, windows: Platform.isWindows);
    return path == null ? null : File(path);
  }

  /// The FFmpeg program in a downloaded build under [root]: `ffmpeg.exe` on
  /// Windows, `bin/ffmpeg` elsewhere (the Linux build also has a share
  /// folder named ffmpeg).
  static Future<String?> findFfmpegIn(Directory root,
      {required bool windows}) async {
    if (!await root.exists()) return null;
    String? other;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final segments = entity.uri.pathSegments;
      final name = segments.last.toLowerCase();
      if (windows) {
        if (name == 'ffmpeg.exe') return entity.path;
        continue;
      }
      if (name != 'ffmpeg') continue;
      if (segments.length > 1 && segments[segments.length - 2] == 'bin') {
        return entity.path;
      }
      other ??= entity.path;
    }
    return other;
  }
}
