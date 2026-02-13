import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';
import '../models/queue_item.dart';
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

  DownloadService({required this.yt, required this.ffmpeg});

  Future<DownloadResult> download(
    PreviewItem item, {
    required String format,
    required String outputDir,
    required String? ffmpegPath,
    required void Function(int pct, DownloadStatus status) onProgress,
    required DownloadToken token,
  }) async {
    final video = await yt.videos.get(item.url);
    final streams = await yt.videos.streamsClient.getManifest(video.id);

    final safeTitle = _sanitizeFileName(video.title);
    final formatLower = format.toLowerCase();

    final outputFolder = Directory('${outputDir}${Platform.pathSeparator}$formatLower');
    await outputFolder.create(recursive: true);

    Uint8List? thumbBytes = await _fetchThumbnailBytes(video.thumbnails.highResUrl);

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
        if (coverPath != null) ...['-i', coverPath, '-map', '0:a', '-map', '1:v'],
        '-c:a', 'libmp3lame',
        '-b:a', '192k',
        '-metadata', 'title=${video.title}',
        '-metadata', 'artist=${video.author}',
        '-metadata', 'album=${video.author}',
        '-metadata', 'date=${video.uploadDate?.toIso8601String() ?? ''}',
      ];
      if (coverPath != null) {
        args.addAll(<String>['-c:v', 'mjpeg', '-disposition:v', 'attached_pic', '-id3v2_version', '3']);
      }
      args.add(outputPath);
      await ffmpeg.run(args, ffmpegPath: ffmpegPath);

      await _safeDelete(tempMp4Path);
      if (coverPath != null) {
        await _safeDelete(coverPath);
      }

      return DownloadResult(path: outputPath, thumbnail: thumbBytes);
    }

    // For MP4, embed thumbnail if available
    final outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.mp4';
    onProgress(95, DownloadStatus.converting);
    
    if (thumbBytes != null) {
      // Re-encode with embedded thumbnail
      final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
      await ffmpeg.run(
        <String>[
          '-y',
          '-i', tempMp4Path,
          '-i', coverPath!,
          '-map', '0',
          '-map', '1',
          '-c', 'copy',
          '-disposition:v:1', 'attached_pic',
          '-metadata', 'title=${video.title}',
          '-metadata', 'artist=${video.author}',
          '-metadata', 'album=${video.author}',
          '-metadata', 'date=${video.uploadDate?.toIso8601String() ?? ''}',
          outputPath,
        ],
        ffmpegPath: ffmpegPath,
      );
      await _safeDelete(tempMp4Path);
      await _safeDelete(coverPath);
    } else {
      // No thumbnail, just rename
      final tempFile = File(tempMp4Path);
      await tempFile.rename(outputPath);
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
}
