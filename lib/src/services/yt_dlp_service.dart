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
    /// Fetches video metadata using yt-dlp --dump-json and returns filesize_approx in bytes (if available).
    Future<int?> fetchEstimatedSize({
      required String url,
      required String ytDlpPath,
      String? ffmpegPath,
      String videoQuality = 'best',
      Map<String, String>? extraHeaders,
      String? cookiesFile,
      String? cookiesFromBrowser,
      bool sponsorBlockEnabled = false,
      bool forceGenericExtractor = false,
    }) async {
      final args = <String>['--dump-json'];
      final height = _qualityToHeight(videoQuality);
      args.addAll([
        '-f',
        'bestvideo[height<=$height]+bestaudio/best[height<=$height]'
      ]);
      if (sponsorBlockEnabled) {
        args.addAll(['--sponsorblock-remove', 'all']);
      }
      if (ffmpegPath != null &&
          ffmpegPath.trim().isNotEmpty &&
          ffmpegPath.trim() != 'ffmpeg') {
        args.addAll(['--ffmpeg-location', ffmpegPath]);
      }
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
      if (cookiesFile != null && cookiesFile.trim().isNotEmpty) {
        args.addAll(['--cookies', cookiesFile]);
      } else if (cookiesFromBrowser != null && cookiesFromBrowser.trim().isNotEmpty) {
        args.addAll(['--cookies-from-browser', cookiesFromBrowser]);
      }
      if (forceGenericExtractor) {
        args.add('--force-generic-extractor');
      }
      args.add(url);

      final process = await Process.start(ytDlpPath, args, runInShell: false);
      final output = await process.stdout.transform(utf8.decoder).join();
      await process.stderr.drain();
      final exitCode = await process.exitCode;
      if (exitCode != 0) return null;
      try {
        final json = jsonDecode(output);
        if (json is Map<String, dynamic> && json.containsKey('filesize_approx')) {
          return json['filesize_approx'] as int?;
        }
      } catch (_) {}
      return null;
    }
  static final _progressRegex = RegExp(r'\[download\]\s+(\d+\.?\d*)%.*?of.*?(\d+\.?\d*\s*\w+B).*?at\s*([\d\.]+\s*\w+/s).*?ETA\s*(\d+:\d+)');

  /// Resolve yt-dlp executable path.
  /// Checks: configured path → app data dir → system PATH → null.
  Future<String?> resolveAvailablePath(String? configuredPath) async {
    if (kIsWeb) return null;

    // 1. Check configured path (works on all platforms)
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
      throw Exception(
          'yt-dlp auto-download is only available on desktop platforms.');
    }

    onProgress?.call(0, 'Downloading yt-dlp…');

    final appBin = await _getAppBinaryPath();
    if (appBin == null) {
      throw Exception(
          'Could not determine app data directory for yt-dlp installation.');
    }

    // Download from GitHub releases (single self-contained binary)
    final url = Platform.isWindows
        ? 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'
        : 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp';

    final client = http.Client();
    try {
      // On Windows prefer using the OS downloader first (PowerShell)
      // because it uses the system TLS stack which is more reliable on
      // older or enterprise-locked machines.
      if (Platform.isWindows) {
        try {
          onProgress?.call(5, 'Downloading yt-dlp (PowerShell)…');
          await _attemptShellDownload(url, appBin, enforceTls12: true);
          // Verify binary
          final verify = await Process.run(appBin, ['--version'])
              .timeout(const Duration(seconds: 5));
          if (verify.exitCode == 0 &&
              verify.stdout.toString().trim().isNotEmpty) {
            onProgress?.call(100, 'yt-dlp installed');
            debugPrint('yt-dlp installed to: $appBin (PowerShell)');
            return appBin;
          }
          await _safeDelete(appBin);
          debugPrint(
              'PowerShell download wrote binary but verification failed');
        } catch (e) {
          debugPrint('PowerShell download/verify failed: $e');
          await _safeDelete(appBin);
        }
      }

      // HTTP download with retries and exponential backoff.
      const maxAttempts = 3;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          onProgress?.call((attempt == 1) ? 10 : (10 + attempt * 10),
              'Downloading yt-dlp (HTTP)…');
          final request = http.Request('GET', Uri.parse(url));
          final response = await client.send(request).timeout(
                const Duration(seconds: 30),
                onTimeout: () =>
                    throw TimeoutException('yt-dlp download request timed out'),
              );
          if (response.statusCode >= 400) {
            throw Exception(
                'Failed to download yt-dlp: HTTP ${response.statusCode}');
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

          // Verify binary by calling `--version`.
          try {
            final verify = await Process.run(appBin, ['--version'])
                .timeout(const Duration(seconds: 5));
            if (verify.exitCode == 0 &&
                verify.stdout.toString().trim().isNotEmpty) {
              onProgress?.call(100, 'yt-dlp installed');
              debugPrint('yt-dlp installed to: $appBin (HTTP)');
              return appBin;
            }
            await _safeDelete(appBin);
            throw Exception('Verification failed after download');
          } catch (e) {
            await _safeDelete(appBin);
            throw Exception('Verification failed: $e');
          }
        } catch (e) {
          await _safeDelete(appBin);
          if (attempt >= maxAttempts) {
            debugPrint('HTTP download attempts exhausted: $e');
            // Final attempt: on Windows try shell fallback one last time.
            if (Platform.isWindows) {
              try {
                onProgress?.call(
                    5, 'Downloading yt-dlp (PowerShell fallback)…');
                await _attemptShellDownload(url, appBin, enforceTls12: true);
                final verify = await Process.run(appBin, ['--version'])
                    .timeout(const Duration(seconds: 5));
                if (verify.exitCode == 0 &&
                    verify.stdout.toString().trim().isNotEmpty) {
                  onProgress?.call(100, 'yt-dlp installed');
                  debugPrint(
                      'yt-dlp installed to: $appBin (PowerShell fallback)');
                  return appBin;
                }
                await _safeDelete(appBin);
              } catch (e2) {
                await _safeDelete(appBin);
                throw Exception('All download methods failed: $e; $e2');
              }
            }
            throw Exception(
                'yt-dlp download failed after $maxAttempts attempts: $e');
          }
          // Exponential backoff before next try
          final backoff = Duration(seconds: 1 << (attempt - 1));
          await Future.delayed(backoff);
          continue;
        }
      }
      throw Exception('yt-dlp download failed');
    } finally {
      client.close();
    }
  }

  /// Force-update the local yt-dlp binary by re-downloading it.
  ///
  /// This is useful when YouTube breaks and a newer yt-dlp release is needed.
  Future<String> update({
    String? configuredPath,
    void Function(int percent, String message)? onProgress,
  }) async {
    // Delete any existing binary so ensureAvailable will fetch the latest.
    final existing = await resolveAvailablePath(configuredPath);
    if (existing != null) {
      await _safeDelete(existing);
    }
    return ensureAvailable(
      configuredPath: configuredPath,
      onProgress: onProgress,
    );
  }

  /// Returns the local yt-dlp binary version if available.
  ///
  /// Returns `null` when yt-dlp cannot be found or cannot be executed.
  Future<String?> getVersion({String? configuredPath}) async {
    final path = await resolveAvailablePath(configuredPath);
    if (path == null) return null;

    try {
      final result = await Process.run(path, ['--version'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final out = result.stdout.toString().trim();
        if (out.isNotEmpty) return out.split('\n').first.trim();
      }
    } catch (_) {
      // ignore
    }
    return null;
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
    required void Function(int pct, String? speed, String? eta) onProgress,
    required String ytDlpPath,
    String videoQuality = '720p',
    int audioBitrate = 192,
    bool Function()? isCancelled,
    Map<String, String>? extraHeaders,
    String? cookiesFile,
    String? cookiesFromBrowser,
    bool sponsorBlockEnabled = false,
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
        '--audio-format',
        formatLower,
        '--audio-quality',
        '${audioBitrate.clamp(64, 320)}k',
      ]);
    }

    // Common options
    args.addAll([
      '--embed-thumbnail', // embed cover art
      '--add-metadata', // include title/artist/date tags
      '--no-playlist', // single video only
      '--newline', // one progress line per update
      '--no-colors', // clean output for parsing
      '--no-overwrites',
      '--no-part', // don't use .part files
      '-o', _escapeTemplate(outputPath),
    ]);

    if (sponsorBlockEnabled) {
      // Use SponsorBlock to strip sponsored/intro/outro segments on download.
      args.addAll(['--sponsorblock-remove', 'all']);
    }

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
    onProgress(0, null, null);

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
          final speed = match.group(3) ?? "";
          final eta = match.group(4) ?? "";
          onProgress(pct.clamp(0, 100), speed, eta);
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
          '$base.mkv', // yt-dlp sometimes outputs MKV
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
          throw Exception(
              'yt-dlp completed but the output file was not created.');
        }
      }

      onProgress(100, null, null);
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
      case '360p':
        return 360;
      case '480p':
        return 480;
      case '720p':
        return 720;
      case '1080p':
        return 1080;
      case '1440p':
        return 1440;
      case '2160p':
        return 2160;
      case '4320p':
        return 4320;
      case 'best':
        return 9999;
      default:
        return 720;
    }
  }

  static Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Fallback downloader that uses OS tooling when the Dart HTTP stack
  /// fails (TLS handshake / proxy issues on some Windows installs).
  static Future<void> _attemptShellDownload(String url, String dest,
      {bool enforceTls12 = false}) async {
    // Ensure parent exists
    try {
      final f = File(dest);
      await f.parent.create(recursive: true);
    } catch (_) {}

    if (Platform.isWindows) {
      try {
        // Use PowerShell's WebClient which relies on the OS networking stack.
        final safeUrl = url.replaceAll("'", "''");
        final safeDest = dest.replaceAll("'", "''");
        final cmd = StringBuffer();
        if (enforceTls12) {
          cmd.write(
              '[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; ');
        }
        cmd.write(
            "try { (New-Object System.Net.WebClient).DownloadFile('$safeUrl','$safeDest') } catch { exit 1 }");
        final args = [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          cmd.toString(),
        ];
        final pr = await Process.run('powershell', args)
            .timeout(const Duration(seconds: 60));
        if (pr.exitCode != 0) {
          throw Exception('PowerShell download failed: ${pr.stderr}');
        }
        return;
      } catch (e) {
        throw Exception('Shell fallback download (PowerShell) failed: $e');
      }
    }

    // Unix-like fallback: try `curl` then `wget`.
    try {
      final whichCurl = await Process.run('which', ['curl'])
          .catchError((_) => ProcessResult(1, 1, '', ''));
      if (whichCurl.exitCode == 0) {
        final r = await Process.run('curl', ['-L', '-f', '-o', dest, url])
            .timeout(const Duration(seconds: 60));
        if (r.exitCode != 0) throw Exception('curl failed: ${r.stderr}');
        return;
      }
    } catch (_) {}

    try {
      final whichWget = await Process.run('which', ['wget'])
          .catchError((_) => ProcessResult(1, 1, '', ''));
      if (whichWget.exitCode == 0) {
        final r = await Process.run('wget', ['-O', dest, url])
            .timeout(const Duration(seconds: 60));
        if (r.exitCode != 0) throw Exception('wget failed: ${r.stderr}');
        return;
      }
    } catch (_) {}

    throw Exception(
        'No suitable shell downloader found (curl/wget/PowerShell)');
  }
}
