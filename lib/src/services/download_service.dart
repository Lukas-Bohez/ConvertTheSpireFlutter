import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';
import '../models/queue_item.dart';
import 'android_saf.dart';
import 'ffmpeg_service.dart';
import 'yt_dlp_service.dart';

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
  final YtDlpService ytDlp;
  final AndroidSaf _saf = AndroidSaf();

  DownloadService({required this.yt, required this.ffmpeg, required this.ytDlp});

  /// Supported download formats.
  static const supportedFormats = {'mp3', 'm4a', 'mp4'};

  /// Known difficult sites that require browser-like headers and/or cookies.
  static const Map<String, String> knownDifficultSites = {
    'hianime.to':
        'Uses Cloudflare bot protection \u2014 cookies required.',
    'crunchyroll.com':
        'Requires authentication. Sign in via browser and export cookies.',
    'funimation.com':
        'Requires authentication and may be geo-restricted.',
    'bilibili.com':
        'May require cookies for high-quality streams.',
    'nicovideo.jp':
        'Requires login cookies for most content.',
  };

  /// Browser-like headers for difficult sites.
  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Returns the referer header for a known difficult site, or null.
  static String? _refererForUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('hianime.to')) return 'https://hianime.to/';
    if (host.contains('crunchyroll.com')) return 'https://www.crunchyroll.com/';
    if (host.contains('bilibili.com')) return 'https://www.bilibili.com/';
    return null;
  }

  /// Whether a URL belongs to a known difficult site.
  static bool isDifficultSite(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return knownDifficultSites.keys.any((domain) => host.contains(domain));
  }

  /// Translate common yt-dlp/download errors into user-friendly messages.
  static String translateError(String error) {
    if (error.contains('403') || error.contains('Forbidden')) {
      return 'Access blocked by site. Try providing browser cookies in Settings.';
    }
    if (error.contains('No video formats found')) {
      return 'No video found. This site may require cookies.';
    }
    if (error.contains('This video is unavailable') ||
        error.contains('Video unavailable')) {
      return 'Video unavailable in your region or removed.';
    }
    if (error.contains('Unsupported URL') ||
        error.contains('is not a valid URL')) {
      return 'This URL is not supported by yt-dlp.';
    }
    if (error.contains('geographic restriction') ||
        error.contains('not available in your country')) {
      return 'This content is geo-restricted and not available in your region.';
    }
    if (error.contains('Private video') ||
        error.contains('login required') ||
        error.contains('Sign in')) {
      return 'This content is private or requires authentication.';
    }
    if (error.contains('429') || error.contains('Too Many Requests')) {
      return 'Rate limited by the server. Please wait a minute and try again.';
    }
    return error;
  }

  /// Download a non-YouTube URL using yt-dlp exclusively.
  ///
  /// This is the entry point for generic sites (Vimeo, Dailymotion, anime
  /// sites, etc.).  YouTube URLs should still use [download] which goes
  /// through youtube_explode_dart first with a yt-dlp fast-path.
  Future<DownloadResult> downloadGeneric(
    PreviewItem item, {
    required String format,
    required String outputDir,
    required String? ffmpegPath,
    required void Function(int pct, DownloadStatus status) onProgress,
    required DownloadToken token,
    String? ytDlpPath,
    String preferredVideoQuality = '720p',
    int preferredAudioBitrate = 192,
    String? cookiesFile,
    String? cookiesFromBrowser,
  }) async {
    if (kIsWeb) {
      throw Exception('Downloads are not supported on web.');
    }
    final formatLower = format.toLowerCase();
    if (!supportedFormats.contains(formatLower)) {
      throw Exception('Unsupported format: $format. Use MP3, M4A, or MP4.');
    }

    // yt-dlp is required for non-YouTube downloads
    final resolvedYtDlp = await ytDlp.resolveAvailablePath(ytDlpPath);
    if (resolvedYtDlp == null) {
      throw Exception(
        'yt-dlp is required to download from this site but was not found. '
        'Go to Settings and ensure yt-dlp is installed.',
      );
    }

    final isAndroid = !kIsWeb && Platform.isAndroid;
    final useMediaStoreOnly = isAndroid && outputDir.trim().isEmpty;
    if (outputDir.trim().isEmpty && !useMediaStoreOnly) {
      throw Exception('Download folder is not configured. Set one in Settings.');
    }
    final isSafOutput = _isSafOutput(outputDir);

    final safeTitle = _sanitizeFileName(item.title);

    onProgress(0, DownloadStatus.downloading);

    // Resolve output folder
    final outputFolder = (isSafOutput || useMediaStoreOnly)
        ? await _resolveTempFolder()
        : await _resolveOutputFolder(outputDir, formatLower);
    await outputFolder.create(recursive: true);

    final outputPath =
        '${outputFolder.path}${Platform.pathSeparator}$safeTitle.$formatLower';

    // Build browser-like headers for difficult sites
    final headers = <String, String>{..._browserHeaders};
    final referer = _refererForUrl(item.url);
    if (referer != null) headers['Referer'] = referer;

    try {
      await ytDlp.download(
        url: item.url,
        outputPath: outputPath,
        format: formatLower,
        ffmpegPath: ffmpegPath,
        ytDlpPath: resolvedYtDlp,
        videoQuality: preferredVideoQuality,
        audioBitrate: preferredAudioBitrate,
        isCancelled: () => token.cancelled,
        extraHeaders: isDifficultSite(item.url) ? headers : null,
        cookiesFile: cookiesFile,
        cookiesFromBrowser: cookiesFromBrowser,
        onProgress: (pct) {
          final adjusted = (pct * 0.95).toInt();
          final status = pct >= 100
              ? DownloadStatus.converting
              : DownloadStatus.downloading;
          onProgress(adjusted, status);
        },
      );

      if (token.cancelled) {
        await _safeDelete(outputPath);
        throw Exception('Cancelled');
      }

      onProgress(98, DownloadStatus.converting);

      return _finalizeOutput(
        outputPath: outputPath,
        outputDir: outputDir,
        safeTitle: safeTitle,
        formatLower: formatLower,
        thumbBytes: null,
        isSafOutput: isSafOutput,
        useMediaStoreOnly: useMediaStoreOnly,
        outputFolder: outputFolder,
      );
    } catch (e) {
      await _safeDelete(outputPath);
      final msg = e.toString();

      // Retry with force-generic-extractor for difficult sites
      if (!token.cancelled &&
          (msg.contains('Unsupported URL') ||
              msg.contains('No video formats found') ||
              msg.contains('403'))) {
        try {
          debugPrint('yt-dlp: retrying with --force-generic-extractor');
          await ytDlp.download(
            url: item.url,
            outputPath: outputPath,
            format: formatLower,
            ffmpegPath: ffmpegPath,
            ytDlpPath: resolvedYtDlp,
            videoQuality: preferredVideoQuality,
            audioBitrate: preferredAudioBitrate,
            isCancelled: () => token.cancelled,
            extraHeaders: headers,
            cookiesFile: cookiesFile,
            cookiesFromBrowser: cookiesFromBrowser,
            forceGenericExtractor: true,
            onProgress: (pct) {
              onProgress((pct * 0.95).toInt(),
                  pct >= 100 ? DownloadStatus.converting : DownloadStatus.downloading);
            },
          );
          if (!token.cancelled) {
            onProgress(98, DownloadStatus.converting);
            return _finalizeOutput(
              outputPath: outputPath,
              outputDir: outputDir,
              safeTitle: safeTitle,
              formatLower: formatLower,
              thumbBytes: null,
              isSafOutput: isSafOutput,
              useMediaStoreOnly: useMediaStoreOnly,
              outputFolder: outputFolder,
            );
          }
        } catch (_) {
          await _safeDelete(outputPath);
          // Fall through to user-friendly error below
        }
      }

      throw Exception(translateError(msg));
    }
  }

  Future<DownloadResult> download(
    PreviewItem item, {
    required String format,
    required String outputDir,
    required String? ffmpegPath,
    required void Function(int pct, DownloadStatus status) onProgress,
    required DownloadToken token,
    String? ytDlpPath,
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

    final safeTitle = _sanitizeFileName(video.title);

    // ── yt-dlp fast-path (desktop only) ─────────────────────────────────
    // yt-dlp handles throttle-token decryption, chunked downloads, and
    // adaptive stream merging natively — bypassing the youtube_explode_dart
    // stream issues that cause 403 errors on HD adaptive streams.
    if (!Platform.isAndroid && !Platform.isIOS) {
      final resolvedYtDlp = await ytDlp.resolveAvailablePath(ytDlpPath);
      if (resolvedYtDlp != null) {
        return _downloadWithYtDlp(
          video: video,
          url: item.url,
          safeTitle: safeTitle,
          format: formatLower,
          outputDir: outputDir,
          ffmpegPath: ffmpegPath,
          ytDlpPath: resolvedYtDlp,
          onProgress: onProgress,
          token: token,
          videoQuality: preferredVideoQuality,
          audioBitrate: preferredAudioBitrate,
          isSafOutput: isSafOutput,
          useMediaStoreOnly: useMediaStoreOnly,
        );
      }
    }

    // ── Fallback: youtube_explode_dart ───────────────────────────────────
    // Used on mobile (no yt-dlp binary) or when yt-dlp isn't installed.
    // Muxed streams (360p max) are reliable; HD adaptive streams may fail.
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
        }, videoId: video.id);
        if (token.cancelled) throw Exception('Cancelled');
        await _downloadStream(separateAudioStream, tempAudioPath!, token, (pct, status) {
          final adjustedPct = 60 + (pct * 0.2).toInt();
          onProgress(adjustedPct, status);
        }, videoId: video.id);
      } else {
        // Single stream download (0-90%)
        await _downloadStream(sourceStream, tempFilePath, token, (pct, status) {
          final adjustedPct = (pct * 0.9).toInt();
          onProgress(adjustedPct, status);
        }, videoId: video.id);
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

  /// ── yt-dlp download path ────────────────────────────────────────────
  /// Uses the yt-dlp binary for the actual stream download, merging, and
  /// audio extraction.  yt-dlp handles YouTube's throttle-token decryption
  /// internally, avoiding the 403 errors that plague adaptive streams via
  /// youtube_explode_dart.
  Future<DownloadResult> _downloadWithYtDlp({
    required dynamic video, // Video from youtube_explode_dart
    required String url,
    required String safeTitle,
    required String format,
    required String outputDir,
    required String? ffmpegPath,
    required String ytDlpPath,
    required void Function(int pct, DownloadStatus status) onProgress,
    required DownloadToken token,
    required String videoQuality,
    required int audioBitrate,
    required bool isSafOutput,
    required bool useMediaStoreOnly,
  }) async {
    debugPrint('DownloadService: using yt-dlp path for "$safeTitle"');
    onProgress(0, DownloadStatus.downloading);

    // Resolve output folder (same structure as normal downloads)
    final outputFolder = (isSafOutput || useMediaStoreOnly)
        ? await _resolveTempFolder()
        : await _resolveOutputFolder(outputDir, format);
    await outputFolder.create(recursive: true);

    final outputPath =
        '${outputFolder.path}${Platform.pathSeparator}$safeTitle.$format';

    // Fetch thumbnail via youtube_explode_dart for display in the queue
    Uint8List? thumbBytes =
        await _fetchThumbnailBytes(video.thumbnails.highResUrl);
    thumbBytes = _prepareCoverBytes(thumbBytes);

    try {
      // Delegate the entire download + merge/conversion to yt-dlp.
      // yt-dlp's --embed-thumbnail handles cover art embedding internally.
      await ytDlp.download(
        url: url,
        outputPath: outputPath,
        format: format,
        ffmpegPath: ffmpegPath,
        ytDlpPath: ytDlpPath,
        videoQuality: videoQuality,
        audioBitrate: audioBitrate,
        isCancelled: () => token.cancelled,
        onProgress: (pct) {
          // Scale yt-dlp's 0-100 into 0-95 (leave room for finalization)
          final adjusted = (pct * 0.95).toInt();
          final status = pct >= 100
              ? DownloadStatus.converting
              : DownloadStatus.downloading;
          onProgress(adjusted, status);
        },
      );

      if (token.cancelled) {
        await _safeDelete(outputPath);
        throw Exception('Cancelled');
      }

      onProgress(98, DownloadStatus.converting);

      return _finalizeOutput(
        outputPath: outputPath,
        outputDir: outputDir,
        safeTitle: safeTitle,
        formatLower: format,
        thumbBytes: thumbBytes,
        isSafOutput: isSafOutput,
        useMediaStoreOnly: useMediaStoreOnly,
        outputFolder: outputFolder,
      );
    } catch (e) {
      await _safeDelete(outputPath);
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

  /// Download a stream using YouTube-native chunked range parameters.
  ///
  /// On desktop, uses YouTube's own `&range=START-END` and `&rn=N` URL query
  /// parameters.  On Android, uses HTTP Range headers with smaller chunks and
  /// automatic manifest refresh on 403/429 — the URL-param approach fails on
  /// Android's HTTP stack after 2-3 chunks.
  ///
  /// [videoId] is used on Android to refresh the stream manifest when the CDN
  /// returns 403 (expired signature).
  Future<void> _downloadStream(
    StreamInfo stream,
    String outputPath,
    DownloadToken token,
    void Function(int pct, DownloadStatus status) onProgress, {
    dynamic videoId,
  }) async {
    final total = stream.size.totalBytes;
    if (total <= 0) {
      // Unknown size – fall back to the library's own streaming API
      await _downloadStreamLegacy(stream, outputPath, token, onProgress);
      return;
    }

    // On Android, use HTTP Range headers with smaller chunks.
    if (!kIsWeb && Platform.isAndroid) {
      await _downloadStreamAndroid(
        stream, outputPath, token, onProgress,
        videoId: videoId,
      );
      return;
    }

    const chunkSize = 10 * 1024 * 1024; // 10 MB per chunk
    const maxRetries = 5;
    final client = http.Client();
    final file = File(outputPath);
    int received = 0;
    int requestNum = 0;
    onProgress(0, DownloadStatus.downloading);

    try {
      // Pre-create the file (truncate if leftover from a previous attempt)
      await file.writeAsBytes([], flush: true);

      while (received < total) {
        if (token.cancelled) {
          await _safeDelete(outputPath);
          throw Exception('Cancelled');
        }
        final start = received;
        final end = (start + chunkSize - 1).clamp(0, total - 1);
        final chunkBytes = await _downloadChunkWithRetry(
          client: client,
          streamUrl: stream.url,
          start: start,
          end: end,
          requestNum: requestNum,
          maxRetries: maxRetries,
          token: token,
        );
        // Append the completed chunk to the file
        await file.writeAsBytes(chunkBytes, mode: FileMode.writeOnlyAppend, flush: true);
        received += chunkBytes.length;
        requestNum++;
        final pct = ((received / total) * 100).clamp(0, 100).toInt();
        onProgress(pct, DownloadStatus.downloading);
      }
    } catch (e) {
      await _safeDelete(outputPath);
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Build a chunk URL using YouTube-native range parameters.
  ///
  /// YouTube's CDN expects `&range=START-END&rn=N&rbuf=0` as URL query params,
  /// NOT as HTTP Range headers.  Using HTTP Range headers triggers 403 blocks
  /// after a few requests.  This mirrors how yt-dlp downloads adaptive streams.
  ///
  /// We strip any pre-existing `range`, `rn` and `rbuf` params from the base
  /// URL first, because youtube_explode_dart may embed its own values which
  /// would conflict with ours and cause the CDN to reject requests after the
  /// first couple of chunks (especially on Android).
  Uri _buildChunkUrl(Uri baseUrl, int start, int end, int requestNum) {
    // Remove conflicting params from the original URL
    final params = Map<String, List<String>>.from(baseUrl.queryParametersAll);
    params.remove('range');
    params.remove('rn');
    params.remove('rbuf');
    final cleaned = baseUrl.replace(
      queryParameters: params.map((k, v) => MapEntry(k, v.length == 1 ? v.first : v.join(','))),
    );
    final urlStr = cleaned.toString();
    final sep = urlStr.contains('?') ? '&' : '?';
    return Uri.parse('$urlStr${sep}range=$start-$end&rn=$requestNum&rbuf=0');
  }

  /// Download a single chunk, retrying up to [maxRetries] times.
  Future<Uint8List> _downloadChunkWithRetry({
    required http.Client client,
    required Uri streamUrl,
    required int start,
    required int end,
    required int requestNum,
    required int maxRetries,
    required DownloadToken token,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        if (token.cancelled) throw Exception('Cancelled');
        final chunkUrl = _buildChunkUrl(streamUrl, start, end, requestNum);
        final request = http.Request('GET', chunkUrl);
        final response = await client.send(request).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Chunk request timed out'),
        );
        if (response.statusCode >= 400) {
          throw Exception('HTTP ${response.statusCode} for range $start-$end');
        }

        // Collect the chunk data with stall detection
        final buffer = BytesBuilder(copy: false);
        await for (final data in response.stream.timeout(
          const Duration(seconds: 30),
          onTimeout: (eventSink) {
            eventSink.addError(TimeoutException('Chunk data stalled'));
            eventSink.close();
          },
        )) {
          if (token.cancelled) throw Exception('Cancelled');
          buffer.add(data);
        }
        return buffer.toBytes();
      } on Exception catch (e) {
        if (token.cancelled) rethrow;
        if (e.toString().contains('Cancelled')) rethrow;
        if (attempt == maxRetries - 1) {
          throw Exception(
            'Download failed after $maxRetries attempts on chunk $start-$end: $e',
          );
        }
        // Exponential back-off before retry
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    // Should never reach here
    throw Exception('Download chunk failed unexpectedly');
  }

  /// Legacy single-connection download for streams with unknown total size.
  Future<void> _downloadStreamLegacy(
    StreamInfo stream,
    String outputPath,
    DownloadToken token,
    void Function(int pct, DownloadStatus status) onProgress,
  ) async {
    final file = File(outputPath);
    final sink = file.openWrite();
    try {
      final rawStream = yt.videos.streamsClient.get(stream);
      final streamData = rawStream.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(TimeoutException('Download stalled – no data received for 60 seconds'));
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

  /// Robust Android download using HTTP Range headers with small chunks.
  ///
  /// YouTube's URL-param range approach (`&range=START-END`) fails after 2-3
  /// chunks on Android.  Instead, this method uses standard HTTP Range headers
  /// with 2 MB chunks, a mobile User-Agent, and automatic manifest refresh
  /// when the CDN returns 403 (signature expired).
  Future<void> _downloadStreamAndroid(
    StreamInfo originalStream,
    String outputPath,
    DownloadToken token,
    void Function(int pct, DownloadStatus status) onProgress, {
    dynamic videoId,
  }) async {
    final total = originalStream.size.totalBytes;
    if (total <= 0) {
      await _downloadStreamLegacy(originalStream, outputPath, token, onProgress);
      return;
    }

    const chunkSize = 1 * 1024 * 1024; // 1 MB — smaller chunks reduce stall window
    const maxRetries = 20; // more retries for flaky mobile networks
    final file = File(outputPath);
    int received = 0;
    Uri currentUrl = originalStream.url;
    final originalTag = originalStream.tag; // itag for matching on refresh
    int consecutiveFailures = 0;
    onProgress(0, DownloadStatus.downloading);

    // Strip pre-existing range / rn params from the URL
    currentUrl = _stripRangeParams(currentUrl);

    try {
      await file.writeAsBytes([], flush: true);

      while (received < total) {
        if (token.cancelled) {
          await _safeDelete(outputPath);
          throw Exception('Cancelled');
        }

        final start = received;
        final end = (start + chunkSize - 1).clamp(0, total - 1);
        Uint8List? chunkBytes;
        Exception? lastError;

        for (int attempt = 0; attempt < maxRetries; attempt++) {
          if (token.cancelled) throw Exception('Cancelled');

          try {
            final client = http.Client();
            try {
              final request = http.Request('GET', currentUrl);
              request.headers['Range'] = 'bytes=$start-$end';
              request.headers['User-Agent'] =
                  'com.google.android.youtube/19.09.37 (Linux; U; Android 14; en_US) gzip';
              // Keep-alive helps mobile connections
              request.headers['Connection'] = 'keep-alive';

              final response = await client.send(request).timeout(
                const Duration(seconds: 45),
                onTimeout: () => throw TimeoutException('Chunk request timed out'),
              );

              if (response.statusCode == 403 || response.statusCode == 429) {
                // Signature expired or rate-limited – refresh stream URL
                if (videoId != null) {
                  debugPrint('Android download: HTTP ${response.statusCode} on chunk $start-$end, refreshing manifest...');
                  try {
                    final fresh = await yt.videos.streamsClient.getManifest(
                      videoId,
                      ytClients: [YoutubeApiClient.safari, YoutubeApiClient.androidVr],
                    ).timeout(const Duration(seconds: 30));
                    final match = _findStreamByTag(fresh, originalTag);
                    if (match != null) {
                      currentUrl = _stripRangeParams(match.url);
                      debugPrint('Android download: refreshed stream URL');
                    }
                  } catch (e2) {
                    debugPrint('Android download: manifest refresh failed: $e2');
                  }
                }
                throw Exception('HTTP ${response.statusCode}');
              }

              if (response.statusCode >= 400) {
                throw Exception('HTTP ${response.statusCode} for range $start-$end');
              }

              final buffer = BytesBuilder(copy: false);
              await for (final data in response.stream.timeout(
                const Duration(seconds: 45),
                onTimeout: (eventSink) {
                  eventSink.addError(TimeoutException('Chunk data stalled'));
                  eventSink.close();
                },
              )) {
                if (token.cancelled) throw Exception('Cancelled');
                buffer.add(data);
              }
              chunkBytes = buffer.toBytes();
              consecutiveFailures = 0; // reset on success
              break; // Success
            } finally {
              client.close();
            }
          } on Exception catch (e) {
            lastError = e;
            if (token.cancelled || e.toString().contains('Cancelled')) rethrow;
            consecutiveFailures++;
            if (attempt < maxRetries - 1) {
              // Exponential back-off: 2s, 4s, 6s, ... up to 30s
              final delay = Duration(seconds: (2 * (attempt + 1)).clamp(2, 30));
              debugPrint('Android download: chunk $start-$end attempt ${attempt + 1} failed: $e, retrying in ${delay.inSeconds}s');
              await Future.delayed(delay);
              // After 3 consecutive failures, try refreshing the manifest
              if (consecutiveFailures >= 3 && videoId != null) {
                debugPrint('Android download: $consecutiveFailures consecutive failures, refreshing manifest...');
                try {
                  final fresh = await yt.videos.streamsClient.getManifest(
                    videoId,
                    ytClients: [YoutubeApiClient.safari, YoutubeApiClient.androidVr],
                  ).timeout(const Duration(seconds: 30));
                  final match = _findStreamByTag(fresh, originalTag);
                  if (match != null) {
                    currentUrl = _stripRangeParams(match.url);
                    debugPrint('Android download: refreshed stream URL after consecutive failures');
                    consecutiveFailures = 0;
                  }
                } catch (_) {}
              }
            }
          }
        }

        if (chunkBytes == null) {
          throw lastError ?? Exception('Download failed after $maxRetries retries at byte $received');
        }

        await file.writeAsBytes(chunkBytes, mode: FileMode.writeOnlyAppend, flush: true);
        received += chunkBytes.length;

        final pct = ((received / total) * 100).clamp(0, 100).toInt();
        onProgress(pct, DownloadStatus.downloading);

        // Small delay between chunks to avoid YouTube throttle detection
        if (received < total) {
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }
    } catch (e) {
      await _safeDelete(outputPath);
      rethrow;
    }
  }

  /// Strip pre-existing range/rn/rbuf params from a YouTube CDN URL.
  Uri _stripRangeParams(Uri url) {
    final params = Map<String, List<String>>.from(url.queryParametersAll);
    params.remove('range');
    params.remove('rn');
    params.remove('rbuf');
    return url.replace(
      queryParameters: params.map(
        (k, v) => MapEntry(k, v.length == 1 ? v.first : v.join(',')),
      ),
    );
  }

  /// Find a stream in a manifest that matches the given itag.
  StreamInfo? _findStreamByTag(StreamManifest manifest, int tag) {
    for (final s in manifest.muxed) {
      if (s.tag == tag) return s;
    }
    for (final s in manifest.videoOnly) {
      if (s.tag == tag) return s;
    }
    for (final s in manifest.audioOnly) {
      if (s.tag == tag) return s;
    }
    return null;
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
