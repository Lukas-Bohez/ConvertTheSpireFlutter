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

    if (formatLower == 'mp3') {
      final audioStream = streams.audioOnly.withHighestBitrate();
      final tempPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.${audioStream.container.name}';
      await _downloadStream(audioStream, tempPath, token, onProgress);

      if (token.cancelled) {
        throw Exception('Cancelled');
      }

      final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
      final outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.mp3';
      onProgress(95, DownloadStatus.converting);
      final args = <String>[
        '-y',
        '-i',
        tempPath,
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

      await _safeDelete(tempPath);
      if (coverPath != null) {
        await _safeDelete(coverPath);
      }

      return DownloadResult(path: outputPath, thumbnail: thumbBytes);
    }

    final videoStream = streams.videoOnly.withHighestBitrate();
    final audioStream = streams.audioOnly.withHighestBitrate();

    final tempVideo = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.video.${videoStream.container.name}';
    final tempAudio = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.audio.${audioStream.container.name}';
    await _downloadStream(videoStream, tempVideo, token, onProgress);
    if (token.cancelled) {
      throw Exception('Cancelled');
    }
    await _downloadStream(audioStream, tempAudio, token, onProgress);

    if (token.cancelled) {
      throw Exception('Cancelled');
    }

    final outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.mp4';
    onProgress(95, DownloadStatus.converting);
    await ffmpeg.run(
      <String>[
        '-y',
        '-i', tempVideo,
        '-i', tempAudio,
        '-c:v', 'copy',
        '-c:a', 'aac',
        outputPath,
      ],
      ffmpegPath: ffmpegPath,
    );

    await _safeDelete(tempVideo);
    await _safeDelete(tempAudio);

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
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9._-]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        buffer.write('_');
      }
    }
    final result = buffer.toString();
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
