import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import 'platform_dirs.dart';

/// Service for downloading media using yt-dlp, the industry-standard
/// YouTube/media downloader that handles throttling, rate-limiting, and
/// bot-detection natively.
///
/// On desktop platforms (Windows, Linux, macOS), yt-dlp can be:
///   1. Manually configured via settings
///   2. Auto-downloaded to the app support directory
///   3. Found on the system PATH
///
/// On mobile/web, yt-dlp is not available — the app falls back to
/// youtube_explode_dart for stream downloads.
class YtDlpService {
  static final _progressRegex = RegExp(r'\[download\]\s+(\d+\.?\d*)%');

  /// Resolve yt-dlp executable path.
  /// Checks: configured path → app data dir → system PATH → null.
  Future<String?> resolveAvailablePath(String? configuredPath) async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) return null;

    // 1. Check configured path
    if (configuredPath != null && configuredPath.trim().isNotEmpty) {
      if (await File(configuredPath).exists()) return configuredPath;
    }

    // 2. Check app support dir for previously downloaded binary
    final appBin = await _getAppBinaryPath();
    if (appBin != null && await File(appBin).exists()) return appBin;

    // 3. Check system PATH
    final exeName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    try {
      final result = await Process.run(exeName, ['--version'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) return exeName;
    } catch (_) {}

    return null;
  }

  /// Returns true when yt-dlp is available for use.
  Future<bool> isAvailable(String? configuredPath) async {
    return await resolveAvailablePath(configuredPath) != null;
  }

  /// Download the yt-dlp binary to the app support directory.
  /// Returns the path to the downloaded binary.
  Future<String> ensureAvailable({
    String? configuredPath,
    void Function(int percent, String message)? onProgress,
  }) async {
    // Already available — return immediately
    final existing = await resolveAvailablePath(configuredPath);
    if (existing != null) return existing;

    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      throw Exception('yt-dlp auto-download is only available on desktop platforms.');
    }

    onProgress?.call(0, 'Downloading yt-dlp…');

    final appBin = await _getAppBinaryPath();
    if (appBin == null) {
      throw Exception('Could not determine app data directory for yt-dlp installation.');
    }

    // Download from GitHub releases (single self-contained binary)
    final url = Platform.isWindows
        ? 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        : 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp';

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('yt-dlp download request timed out'),
      );
      if (response.statusCode >= 400) {
        throw Exception('Failed to download yt-dlp: HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(TimeoutException('yt-dlp download stalled'));
          sink.close();
        },
      )) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = ((received / total) * 100).clamp(0, 100).toInt();
          onProgress?.call(pct, 'Downloading yt-dlp…');
        }
      }

      // Write to disk
      final file = File(appBin);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);

      // Make executable on Linux/macOS
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', appBin]);
      }

      onProgress?.call(100, 'yt-dlp installed');
      debugPrint('yt-dlp installed to: $appBin');
      return appBin;
    } finally {
      client.close();
    }
  }

  /// Download media using yt-dlp.
  ///
  /// [url]            – Video / media URL (YouTube, SoundCloud, etc.)
  /// [outputPath]     – Full path for the output file *including* extension.
  /// [format]         – Target format: `mp4`, `mp3`, or `m4a`.
  /// [ffmpegPath]     – Path to FFmpeg (needed for merging / conversion).
  /// [onProgress]     – Progress callback (0-100).
  /// [ytDlpPath]      – Resolved path to the yt-dlp binary.
  /// [videoQuality]   – Target video quality string (e.g. `'720p'`).
  /// [audioBitrate]   – Target audio bitrate in kbps.
  /// [isCancelled]    – Polled to support external cancellation.
  Future<void> download({
    required String url,
    required String outputPath,
    required String format,
    required String? ffmpegPath,
    required void Function(int pct) onProgress,
    required String ytDlpPath,
    String videoQuality = '720p',
    int audioBitrate = 192,
    bool Function()? isCancelled,
    Map<String, String>? extraHeaders,
    String? cookiesFile,
    String? cookiesFromBrowser,
    bool forceGenericExtractor = false,
  }) async {
    final args = <String>[];
    final formatLower = format.toLowerCase();

    if (formatLower == 'mp4') {
      // Video download: best video+audio up to target quality
      final height = _qualityToHeight(videoQuality);
      args.addAll([
        '-f',
        'bestvideo[height<=$height]+bestaudio/best[height<=$height]',
        '--merge-output-format',
        'mp4',
      ]);
    } else {
      // Audio download: extract audio in target format
      args.addAll([
        '-x',
        '--audio-format', formatLower,
        '--audio-quality', '${audioBitrate.clamp(64, 320)}k',
      ]);
    }

    // Common options
    args.addAll([
      '--embed-thumbnail',    // embed cover art
      '--no-playlist',        // single video only
      '--newline',            // one progress line per update
      '--no-colors',          // clean output for parsing
      '--no-overwrites',
      '--no-part',            // don't use .part files
      '-o', _escapeTemplate(outputPath),
    ]);

    // FFmpeg location — only pass when we have an explicit path (not 'ffmpeg' on PATH)
    if (ffmpegPath != null &&
        ffmpegPath.trim().isNotEmpty &&
        ffmpegPath.trim() != 'ffmpeg') {
      args.addAll(['--ffmpeg-location', ffmpegPath]);
    }

    // Browser-like headers for difficult sites
    if (extraHeaders != null) {
      for (final entry in extraHeaders.entries) {
        if (entry.key.toLowerCase() == 'user-agent') {
          args.addAll(['--user-agent', entry.value]);
        } else if (entry.key.toLowerCase() == 'referer') {
          args.addAll(['--referer', entry.value]);
        } else {
          args.addAll(['--add-header', '${entry.key}:${entry.value}']);
        }
      }
    }

    // Cookie support
    if (cookiesFile != null && cookiesFile.trim().isNotEmpty) {
      args.addAll(['--cookies', cookiesFile]);
    } else if (cookiesFromBrowser != null &&
        cookiesFromBrowser.trim().isNotEmpty) {
      args.addAll(['--cookies-from-browser', cookiesFromBrowser]);
    }

    // Force generic extractor as fallback
    if (forceGenericExtractor) {
      args.add('--force-generic-extractor');
    }

    args.add(url);

    debugPrint('yt-dlp command: $ytDlpPath ${args.join(' ')}');
    onProgress(0);

    final process = await Process.start(ytDlpPath, args, runInShell: false);

    // Poll for cancellation every 500ms
    final cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (isCancelled?.call() ?? false) {
        debugPrint('yt-dlp: cancellation requested, killing process');
        process.kill();
      }
    });

    try {
      // Parse stdout for progress
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('yt-dlp stdout: $line');
        final match = _progressRegex.firstMatch(line);
        if (match != null) {
          final pct = double.tryParse(match.group(1)!)?.toInt() ?? 0;
          onProgress(pct.clamp(0, 100));
        }
      });

      // Capture stderr
      final stderrBuffer = StringBuffer();
      String? lastError;
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('yt-dlp stderr: $line');
        stderrBuffer.writeln(line);
        if (line.contains('ERROR')) {
          lastError = line;
        }
      });

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      if (isCancelled?.call() ?? false) {
        // Clean up partial output
        await _safeDelete(outputPath);
        throw Exception('Cancelled');
      }

      if (exitCode != 0) {
        final stderr = stderrBuffer.toString().trim();
        final errorMsg = lastError ?? stderr;
        throw Exception('yt-dlp failed (exit $exitCode): $errorMsg');
      }

      // Verify output exists (yt-dlp may adjust extension)
      if (!await File(outputPath).exists()) {
        // Check for common extension adjustments
        final base = outputPath.replaceAll(RegExp(r'\.[^.]+$'), '');
        final candidates = [
          outputPath,
          '$base.$formatLower',
          '$base.mkv',           // yt-dlp sometimes outputs MKV
          '$base.webm',
        ];
        bool found = false;
        for (final c in candidates) {
          if (await File(c).exists()) {
            if (c != outputPath) {
              await File(c).rename(outputPath);
            }
            found = true;
            break;
          }
        }
        if (!found) {
          throw Exception('yt-dlp completed but the output file was not created.');
        }
      }

      onProgress(100);
    } finally {
      cancelTimer.cancel();
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  /// Path where this app stores the yt-dlp binary.
  Future<String?> _getAppBinaryPath() async {
    final support = await PlatformDirs.getAppSupportDir();
    if (support == null) return null;
    final binName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    return '${support.path}${Platform.pathSeparator}yt-dlp${Platform.pathSeparator}$binName';
  }

  /// Escape `%` in output template so yt-dlp doesn't interpret it.
  static String _escapeTemplate(String path) => path.replaceAll('%', '%%');

  static int _qualityToHeight(String quality) {
    switch (quality) {
      case '360p':  return 360;
      case '480p':  return 480;
      case '720p':  return 720;
      case '1080p': return 1080;
      case '1440p': return 1440;
      case '2160p': return 2160;
      case 'best':  return 9999;
      default:      return 720;
    }
  }

  static Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
