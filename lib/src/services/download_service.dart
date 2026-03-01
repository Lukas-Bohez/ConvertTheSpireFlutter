import 'dart:async';
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

  /// Supported download formats.
  static const supportedFormats = {'mp3', 'm4a', 'mp4'};

  Future<DownloadResult> download(
    PreviewItem item, {
    required String format,
    required String outputDir,
    required String? ffmpegPath,
    required void Function(int pct, DownloadStatus status) onProgress,
    required DownloadToken token,
    String preferredVideoQuality = '720p',
    int preferredAudioBitrate = 192,
  }) async {
    if (kIsWeb) {
      throw Exception('Downloads are not supported on web. Please use the desktop or mobile app.');
    }
    final formatLower = format.toLowerCase();
    if (!supportedFormats.contains(formatLower)) {
      throw Exception('Unsupported format: $format. Use MP3, M4A, or MP4.');
    }
    final isAndroid = Platform.isAndroid;
    final useMediaStoreOnly = isAndroid && outputDir.trim().isEmpty;
    if (outputDir.trim().isEmpty && !useMediaStoreOnly) {
      throw Exception('Download folder is not configured. Set one in Settings.');
    }
    final isSafOutput = _isSafOutput(outputDir);
    final video = await yt.videos.get(item.url)
        .timeout(const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Timed out fetching video info'));
    // Fetch stream manifest with retry using different YouTube API clients
    StreamManifest streams;
    try {
      streams = await yt.videos.streamsClient.getManifest(video.id)
          .timeout(const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException('Timed out fetching stream manifest'));
    } catch (_) {
      // Retry with safari + androidVr clients for broader stream availability
      streams = await yt.videos.streamsClient.getManifest(
        video.id,
        ytClients: [YoutubeApiClient.safari, YoutubeApiClient.androidVr],
      ).timeout(const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException('Timed out fetching stream manifest (retry)'));
    }

    final safeTitle = _sanitizeFileName(video.title);
    final needsConversion = formatLower != 'mp4';
    // Muxed streams are limited to 360p. Anything above 360p requires
    // separate video + audio streams merged via FFmpeg.
    final wantHd = !needsConversion && _qualityToHeight(preferredVideoQuality) > 360;
    if ((needsConversion || wantHd) && !await ffmpeg.isAvailable(ffmpegPath)) {
      if (wantHd) {
        // Fall back to muxed (360p max) if FFmpeg unavailable for merge
      } else {
        throw Exception('FFmpeg is required for $formatLower conversion. Configure it in Settings.');
      }
    }
    final bool ffmpegAvailable = await ffmpeg.isAvailable(ffmpegPath);

    // Create output directory
    final outputFolder = (isSafOutput || useMediaStoreOnly)
      ? await _resolveTempFolder()
      : await _resolveOutputFolder(outputDir, formatLower);
    await outputFolder.create(recursive: true);

    // Track all temp files so we can clean up on success OR failure
    final tempFiles = <String>[];

    Uint8List? thumbBytes = await _fetchThumbnailBytes(video.thumbnails.highResUrl);
    thumbBytes = _prepareCoverBytes(thumbBytes);
    final thumbPath = await _writeThumbnailFile(outputFolder.path, safeTitle, thumbBytes);
    if (thumbPath != null) tempFiles.add(thumbPath);

    final needsMp4Embed = formatLower == 'mp4' && thumbBytes != null;

    // Determine download strategy:
    // (a) Audio conversion (MP3/M4A): prefer muxed, fall back audio-only
    // (b) MP4 480p+: download separate video+audio and merge via FFmpeg
    //     (muxed streams are capped at 360p by YouTube)
    // (c) MP4 360p: use muxed stream directly
    final StreamInfo sourceStream;
    final String tempFilePath;
    StreamInfo? separateAudioStream;  // non-null when doing HD merge
    String? tempAudioPath;

    if (needsConversion) {
      // Audio formats: prefer muxed (reliable), fall back to audio-only
      if (streams.muxed.isNotEmpty) {
        sourceStream = streams.muxed.withHighestBitrate();
        tempFilePath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.temp.mp4';
      } else if (streams.audioOnly.isNotEmpty) {
        sourceStream = streams.audioOnly.withHighestBitrate();
        tempFilePath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.temp.webm';
      } else {
        throw Exception('No downloadable streams found for this video. It may be region-restricted or DRM-protected.');
      }
    } else if (wantHd && ffmpegAvailable && streams.videoOnly.isNotEmpty && streams.audioOnly.isNotEmpty) {
      // HD MP4: download separate video + audio, then merge
      final targetHeight = _qualityToHeight(preferredVideoQuality);
      final videoStream = _pickBestVideoStream(streams.videoOnly, targetHeight);
      sourceStream = videoStream;
      tempFilePath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.temp.video.${_containerExt(videoStream)}';
      separateAudioStream = streams.audioOnly.withHighestBitrate();
      tempAudioPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.temp.audio.${_containerExt(separateAudioStream)}';
    } else {
      // Standard muxed MP4 (720p max)
      if (streams.muxed.isEmpty) {
        throw Exception('No downloadable video streams found for this video. It may be region-restricted or DRM-protected.');
      }
      sourceStream = streams.muxed.withHighestBitrate();
      tempFilePath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.temp.mp4';
    }
    tempFiles.add(tempFilePath);
    if (tempAudioPath != null) tempFiles.add(tempAudioPath);

    try {
      // Download source stream
      final bool isHdMerge = separateAudioStream != null;
      if (isHdMerge) {
        // Download video (0-60%) then audio (60-80%)
        await _downloadStream(sourceStream, tempFilePath, token, (pct, status) {
          final adjustedPct = (pct * 0.6).toInt();
          onProgress(adjustedPct, status);
        });
        if (token.cancelled) throw Exception('Cancelled');
        await _downloadStream(separateAudioStream, tempAudioPath!, token, (pct, status) {
          final adjustedPct = 60 + (pct * 0.2).toInt();
          onProgress(adjustedPct, status);
        });
      } else {
        // Single stream download (0-90%)
        await _downloadStream(sourceStream, tempFilePath, token, (pct, status) {
          final adjustedPct = (pct * 0.9).toInt();
          onProgress(adjustedPct, status);
        });
      }

      if (token.cancelled) {
        throw Exception('Cancelled');
      }

      String outputPath;

      if (needsConversion) {
        // ── Convert to the requested audio format ─────────────────────
        final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
        if (coverPath != null) tempFiles.add(coverPath);
        outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.$formatLower';
        onProgress(95, DownloadStatus.converting);

        final args = _buildAudioConvertArgs(
          inputPath: tempFilePath,
          outputPath: outputPath,
          format: formatLower,
          coverPath: coverPath,
          title: video.title,
          artist: video.author,
          date: video.uploadDate?.toIso8601String() ?? '',
          bitrate: preferredAudioBitrate,
        );
        await ffmpeg.run(args, ffmpegPath: ffmpegPath);

        // Verify the output file was actually created
        if (!await File(outputPath).exists()) {
          throw Exception('FFmpeg completed but output file was not created for format: $formatLower');
        }
      } else {
        // ── MP4: keep as video ────────────────────────────────────────
        outputPath = '${outputFolder.path}${Platform.pathSeparator}$safeTitle.mp4';
        onProgress(isHdMerge ? 85 : 95, DownloadStatus.converting);
        if (isHdMerge) {
          // Merge separate video + audio streams into final MP4
          final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
          if (coverPath != null) tempFiles.add(coverPath);
          await _mergeVideoAudio(
            videoPath: tempFilePath,
            audioPath: tempAudioPath!,
            outputPath: outputPath,
            coverPath: coverPath,
            ffmpegPath: ffmpegPath,
          );
        } else if (needsMp4Embed) {
          final coverPath = await _writeCoverFile(outputFolder.path, safeTitle, thumbBytes);
          if (coverPath != null) tempFiles.add(coverPath);
          await _embedMp4Cover(tempFilePath, outputPath, coverPath, ffmpegPath: ffmpegPath);
        } else {
          await File(tempFilePath).rename(outputPath);
          tempFiles.remove(tempFilePath); // renamed, no longer needs cleanup
        }
      }

      // Clean up all temp files on success
      for (final f in tempFiles) {
        await _safeDelete(f);
      }

      return _finalizeOutput(
        outputPath: outputPath,
        outputDir: outputDir,
        safeTitle: safeTitle,
        formatLower: formatLower,
        thumbBytes: thumbBytes,
        isSafOutput: isSafOutput,
        useMediaStoreOnly: useMediaStoreOnly,
        outputFolder: outputFolder,
      );
    } catch (e) {
      // Clean up ALL temp files on failure so we don't leave .webm/.jpg garbage
      for (final f in tempFiles) {
        await _safeDelete(f);
      }
      rethrow;
    }
  }

  /// Build FFmpeg arguments to convert source audio to the requested format
  /// with metadata and optional cover art embedding.
  /// Input may be WebM (audio-only) or MP4 (muxed); FFmpeg extracts audio either way.
  List<String> _buildAudioConvertArgs({
    required String inputPath,
    required String outputPath,
    required String format,
    required String? coverPath,
    required String title,
    required String artist,
    required String date,
    int bitrate = 192,
  }) {
    // Cover embedding support:
    //   MP3 – ID3v2 attached picture (mjpeg + attached_pic)
    //   M4A – MP4 container (mjpeg + attached_pic)
    final supportsCoverEmbed = {'mp3', 'm4a'}.contains(format);
    final embedCover = coverPath != null && supportsCoverEmbed;

    final args = <String>['-y', '-i', inputPath];

    if (embedCover) {
      args.addAll(['-i', coverPath]);
      args.addAll(['-map', '0:a', '-map', '1:v']);
      args.addAll(['-c:v', 'mjpeg', '-disposition:v', 'attached_pic']);
      args.addAll(['-metadata:s:v', 'title=Album cover', '-metadata:s:v', 'comment=Cover (front)']);
    } else {
      // No cover – explicitly map only the audio stream (important when input
      // is a muxed MP4 that also contains a video track).
      args.addAll(['-map', '0:a']);
    }

    // Audio codec + container settings
    final bitrateStr = '${bitrate.clamp(64, 320)}k';
    switch (format) {
      case 'mp3':
        args.addAll(['-c:a', 'libmp3lame', '-b:a', bitrateStr, '-id3v2_version', '3']);
        break;
      case 'm4a':
        args.addAll(['-c:a', 'aac', '-b:a', bitrateStr]);
        break;
      default:
        args.addAll(['-c:a', 'copy']);
    }

    // Metadata
    args.addAll([
      '-metadata', 'title=$title',
      '-metadata', 'artist=$artist',
      '-metadata', 'album=$artist',
      '-metadata', 'date=$date',
    ]);

    args.add(outputPath);
    return args;
  }

  /// Move the final output file to SAF / Downloads / local, cleaning up temp.
  Future<DownloadResult> _finalizeOutput({
    required String outputPath,
    required String outputDir,
    required String safeTitle,
    required String formatLower,
    required Uint8List? thumbBytes,
    required bool isSafOutput,
    required bool useMediaStoreOnly,
    required Directory outputFolder,
  }) async {
    if (isSafOutput) {
      final destUri = await _copyFileToSaf(
        treeUri: outputDir,
        sourcePath: outputPath,
        safeTitle: safeTitle,
        formatLower: formatLower,
      );
      if (destUri == null) {
        final fallbackUri = await _copyFileToDownloads(
          sourcePath: outputPath,
          safeTitle: safeTitle,
          formatLower: formatLower,
        );
        if (fallbackUri == null) {
          throw Exception('Failed to save file to selected folder');
        }
        await _safeDelete(outputPath);
        await _safeDeleteDir(outputFolder.path);
        return DownloadResult(path: fallbackUri, thumbnail: thumbBytes);
      }
      await _safeDelete(outputPath);
      await _safeDeleteDir(outputFolder.path);
      return DownloadResult(path: destUri, thumbnail: thumbBytes);
    }

    if (useMediaStoreOnly) {
      final fallbackUri = await _copyFileToDownloads(
        sourcePath: outputPath,
        safeTitle: safeTitle,
        formatLower: formatLower,
      );
      if (fallbackUri == null) {
        throw Exception('Failed to save file to Downloads');
      }
      await _safeDelete(outputPath);
      await _safeDeleteDir(outputFolder.path);
      return DownloadResult(path: fallbackUri, thumbnail: thumbBytes);
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
      final rawStream = yt.videos.streamsClient.get(stream);
      // Dynamic stall detection: scale timeout based on stream size.
      // Larger HD streams need more time as CDNs can be slower for adaptive
      // streams. Small (<50MB): 60s, Medium (50-200MB): 120s, Large (>200MB): 180s
      final sizeMb = stream.size.totalBytes / (1024 * 1024);
      final stallSeconds = sizeMb > 200 ? 180 : sizeMb > 50 ? 120 : 60;
      final streamData = rawStream.timeout(
        Duration(seconds: stallSeconds),
        onTimeout: (sink) {
          sink.addError(TimeoutException('Download stalled – no data received for $stallSeconds seconds'));
          sink.close();
        },
      );
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
    // Organise into sub-folders by format
    return Directory('${base.path}${Platform.pathSeparator}$formatLower');
  }

  Future<Directory> _resolveTempFolder() async {
    final temp = Directory.systemTemp;
    final dir = Directory('${temp.path}${Platform.pathSeparator}cts_download');
    await dir.create(recursive: true);
    return dir;
  }

  bool _isSafOutput(String outputDir) {
    return !kIsWeb && Platform.isAndroid && outputDir.startsWith('content://');
  }

  static String _mimeForFormat(String fmt) {
    switch (fmt) {
      case 'mp3':  return 'audio/mpeg';
      case 'm4a':  return 'audio/mp4';
      case 'mp4':  return 'video/mp4';
      default:     return 'application/octet-stream';
    }
  }

  Future<String?> _copyFileToSaf({
    required String treeUri,
    required String sourcePath,
    required String safeTitle,
    required String formatLower,
  }) async {
    final displayName = '$safeTitle.$formatLower';
    final mimeType = _mimeForFormat(formatLower);
    return _saf.copyToTree(
      treeUri: treeUri,
      sourcePath: sourcePath,
      displayName: displayName,
      mimeType: mimeType,
      subdir: formatLower,
    );
  }

  Future<String?> _copyFileToDownloads({
    required String sourcePath,
    required String safeTitle,
    required String formatLower,
  }) async {
    final displayName = '$safeTitle.$formatLower';
    final mimeType = _mimeForFormat(formatLower);
    return _saf.copyToDownloads(
      sourcePath: sourcePath,
      displayName: displayName,
      mimeType: mimeType,
      subdir: formatLower,
    );
  }

  /// Convert quality string like '1080p' to pixel height.
  static int _qualityToHeight(String quality) {
    switch (quality) {
      case '360p': return 360;
      case '480p': return 480;
      case '720p': return 720;
      case '1080p': return 1080;
      case '1440p': return 1440;
      case '2160p': return 2160;
      case 'best': return 9999;
      default: return 720;
    }
  }

  /// Pick the best video-only stream whose height is ≤ targetHeight.
  /// Strongly prefers MP4 (H.264) container for direct copy into MP4 output.
  /// Falls back to WebM (VP9) only if no MP4 stream is available at target.
  VideoOnlyStreamInfo _pickBestVideoStream(
    Iterable<VideoOnlyStreamInfo> streams,
    int targetHeight,
  ) {
    // Separate MP4 (H.264) and other (WebM/VP9) streams
    final mp4Streams = streams
        .where((s) => s.container.name.toLowerCase().contains('mp4'))
        .toList()
      ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
    final allSorted = streams.toList()
      ..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

    if (targetHeight >= 9999) {
      // 'best' quality: prefer highest-res MP4, fall back to any
      if (mp4Streams.isNotEmpty) return mp4Streams.first;
      return allSorted.first;
    }

    // Prefer MP4/H.264 stream at or below target height
    for (final s in mp4Streams) {
      if (s.videoResolution.height <= targetHeight) return s;
    }

    // No MP4 at or below target; try any codec
    for (final s in allSorted) {
      if (s.videoResolution.height <= targetHeight) return s;
    }

    // Nothing ≤ target; return the lowest available
    return allSorted.last;
  }

  /// Determine a container extension from a StreamInfo's codec/container.
  String _containerExt(StreamInfo stream) {
    final mime = stream.container.name.toLowerCase();
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('mp4')) return 'mp4';
    return 'mp4';
  }

  /// Merge separate video and audio files into a single MP4 using FFmpeg.
  /// Handles codec mismatch: VP9/WebM video is re-encoded to H.264 for MP4
  /// output, while H.264/MP4 video is stream-copied (fast, lossless).
  Future<void> _mergeVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required String? coverPath,
    required String? ffmpegPath,
  }) async {
    // Detect codec mismatch: VP9/WebM can't be stream-copied into MP4
    final videoIsWebm = videoPath.toLowerCase().endsWith('.webm');
    final outputIsMp4 = outputPath.toLowerCase().endsWith('.mp4');
    final needsVideoReencode = videoIsWebm && outputIsMp4;
    final videoCodec = needsVideoReencode ? 'libx264' : 'copy';

    final args = <String>['-y', '-i', videoPath, '-i', audioPath];
    if (coverPath != null) {
      args.addAll(['-i', coverPath]);
      args.addAll(['-map', '0:v', '-map', '1:a', '-map', '2:v']);
      args.addAll(['-c:v:0', videoCodec, '-c:a', 'aac', '-c:v:1', 'mjpeg',
                   '-disposition:v:1', 'attached_pic',
                   '-metadata:s:v:1', 'title=Album cover',
                   '-metadata:s:v:1', 'comment=Cover (front)']);
    } else {
      args.addAll(['-map', '0:v', '-map', '1:a']);
      args.addAll(['-c:v', videoCodec, '-c:a', 'aac']);
    }
    if (needsVideoReencode) {
      // Reasonable H.264 encoding settings for re-encoding VP9
      args.addAll(['-preset', 'medium', '-crf', '23']);
    }
    args.addAll(['-movflags', '+faststart', outputPath]);
    await ffmpeg.run(args, ffmpegPath: ffmpegPath);
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
