import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/safe_json.dart';
import 'network_proxy_service.dart';
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
/// On mobile/web, yt-dlp is not available - the app falls back to
/// youtube_explode_dart for stream downloads.
class YtDlpService {
  /// When the last automatic self-update finished (millis since epoch).
  ///
  /// Used to throttle the update-and-retry path so a burst of failed downloads
  /// (e.g. the "page needs to be reloaded" YouTube regression) only triggers
  /// one binary refresh instead of hammering GitHub on every attempt.
  static DateTime? _lastAutoUpdate;

  static const Duration _autoUpdateCooldown = Duration(hours: 2);

  /// Resolved Deno JS runtime path (per session), avoids re-probing/downloading.
  static String? _denoPath;

  Future<String> _getYtDlpWorkingDir() async {
    final temp = await getTemporaryDirectory();
    return temp.path;
  }

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
    args.addAll([
      '--no-mtime',
      '--extractor-args',
      'youtube:lang=en',
      '--extractor-retries',
      '3',
    ]);
    final height = _qualityToHeight(videoQuality);
    args.addAll(
        ['-f', 'bestvideo[height<=$height]+bestaudio/best[height<=$height]']);
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
    } else if (cookiesFromBrowser != null &&
        cookiesFromBrowser.trim().isNotEmpty) {
      args.addAll(['--cookies-from-browser', cookiesFromBrowser]);
    }
    if (forceGenericExtractor) {
      args.add('--force-generic-extractor');
    }
    await _applyProxyArg(args);
    args.add(url);

    final workDir = await _getYtDlpWorkingDir();
    final process = await Process.start(
      ytDlpPath,
      args,
      workingDirectory: workDir,
      runInShell: false,
    );
    final output = await process.stdout.transform(utf8.decoder).join();
    await process.stderr.drain();
    final exitCode = await process.exitCode;
    if (exitCode != 0) return null;
    final json = safeJsonDecode<Map<String, dynamic>>(output);
    if (json != null && json.containsKey('filesize_approx')) {
      return json['filesize_approx'] as int?;
    }
    return null;
  }

  static final _progressRegex = RegExp(
      r'\[download\]\s+(\d+\.?\d*)%.*?of.*?(\d+\.?\d*\s*\w+B).*?at\s*([\d\.]+\s*\w+/s).*?ETA\s*(\d+:\d+)');

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
      final workDir = await _getYtDlpWorkingDir();
      final result = await Process.run(
        exeName,
        ['--version'],
        workingDirectory: workDir,
        runInShell: false,
      ).timeout(const Duration(seconds: 5));
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
    // Already available - return immediately
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

    // Download from GitHub releases (self-contained binary per platform).
    // IMPORTANT: yt-dlp's bare `yt-dlp` release asset is a Python zipapp
    // that requires a system Python 3.11+ interpreter on PATH -- it is NOT
    // a standalone binary. Downloading it for Linux/macOS is what caused
    // "can't download" reports (Linux Mint users especially, since many
    // Mint releases ship an older system Python by default). Linux and
    // macOS each publish their own real self-contained binary that needs
    // no system Python at all -- use those instead.
    final String url;
    if (Platform.isWindows) {
      url =
          'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
    } else if (Platform.isLinux) {
      url =
          'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux';
    } else if (Platform.isMacOS) {
      url =
          'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos';
    } else {
      // Not expected to be hit on supported desktop targets; keep the old
      // behavior as a last-resort fallback rather than throwing here.
      url = 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp';
    }

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
          final workDir = await _getYtDlpWorkingDir();
          final verify = await Process.run(
            appBin,
            ['--version'],
            workingDirectory: workDir,
            runInShell: false,
          ).timeout(const Duration(seconds: 5));
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
            final workDir = await _getYtDlpWorkingDir();
            final verify = await Process.run(
              appBin,
              ['--version'],
              workingDirectory: workDir,
              runInShell: false,
            ).timeout(const Duration(seconds: 5));
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
                final workDir = await _getYtDlpWorkingDir();
                final verify = await Process.run(
                  appBin,
                  ['--version'],
                  workingDirectory: workDir,
                  runInShell: false,
                ).timeout(const Duration(seconds: 5));
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

  /// Checks remote yt-dlp latest release and updates the local binary if
  /// the versions differ. Safe no-op on mobile/web.
  Future<void> updateIfOutdated(
      {String? configuredPath,
      void Function(int percent, String message)? onProgress}) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    await updateYtDlp(configuredPath: configuredPath, onProgress: onProgress);
  }

  /// Force-update the local yt-dlp binary by re-downloading it.
  ///
  /// This is useful when YouTube breaks and a newer yt-dlp release is needed.
  Future<String> update({
    String? configuredPath,
    void Function(int percent, String message)? onProgress,
  }) async {
    return updateYtDlp(
      configuredPath: configuredPath,
      onProgress: onProgress,
    );
  }

  /// Update yt-dlp by downloading the latest GitHub release asset and
  /// replacing the local binary atomically.
  Future<String> updateYtDlp({
    String? configuredPath,
    void Function(int percent, String message)? onProgress,
  }) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      throw Exception(
          'yt-dlp updates are only supported on desktop platforms.');
    }

    try {
      onProgress?.call(5, 'Checking latest yt-dlp release');
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) {
        throw Exception('GitHub API failed: ${response.statusCode}');
      }

      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final latestTag = (release['tag_name'] ?? '').toString().trim();
      if (latestTag.isEmpty) {
        throw Exception('GitHub API returned an empty release tag');
      }

      final ytDlpPath = await _getYtDlpPath(configuredPath);
      final currentVersion = await _getCurrentYtDlpVersion(ytDlpPath);

      if (currentVersion == latestTag) {
        debugPrint('yt-dlp already up to date: $latestTag');
        onProgress?.call(100, 'yt-dlp is already up to date');
        return ytDlpPath;
      }

      final assets = (release['assets'] as List<dynamic>? ?? const []);
      String assetName;
      if (Platform.isWindows) {
        assetName = 'yt-dlp.exe';
      } else if (Platform.isMacOS) {
        assetName = 'yt-dlp_macos';
      } else {
        assetName = 'yt-dlp_linux';
      }

      final asset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] ?? '').toString() == assetName,
            orElse: () => throw Exception('No asset found for $assetName'),
          );

      final downloadUrl = (asset['browser_download_url'] ?? '').toString();
      if (downloadUrl.isEmpty) {
        throw Exception('Release asset is missing browser_download_url');
      }

      onProgress?.call(25, 'Downloading $assetName');
      final tempPath = '$ytDlpPath.tmp';
      final dlResponse = await http.get(Uri.parse(downloadUrl));
      if (dlResponse.statusCode != 200) {
        throw Exception('Download failed: HTTP ${dlResponse.statusCode}');
      }

      final targetFile = File(ytDlpPath);
      await targetFile.parent.create(recursive: true);
      await File(tempPath).writeAsBytes(dlResponse.bodyBytes, flush: true);

      onProgress?.call(70, 'Replacing binary');
      if (Platform.isWindows) {
        final backupPath = '$ytDlpPath.bak';
        if (await targetFile.exists()) {
          await _safeDelete(backupPath);
          await targetFile.rename(backupPath);
        }
        await File(tempPath).rename(ytDlpPath);
        await _safeDelete(backupPath);
      } else {
        await _safeDelete(ytDlpPath);
        await File(tempPath).rename(ytDlpPath);
        await Process.run('chmod', ['+x', ytDlpPath]);
      }

      final installedVersion = await _getCurrentYtDlpVersion(ytDlpPath);
      debugPrint('yt-dlp updated from $currentVersion to $installedVersion');
      onProgress?.call(100, 'yt-dlp updated to $installedVersion');
      return ytDlpPath;
    } catch (e) {
      debugPrint('yt-dlp update failed: $e');
      rethrow;
    }
  }

  Future<String> _getYtDlpPath(String? configuredPath) async {
    final existing = await resolveAvailablePath(configuredPath);
    if (existing != null) {
      // Only return absolute file paths. For PATH-resolved values like
      // "yt-dlp.exe" we still install to the app support directory.
      if (p.isAbsolute(existing)) return existing;
    }

    final appPath = await _getAppBinaryPath();
    if (appPath == null) {
      throw Exception('Could not resolve a writable yt-dlp path');
    }
    return appPath;
  }

  Future<String> _getCurrentYtDlpVersion(String ytDlpPath) async {
    try {
      final workDir = await _getYtDlpWorkingDir();
      final result = await Process.run(
        ytDlpPath,
        ['--version'],
        workingDirectory: workDir,
        runInShell: false,
      );
      return result.stdout.toString().trim();
    } catch (_) {
      return 'unknown';
    }
  }

  /// Returns the local yt-dlp binary version if available.
  ///
  /// Returns `null` when yt-dlp cannot be found or cannot be executed.
  Future<String?> getVersion({String? configuredPath}) async {
    final path = await resolveAvailablePath(configuredPath);
    if (path == null) return null;

    try {
      final workDir = await _getYtDlpWorkingDir();
      final result = await Process.run(
        path,
        ['--version'],
        workingDirectory: workDir,
        runInShell: false,
      ).timeout(const Duration(seconds: 5));
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
      // Audio download: let yt-dlp pick best available format, then extract audio.
      // Using complex format filters like bestaudio[ext=m4a] fails with YouTube's
      // SABR-only streaming experiment. Let yt-dlp choose the best format naturally.
      args.addAll([
        '-f',
        'bestaudio/best',
        '-x',
        '--audio-format',
        formatLower,
        '--audio-quality',
        '${audioBitrate.clamp(64, 320)}k',
      ]);
    }

    // Common options
    args.addAll([
      '--no-mtime',
      '--extractor-args', 'youtube:lang=en',
      '--no-playlist',
      '--newline',
      '--no-colors',
      '--no-overwrites',
      '--no-part',
      '-o', _escapeTemplate(outputPath),
      '--extractor-retries', '3',
      '--retries', '10',
    ]);

    args.addAll([
      '--embed-metadata',
      '--embed-thumbnail',
      '--parse-metadata', '%(uploader|)s:%(meta_artist)s',
      '--parse-metadata', '%(uploader|)s:%(meta_album_artist)s',
      '--parse-metadata', '%(title)s:%(meta_title)s',
      '--add-metadata',
    ]);

    if (sponsorBlockEnabled) {
      args.addAll(['--sponsorblock-remove', 'all']);
    }

    if (ffmpegPath != null &&
        ffmpegPath.trim().isNotEmpty &&
        ffmpegPath.trim() != 'ffmpeg') {
      args.addAll(['--ffmpeg-location', ffmpegPath]);
    }

    // Conditionally pass --js-runtimes node: when Node.js is available
    await _tryApplyNodeRuntime(args);
    // Ensure a JS runtime (Deno) is available for nsig/SABR extraction — a
    // missing/old runtime is a common cause of "page needs to be reloaded".
    await _tryApplyDenoRuntime(args, onProgress);
    // Use tv client which doesn't trigger SABR-only streaming experiment
    args.addAll(['--extractor-args', 'youtube:player_client=tv,web']);

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
    } else if (cookiesFromBrowser != null &&
        cookiesFromBrowser.trim().isNotEmpty) {
      args.addAll(['--cookies-from-browser', cookiesFromBrowser]);
    }

    if (forceGenericExtractor) {
      args.add('--force-generic-extractor');
    }

    await _applyProxyArg(args);
    args.add(url);

    debugPrint('yt-dlp command: $ytDlpPath ${args.join(' ')}');
    final hadCookieArgs =
        args.contains('--cookies') || args.contains('--cookies-from-browser');

    Future<void> runAttempt(List<String> runArgs) async {
      onProgress(0, null, null);
      final workDir = await _getYtDlpWorkingDir();
      final process = await Process.start(
        ytDlpPath,
        runArgs,
        workingDirectory: workDir,
        runInShell: false,
      );

      final cancelTimer =
          Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (isCancelled?.call() ?? false) {
          debugPrint('yt-dlp: cancellation requested, killing process');
          process.kill();
        }
      });

      try {
        final stdoutBuffer = StringBuffer();
        final stdoutSub = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          debugPrint('yt-dlp stdout: $line');
          stdoutBuffer.writeln(line);
          final match = _progressRegex.firstMatch(line);
          if (match != null) {
            final pct = double.tryParse(match.group(1)!)?.toInt() ?? 0;
            final speed = match.group(3) ?? '';
            final eta = match.group(4) ?? '';
            onProgress(pct.clamp(0, 100), speed, eta);
          }
        });

        final stderrBuffer = StringBuffer();
        final stderrSub = process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          debugPrint('yt-dlp stderr: $line');
          stderrBuffer.writeln(line);
        });

        final exitCode = await process.exitCode;
        await stdoutSub.cancel();
        await stderrSub.cancel();

        if (isCancelled?.call() ?? false) {
          await _cleanupFailedDownloadArtifacts(outputPath);
          throw Exception('Cancelled');
        }

        if (exitCode != 0) {
          await _cleanupFailedDownloadArtifacts(outputPath);
          final fullError =
              '${stderrBuffer.toString().trim()}\n${stdoutBuffer.toString().trim()}'
                  .trim();
          debugPrint('yt-dlp full error output:\n$fullError');
          throw Exception('yt-dlp failed (exit $exitCode): $fullError');
        }
      } finally {
        cancelTimer.cancel();
      }
    }

    try {
      await runAttempt(args);
    } catch (e) {
      final message = e.toString();
      final isFormatUnavailable =
          message.contains('Requested format is not available') ||
              message.contains('format is not available');
      final isReloadError =
          message.contains('page needs to be reloaded') ||
              message.contains('UNPLAYABLE') ||
              message.contains('playability status: UNPLAYABLE') ||
              message.contains('sign in to confirm') ||
              message.contains('confirm you are not a bot');
      if (hadCookieArgs && isFormatUnavailable) {
        debugPrint(
            'yt-dlp failed with format unavailable while cookies were enabled; retrying once without cookies');
        final retryArgs = _stripCookieArgs(args);
        await runAttempt(retryArgs);
      } else if (isReloadError) {
        // YouTube-side extractor/player change (e.g. "The page needs to be
        // reloaded"). Self-update throttled to the cooldown window, then retry
        // once — a newer yt-dlp usually has the SABR/nsig patch that fixes it.
        debugPrint('yt-dlp hit a reload/playability error: $message');
        final cooldownOk =
            _lastAutoUpdate == null ||
                DateTime.now().difference(_lastAutoUpdate!) >=
                    _autoUpdateCooldown;
        if (cooldownOk) {
          try {
            final updatedPath = await updateYtDlp(
              configuredPath: null,
              onProgress: null,
            );
            if (updatedPath.isNotEmpty &&
                await File(updatedPath).exists() &&
                updatedPath != ytDlpPath) {
              _lastAutoUpdate = DateTime.now();
              debugPrint(
                  'yt-dlp self-updated to $updatedPath; retrying download once');
              await runAttempt([for (final a in args) a]);
            } else {
              rethrow;
            }
          } catch (updateErr) {
            // Self-update failed; surface the original download error.
            debugPrint('yt-dlp self-update failed ($updateErr); not retrying');
            rethrow;
          }
        } else {
          rethrow;
        }
      } else {
        rethrow;
      }
    }

    if (!await File(outputPath).exists()) {
      final base = outputPath.replaceAll(RegExp(r'\.[^.]+$'), '');
      final candidates = [
        outputPath,
        '$base.$formatLower',
        '$base.mkv',
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
        await _cleanupFailedDownloadArtifacts(outputPath);
        throw Exception(
            'yt-dlp completed but the output file was not created.');
      }
    }

    onProgress(100, null, null);
  }

  // --─ Helpers ----------------------------------------------------------─

  static List<String> _stripCookieArgs(List<String> args) {
    final stripped = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--cookies' || arg == '--cookies-from-browser') {
        if (i + 1 < args.length) i++;
        continue;
      }
      stripped.add(arg);
    }
    return stripped;
  }

  Future<String?> _getAppBinaryPath() async {
    final support = await PlatformDirs.getAppSupportDir();
    if (support == null) return null;
    final binName = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    return '${support.path}${Platform.pathSeparator}yt-dlp${Platform.pathSeparator}$binName';
  }

  static String _escapeTemplate(String path) => path.replaceAll('%', '%%');

  static int _qualityToHeight(String quality) {
    switch (quality) {
      case '360p': return 360;
      case '480p': return 480;
      case '720p': return 720;
      case '1080p': return 1080;
      case '1440p': return 1440;
      case '2160p': return 2160;
      case '4320p': return 4320;
      case 'best': return 9999;
      default: return 720;
    }
  }

  static Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _cleanupFailedDownloadArtifacts(String outputPath) async {
    final base = outputPath.replaceAll(RegExp(r'\.[^.]+$'), '');
    final candidates = <String>{
      outputPath,
      '$outputPath.part',
      '$outputPath.ytdl',
      '$outputPath.temp',
      '$outputPath.tmp',
      '$base.part',
      '$base.ytdl',
      '$base.temp',
      '$base.tmp',
    };
    for (final ext in <String>['mp4', 'mkv', 'webm', 'mp3', 'm4a', 'opus']) {
      candidates.add('$base.$ext.part');
      candidates.add('$base.$ext.ytdl');
      candidates.add('$base.$ext.temp');
      candidates.add('$base.$ext.tmp');
    }
    for (final path in candidates) {
      await _safeDelete(path);
    }
  }

  /// Fallback shell downloader for yt-dlp binary.
  /// Tries: PowerShell WebClient → Invoke-WebRequest → BITS → certutil → curl/wget
  static Future<void> _attemptShellDownload(String url, String dest,
      {bool enforceTls12 = false}) async {
    try {
      final f = File(dest);
      await f.parent.create(recursive: true);
    } catch (_) {}

    if (Platform.isWindows) {
      // Strategy 1: PowerShell WebClient
      try {
        final safeUrl = url.replaceAll("'", "''");
        final safeDest = dest.replaceAll("'", "''");
        final cmd = StringBuffer();
        if (enforceTls12) {
          cmd.write(
              '[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; ');
        }
        cmd.write(
            "try { (New-Object System.Net.WebClient).DownloadFile('$safeUrl','$safeDest') } catch { exit 1 }");
        final pr = await Process.run('powershell', [
          '-NoProfile', '-NonInteractive', '-Command', cmd.toString(),
        ]).timeout(const Duration(seconds: 60));
        if (pr.exitCode == 0) return;
      } catch (_) {}

      // Strategy 2: PowerShell Invoke-WebRequest
      try {
        final safeUrl = url.replaceAll("'", "''");
        final safeDest = dest.replaceAll("'", "''");
        final cmd = StringBuffer();
        if (enforceTls12) {
          cmd.write(
              '[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; ');
        }
        cmd.write(
            "try { Invoke-WebRequest -Uri '$safeUrl' -OutFile '$safeDest' -UseBasicParsing } catch { exit 1 }");
        final pr = await Process.run('powershell', [
          '-NoProfile', '-NonInteractive', '-Command', cmd.toString(),
        ]).timeout(const Duration(seconds: 90));
        if (pr.exitCode == 0) return;
      } catch (_) {}

      // Strategy 3: BITS Transfer
      try {
        final safeUrl = url.replaceAll("'", "''");
        final safeDest = dest.replaceAll("'", "''");
        final cmd =
            "try { Start-BitsTransfer -Source '$safeUrl' -Destination '$safeDest' -Priority High } catch { exit 1 }";
        final pr = await Process.run('powershell', [
          '-NoProfile', '-NonInteractive', '-Command', cmd,
        ]).timeout(const Duration(seconds: 60));
        if (pr.exitCode == 0) return;
      } catch (_) {}

      // Strategy 4: certutil (available on all Windows versions)
      // Cleans up .TMP file and URL cache after success.
      try {
        final safeUrl = url.replaceAll("'", "''");
        final safeDest = dest.replaceAll("'", "''");
        final pr = await Process.run('certutil', [
          '-urlcache', '-split', '-f', safeUrl, safeDest,
        ]).timeout(const Duration(seconds: 90));
        if (pr.exitCode == 0) {
          final tmpFile = File('$dest.TMP');
          if (await tmpFile.exists()) await tmpFile.delete();
          unawaited(Process.run('certutil', ['-urlcache', '-f', safeUrl]));
          return;
        }
      } catch (_) {}

      throw Exception('Shell fallback download failed on Windows');
    }

    // Unix: curl → wget
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
        'No suitable shell downloader found (curl/wget/PowerShell/BITS)');
  }

  /// Try to detect and apply Node.js as a JS runtime for yt-dlp.
  /// Silences the "No supported JavaScript runtime" warning on machines
  /// with Node installed. Never throws — failures are silently ignored.
  Future<void> _tryApplyNodeRuntime(List<String> args) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    try {
      const nodePaths = [
        'C:\\Program Files\\nodejs\\node.exe',
        'C:\\Program Files (x86)\\nodejs\\node.exe',
        '/usr/bin/node',
        '/usr/local/bin/node',
        '/opt/homebrew/bin/node',
      ];
      String? nodePath;
      for (final p in nodePaths) {
        if (await File(p).exists()) {
          nodePath = p;
          break;
        }
      }
      if (nodePath == null) {
        final result = await Process.run(
          Platform.isWindows ? 'where' : 'which', ['node'],
          runInShell: true,
        ).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim()
              .split(RegExp(r'\r?\n'));
          for (final l in lines) {
            if (l.trim().isNotEmpty) {
              nodePath = l.trim();
              break;
            }
          }
        }
      }
      if (nodePath != null && nodePath.isNotEmpty) {
        args.addAll(['--js-runtimes', 'node:$nodePath']);
        debugPrint('yt-dlp: using Node.js JS runtime at $nodePath');
      }
    } catch (_) {
      // Silently ignore — yt-dlp still works without a JS runtime
    }
  }

  /// Ensure a JavaScript runtime (Deno) is available so yt-dlp can evaluate
  /// YouTube's signature / nsig / SABR player code. Without one, modern
  /// yt-dlp emits "The page needs to be reloaded" / UNPLAYABLE errors.
  ///
  /// Tries an existing Deno install first; if none is found it downloads the
  /// standalone Deno binary into the app support dir (lazy, ~25-30 MB) and
  /// reuses it for the rest of the session. Never throws.
  Future<void> _tryApplyDenoRuntime(
    List<String> args,
    void Function(int pct, String? speed, String? eta)? onProgress,
  ) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    try {
      if (_denoPath != null && await File(_denoPath!).exists()) {
        args.addAll(['--js-runtimes', 'deno:$_denoPath']);
        debugPrint('yt-dlp: using Deno runtime at $_denoPath');
        return;
      }

      // Look for an existing Deno install on common paths / PATH.
      final String? denoPath = await _locateExistingDeno();
      if (denoPath != null && await File(denoPath).exists()) {
        _denoPath = denoPath;
        args.addAll(['--js-runtimes', 'deno:$denoPath']);
        debugPrint('yt-dlp: found existing Deno runtime at $denoPath');
        return;
      }

      // Download a bundled Deno binary for the current platform.
      final support = await PlatformDirs.getAppSupportDir();
      if (support == null) return;
      final binDir = Directory(p.join(
          support.path, 'deno'));
      if (!await binDir.exists()) await binDir.create(recursive: true);

      final bool isWindows = Platform.isWindows;
      final String assetName;
      final bool isArmMac = Platform.isMacOS &&
          (await _cpuArchitecture() == 'arm64');
      if (isWindows) {
        assetName = 'deno-x86_64-pc-windows-msvc.zip';
      } else if (Platform.isLinux) {
        assetName = 'deno-x86_64-unknown-linux-gnu.zip';
      } else if (isArmMac) {
        assetName = 'deno-aarch64-apple-darwin.zip';
      } else {
        assetName = 'deno-x86_64-apple-darwin.zip';
      }

      final url =
          'https://github.com/denoland/deno/releases/latest/download/$assetName';
      final destBase = p.join(binDir.path,
          assetName.replaceAll('.zip', ''));
      if (await File(destBase).exists()) {
        _denoPath = destBase;
        args.addAll(['--js-runtimes', 'deno:$destBase']);
        debugPrint('yt-dlp: using previously bundled Deno at $destBase');
        return;
      }

      debugPrint('yt-dlp: downloading Deno runtime ($assetName)');
      final dl = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 60),
          );
      if (dl.statusCode != 200) {
        debugPrint('yt-dlp: Deno download failed HTTP ${dl.statusCode}');
        return;
      }
      final zipPath = p.join(binDir.path, assetName);
      await File(zipPath).writeAsBytes(dl.bodyBytes, flush: true);

      // Deno ships as a zip containing the single binary — extract it.
      if (isWindows) {
        final out = await Process.run('tar',
            ['-xf', zipPath, '-C', binDir.path],
            runInShell: true);
        if (out.exitCode != 0) {
          // Fall back to Expand-Archive on Windows PowerShell.
          await Process.run('powershell',
              ['-NoProfile', '-Command',
               "Expand-Archive -Force '${zipPath.replaceAll("'", "''")}' -DestinationPath '${binDir.path.replaceAll("'", "''")}'"],
              runInShell: true);
        }
      } else {
        await Process.run('tar', ['-xf', zipPath, '-C', binDir.path],
            runInShell: true);
        await Process.run('chmod', ['+x', destBase]);
      }
      try {
        await File(zipPath).delete();
      } catch (_) {}

      if (await File(destBase).exists()) {
        _denoPath = destBase;
        args.addAll(['--js-runtimes', 'deno:$destBase']);
        debugPrint('yt-dlp: Deno runtime ready at $destBase');
      } else {
        debugPrint('yt-dlp: Deno extraction produced no binary at $destBase');
      }
    } catch (e) {
      debugPrint('yt-dlp: failed to provision Deno runtime: $e');
    }
  }

  /// Look for a system Deno install (common paths then PATH).
  Future<String?> _locateExistingDeno() async {
    const paths = [
      'C:\\Program Files\\deno\\deno.exe',
      '/usr/bin/deno',
      '/usr/local/bin/deno',
      '/opt/homebrew/bin/deno',
      '/root/.deno/bin/deno',
    ];
    for (final pPath in paths) {
      if (await File(pPath).exists()) return pPath;
    }
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which', ['deno'],
        runInShell: true,
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim()
            .split(RegExp(r'\r?\n'));
        for (final l in lines) {
          if (l.trim().isNotEmpty) {
            final candidate = l.trim();
            if (await File(candidate).exists()) return candidate;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String> _cpuArchitecture() async {
    try {
      final r = await Process.run(Platform.isWindows ? 'echo' : 'uname',
          Platform.isWindows ? ['%PROCESSOR_ARCHITECTURE%'] : ['-m'],
          runInShell: true);
      return r.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return 'x86_64';
    }
  }

  /// Apply proxy settings to yt-dlp arguments if configured.
  Future<void> _applyProxyArg(List<String> args) async {
    final proxy = await NetworkProxyService.ytDlpProxyUrl();
    if (proxy != null && proxy.isNotEmpty) {
      args.addAll(['--proxy', proxy]);
    }
  }
}