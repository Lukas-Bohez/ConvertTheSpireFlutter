import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';
import '../models/queue_item.dart';
import 'android_saf.dart';
import 'ffmpeg_service.dart';

class DownloadToken {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

class DownloadResult {
  final String path;
  final Uint8List? thumbnail;

  const DownloadResult({required this.path, required this.thumbnail});
}

class DownloadService {
  final YoutubeExplode yt;
  final FfmpegService ffmpeg;
  final AndroidSaf _saf = AndroidSaf();

  DownloadService({required this.yt, required this.ffmpeg});

  Future<DownloadResult> download(
    PreviewItem item, {
    required String format,
    required String outputDir,
    required String? ffmpegPath,
    required void Function(int pct, DownloadStatus status) onProgress,
    required DownloadToken token,
  }) async {
    if (kIsWeb) {
      throw Exception('Downloads are not supported on web. Please use the desktop or mobile app.');
    }
    if (outputDir.trim().isEmpty) {
      throw Exception('Download folder is not configured');
    }
    final isSafOutput = _isSafOutput(outputDir);
    final video = await yt.videos.get(item.url);
    final streams = await yt.videos.streamsClient.getManifest(video.id);

    final safeTitle = _sanitizeFileName(video.title);
    final formatLower = format.toLowerCase();
    if (formatLower == 'mp3' && !await ffmpeg.isAvailable(ffmpegPath)) {
      throw Exception('FFmpeg is required for MP3 conversion. Configure it in Settings.');
    }

    // Create output directory if it doesn't exist
    final outputFolder = isSafOutput
      ? await Directory.systemTemp.createTemp('cts_download_')
      : await _resolveOutputFolder(outputDir, formatLower);
    await outputFolder.create(recursive: true);

    Uint8List? thumbBytes = await _fetchThumbnailBytes(video.thumbnails.highResUrl);
    thumbBytes = _prepareCoverBytes(thumbBytes);
    final thumbPath = await _writeThumbnailFile(outputFolder.path, safeTitle, thumbBytes);

    final needsMp4Embed = formatLower == 'mp4' && thumbBytes != null;
    if (needsMp4Embed && !await ffmpeg.isAvailable(ffmpegPath)) {
      throw Exception('FFmpeg is required to embed MP4 thumbnails. Configure it in Settings.');
    }

    // Always download muxed MP4 first (video + audio in one stream)
    final muxedStream = streams.muxed.withHighestBitrate();
    final tempMp4Path = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.temp.mp4';
    
    // Download muxed stream (0-90% of total progress)
    await _downloadStream(muxedStream, tempMp4Path, token, (pct, status) {
      final adjustedPct = (pct * 0.9).toInt(); // 0-90%
      onProgress(adjustedPct, status);
    });

    if (token.cancelled) {
      await _safeDelete(tempMp4Path);
      throw Exception('Cancelled');
    }

    if (formatLower == 'mp3') {
      // Convert MP4 to MP3
      final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
      final outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.mp3';
      onProgress(95, DownloadStatus.converting);
      final args = <String>[
        '-y',
        '-i',
        tempMp4Path,
        if (coverPath != null) ...[
          '-i',
          coverPath,
          '-map',
          '0:a',
          '-map',
          '1:v',
          '-c:v',
          'mjpeg',
          '-disposition:v',
          'attached_pic',
          '-metadata:s:v',
          'title=Album cover',
          '-metadata:s:v',
          'comment=Cover (front)',
        ],
        '-c:a',
        'libmp3lame',
        '-b:a',
        '192k',
        '-id3v2_version',
        '3',
        '-metadata',
        'title=${video.title}',
        '-metadata',
        'artist=${video.author}',
        '-metadata',
        'album=${video.author}',
        '-metadata',
        'date=${video.uploadDate?.toIso8601String() ?? ''}',
        outputPath,
      ];
      await ffmpeg.run(args, ffmpegPath: ffmpegPath);

      await _safeDelete(tempMp4Path);
      if (coverPath != null) {
        await _safeDelete(coverPath);
      }
      if (thumbPath != null) {
        await _safeDelete(thumbPath);
      }

      if (isSafOutput) {
        final destUri = await _copyFileToSaf(
          treeUri: outputDir,
          sourcePath: outputPath,
          safeTitle: safeTitle,
          formatLower: formatLower,
        );
        await _safeDelete(outputPath);
        await _safeDeleteDir(outputFolder.path);
        return DownloadResult(path: destUri ?? '$safeTitle.$formatLower', thumbnail: thumbBytes);
      }

      return DownloadResult(path: outputPath, thumbnail: thumbBytes);
    }

    final outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.mp4';
    onProgress(95, DownloadStatus.converting);
    if (needsMp4Embed) {
      final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
      await _embedMp4Cover(tempMp4Path, outputPath, coverPath, ffmpegPath: ffmpegPath);
      await _safeDelete(tempMp4Path);
      if (coverPath != null) {
        await _safeDelete(coverPath);
      }
      if (thumbPath != null) {
        await _safeDelete(thumbPath);
      }
    } else {
      // For MP4 without thumbnail embedding, just rename the temp file to final output
      final tempFile = File(tempMp4Path);
      await tempFile.rename(outputPath);
    }

    if (isSafOutput) {
      final destUri = await _copyFileToSaf(
        treeUri: outputDir,
        sourcePath: outputPath,
        safeTitle: safeTitle,
        formatLower: formatLower,
      );
      await _safeDelete(outputPath);
      await _safeDeleteDir(outputFolder.path);
      return DownloadResult(path: destUri ?? '$safeTitle.$formatLower', thumbnail: thumbBytes);
    }

    return DownloadResult(path: outputPath, thumbnail: thumbBytes);
  }

  Future<void> _downloadStream(
    StreamInfo stream,
    String outputPath,
    DownloadToken token,
    void Function(int pct, DownloadStatus status) onProgress,
  ) async {
    final file = File(outputPath);
    final sink = file.openWrite();
    try {
      final streamData = yt.videos.streamsClient.get(stream);
      final total = stream.size.totalBytes;
      int received = 0;
      onProgress(0, DownloadStatus.downloading);

      await for (final data in streamData) {
        if (token.cancelled) {
          await sink.close();
          await _safeDelete(outputPath);
          throw Exception('Cancelled');
        }
        sink.add(data);
        received += data.length;
        if (total > 0) {
          final pct = ((received / total) * 100).clamp(0, 100).toInt();
          onProgress(pct, DownloadStatus.downloading);
        }
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try { await sink.close(); } catch (_) {}
      rethrow;
    }
  }

  Future<Uint8List?> _fetchThumbnailBytes(String? url) async {
    if (url == null || url.isEmpty) {
      return null;
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _writeCoverFile(String dir, String name, Uint8List? bytes) async {
    if (bytes == null) {
      return null;
    }
    final path = '$dir${Platform.pathSeparator}$name.cover.jpg';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<String?> _writeThumbnailFile(String dir, String name, Uint8List? bytes) async {
    if (bytes == null) {
      return null;
    }
    final path = '$dir${Platform.pathSeparator}$name.thumbnail.jpg';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Uint8List? _prepareCoverBytes(Uint8List? bytes) {
    if (bytes == null) {
      return null;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return bytes;
    }
    
    // Detect and crop black bars first
    final trimmed = _trimBlackBars(decoded);
    
    // Now crop to center square from the trimmed image
    final size = trimmed.width < trimmed.height ? trimmed.width : trimmed.height;
    final offsetX = (trimmed.width - size) ~/ 2;
    final offsetY = (trimmed.height - size) ~/ 2;
    final cropped = img.copyCrop(trimmed, x: offsetX, y: offsetY, width: size, height: size);
    
    // Resize to target size if needed
    final targetSize = size > 1200 ? 1200 : size;
    final resized = size > targetSize
        ? img.copyResize(cropped, width: targetSize, height: targetSize, interpolation: img.Interpolation.cubic)
        : cropped;
    final encoded = img.encodeJpg(resized, quality: 90);
    return Uint8List.fromList(encoded);
  }

  img.Image _trimBlackBars(img.Image image) {
    // Find content bounds by detecting non-black pixels
    int minX = image.width;
    int minY = image.height;
    int maxX = 0;
    int maxY = 0;
    
    const blackThreshold = 20; // Pixels darker than this are considered black
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // If pixel is not black
        if (r > blackThreshold || g > blackThreshold || b > blackThreshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    
    // If we found content bounds, crop to them
    if (maxX > minX && maxY > minY) {
      final width = maxX - minX + 1;
      final height = maxY - minY + 1;
      return img.copyCrop(image, x: minX, y: minY, width: width, height: height);
    }
    
    // No black bars detected, return original
    return image;
  }

  Future<void> _embedMp4Cover(
    String inputPath,
    String outputPath,
    String? coverPath, {
    required String? ffmpegPath,
  }) async {
    if (coverPath == null) {
      final tempFile = File(inputPath);
      await tempFile.rename(outputPath);
      return;
    }
    final args = <String>[
      '-y',
      '-i',
      inputPath,
      '-i',
      coverPath,
      '-map',
      '0',
      '-map',
      '1',
      '-c',
      'copy',
      '-c:v:1',
      'mjpeg',
      '-disposition:v:1',
      'attached_pic',
      '-metadata:s:v:1',
      'title=Album cover',
      '-metadata:s:v:1',
      'comment=Cover (front)',
      outputPath,
    ];
    await ffmpeg.run(args, ffmpegPath: ffmpegPath);
  }

  Future<Directory> _resolveOutputFolder(String outputDir, String formatLower) async {
    final base = Directory(outputDir);
    if (formatLower == 'mp3' || formatLower == 'mp4') {
      return Directory('${base.path}${Platform.pathSeparator}$formatLower');
    }
    return base;
  }

  bool _isSafOutput(String outputDir) {
    return !kIsWeb && Platform.isAndroid && outputDir.startsWith('content://');
  }

  Future<String?> _copyFileToSaf({
    required String treeUri,
    required String sourcePath,
    required String safeTitle,
    required String formatLower,
  }) async {
    final displayName = '$safeTitle.$formatLower';
    final mimeType = formatLower == 'mp3' ? 'audio/mpeg' : 'video/mp4';
    final subdir = (formatLower == 'mp3' || formatLower == 'mp4') ? formatLower : null;
    return _saf.copyToTree(
      treeUri: treeUri,
      sourcePath: sourcePath,
      displayName: displayName,
      mimeType: mimeType,
      subdir: subdir,
    );
  }

  String _sanitizeFileName(String value) {
    // Remove only filesystem-unsafe characters but keep Unicode (Japanese, etc.)
    // Unsafe characters on Windows/Linux: < > : " / \\ | ? *
    final unsafe = RegExp(r'[<>:"/\\|?*]');
    String result = value.replaceAll(unsafe, '_');
    // Also replace control characters
    result = result.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_');
    // Trim whitespace and dots from ends (Windows doesn't like trailing dots)
    result = result.trim().replaceAll(RegExp(r'\.+$'), '');
    return result.isEmpty ? 'download' : result;
  }

  Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> _safeDeleteDir(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
