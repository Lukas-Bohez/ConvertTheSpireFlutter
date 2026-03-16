import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/platform_dirs.dart';

import '../models/app_settings.dart';
import '../models/convert_result.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../models/search_result.dart' as models;
import '../services/bulk_import_service.dart';
import '../services/convert_service.dart';
import '../services/download_service.dart';
import '../services/file_organization_service.dart';
import '../services/installer_service.dart';
import '../services/log_service.dart';
import '../services/metadata_service.dart';
import '../services/multi_source_search_service.dart';
import '../services/notification_service.dart';
import '../services/playlist_service.dart';
import '../services/preview_player_service.dart';
import '../services/android_saf.dart';
import '../services/settings_store.dart';
import '../services/statistics_service.dart';
import '../services/watched_playlist_service.dart';
import '../services/youtube_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppController extends ChangeNotifier {
  final WebViewEnvironment? webViewEnvironment;
  final SettingsStore settingsStore;
  final YouTubeService youtube;
  final DownloadService downloadService;
  final ConvertService convertService;
  final InstallerService installerService;
  final LogService logs;

  // ── New feature services ──────────────────────────────────────────────
  final MultiSourceSearchService searchService;
  final PreviewPlayerService previewPlayer;
  final PlaylistService playlistService;
  final WatchedPlaylistService watchedPlaylistService;
  final BulkImportService bulkImportService;
  final MusicBrainzService musicBrainzService;
  final LyricsService lyricsService;
  final FileOrganizationService fileOrganizationService;
  final StatisticsService statisticsService;
  final NotificationService notificationService;

  AppSettings? _settings;
  AppSettings? get settings => _settings;
  // Active tab index for the shell (0-13). Restored once at startup.
  int _activeTabIndex = 13;
  int get activeTabIndex => _activeTabIndex;

  // Onboarding/version gating
  bool onboardingChecked = false;
  bool needsOnboarding = false;
  String? currentAppVersion;

  bool previewLoading = false;
  List<PreviewItem> previewItems = <PreviewItem>[];
  List<QueueItem> queue = <QueueItem>[];
  static const _queueKey = 'persisted_queue';
  final Map<String, DownloadToken> _tokens = {};
  final List<ConvertResult> convertResults = <ConvertResult>[];
  Future<String?>? _ffmpegInstall;
  bool _downloadAllRunning = false;

  AppController({
    this.webViewEnvironment,
    required this.settingsStore,
    required this.youtube,
    required this.downloadService,
    required this.convertService,
    required this.installerService,
    required this.logs,
    required this.searchService,
    required this.previewPlayer,
    required this.playlistService,
    required this.watchedPlaylistService,
    required this.bulkImportService,
    required this.musicBrainzService,
    required this.lyricsService,
    required this.fileOrganizationService,
    required this.statisticsService,
    required this.notificationService,
  });

  Future<void> init() async {
    _settings = await settingsStore.load();
    // Load non-critical services individually so a single failure doesn't
    // prevent the app from starting. Errors are logged and initialization
    // continues.
    try {
      await statisticsService.load();
    } catch (e, st) {
      logs.add('StatisticsService failed to load: $e');
      if (kDebugMode) debugPrint('StatisticsService.load error: $e\n$st');
    }
    try {
      await notificationService.initialize();
    } catch (e, st) {
      logs.add('NotificationService failed to initialize: $e');
      if (kDebugMode)
        debugPrint('NotificationService.initialize error: $e\n$st');
    }
    notifyListeners();

    // Restore last selected tab (if present). Only restore once during
    // controller initialization to avoid racing with manual navigation.
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('last_tab');
      if (saved != null) {
        var selected = saved;
        if (selected == 2) selected = 13; // never restore directly into browser
        _activeTabIndex = selected;
        if (kDebugMode)
          debugPrint('[AppController] restored last_tab -> $_activeTabIndex');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppController] prefs restore failed: $e');
    }

    // Check whether onboarding needs to be shown for this app version.
    unawaited(checkOnboardingStatus());

    // Load persisted queue (if any)
    try {
      await _loadQueue();
    } catch (_) {}

    // Auto-install FFmpeg on boot (desktop only; mobile bundles FFmpegKit)
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _ensureFfmpegOnBoot();
      _ensureYtDlpOnBoot();
    }
  }

  /// Programmatic tab switch. Persists preference and notifies listeners.
  void switchToTab(int index) {
    if (index < 0 || index > 13) return;
    if (index == _activeTabIndex) return;
    if (kDebugMode)
      debugPrint(
          '[AppController] switchToTab requested: $_activeTabIndex -> $index\n${StackTrace.current}');
    _activeTabIndex = index;
    // Persist asynchronously; don't await here.
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setInt('last_tab', index));
    notifyListeners();
  }

  /// Fire-and-forget FFmpeg check at startup so it's ready before downloads.
  void _ensureFfmpegOnBoot() {
    unawaited(Future(() async {
      final settings = _settings;
      if (settings == null) return;
      final resolved = await downloadService.ffmpeg
          .resolveAvailablePath(settings.ffmpegPath);
      if (resolved != null) {
        // Already available – persist resolved path if it wasn't saved
        if (settings.ffmpegPath != resolved) {
          await saveSettings(settings.copyWith(ffmpegPath: resolved));
        }
        return;
      }
      // Not found – attempt auto-install (Windows only; Linux/macOS log a hint)
      try {
        _ffmpegInstall ??= _installFfmpeg(settings);
        await _ffmpegInstall;
      } catch (e) {
        logs.add('FFmpeg not found on startup: $e');
      } finally {
        _ffmpegInstall = null;
      }
    }).catchError((_) {}));
  }

  /// Fire-and-forget yt-dlp check at startup so HD downloads work immediately.
  void _ensureYtDlpOnBoot() {
    unawaited(Future(() async {
      final settings = _settings;
      if (settings == null) return;
      final resolved =
          await downloadService.ytDlp.resolveAvailablePath(settings.ytDlpPath);
      if (resolved != null) {
        if (settings.ytDlpPath != resolved) {
          await saveSettings(settings.copyWith(ytDlpPath: resolved));
        }
        logs.add('yt-dlp found: $resolved');
        return;
      }
      // Not found – auto-download (Windows/Linux/macOS)
      try {
        final path = await downloadService.ytDlp.ensureAvailable(
          configuredPath: settings.ytDlpPath,
          onProgress: (pct, message) {
            if (pct == 0 || pct == 100) logs.add('yt-dlp $message ($pct%)');
          },
        );
        await saveSettings(settings.copyWith(ytDlpPath: path));
        logs.add('yt-dlp installed: $path');
      } catch (e) {
        logs.add('yt-dlp auto-download skipped: $e');
      }
    }).catchError((_) {}));
  }

  Future<void> saveSettings(AppSettings next) async {
    _settings = next;
    await settingsStore.save(next);
    notifyListeners();
  }

  Future<void> checkOnboardingStatus() async {
    try {
      final info = await PackageInfo.fromPlatform();
      currentAppVersion = info.version;
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString('onboardingSeenVersion');
      needsOnboarding = seen != currentAppVersion;
    } catch (e) {
      needsOnboarding = false;
    } finally {
      onboardingChecked = true;
      notifyListeners();
    }
  }

  /// Called by the app when the lifecycle state changes. Used to adjust
  /// Android notification behavior (allow dismissal when app is backgrounded).
  void handleAppLifecycleState(AppLifecycleState state) {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // If downloads banner is shown, make it dismissible while the app
        // is backgrounded so the user can swipe it away. When the app
        // resumes we re-show it as ongoing to indicate active work.
        final remaining =
            queue.where((item) => item.status == DownloadStatus.queued).length;
        if (remaining > 0) {
          if (state == AppLifecycleState.paused ||
              state == AppLifecycleState.inactive ||
              state == AppLifecycleState.detached) {
            unawaited(notificationService.showActiveDownloadsBanner(remaining,
                ongoing: false));
          } else if (state == AppLifecycleState.resumed) {
            unawaited(notificationService.showActiveDownloadsBanner(remaining,
                ongoing: true));
          }
        }
      }
    } catch (_) {}
  }

  Future<void> completeOnboarding() async {
    final v = currentAppVersion ?? 'unknown';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('onboardingSeenVersion', v);
    needsOnboarding = false;
    notifyListeners();
  }

  /// Update the application's theme preference and persist it.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_settings == null) return;
    final str = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await saveSettings(_settings!.copyWith(themeMode: str));
  }

  Future<void> preview(String url, bool expandPlaylist,
      {int startIndex = 0, int? limit}) async {
    if (_settings == null) {
      return;
    }
    previewLoading = true;
    notifyListeners();
    try {
      final items = await youtube.preview(
        url,
        expandPlaylist: expandPlaylist,
        limit: limit ?? _settings!.previewMaxEntries,
        startIndex: startIndex,
      );
      previewItems = items;
      logs.add('Preview loaded: ${items.length} items');
    } catch (e) {
      logs.add('Preview failed: $e');
      previewItems = <PreviewItem>[];
    } finally {
      previewLoading = false;
      notifyListeners();
    }
  }

  void addToQueue(PreviewItem item, String format,
      {String? videoQuality}) {
    if (queue.any((q) => q.url == item.url && q.format == format)) {
      return;
    }
    queue = List<QueueItem>.from(queue)
      ..add(
        QueueItem(
          url: item.url,
          title: item.title,
          format: format,
          uploader: item.uploader,
          thumbnailBytes: null,
          progress: 0,
          status: DownloadStatus.queued,
          outputPath: null,
          error: null,
          videoQuality: videoQuality,
        ),
      );
    notifyListeners();
    unawaited(_saveQueue());
  }

  void removeFromQueue(QueueItem item) {
    final key = '${item.url}|${item.format}';
    _tokens[key]?.cancel();
    queue = List<QueueItem>.from(queue)
      ..removeWhere((q) => q.url == item.url && q.format == item.format);
    notifyListeners();
    unawaited(_saveQueue());
  }

  Future<void> downloadSingle(QueueItem item) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    // Resolve title if it's still a raw URL (user downloaded without preview)
    // Only attempt YouTube metadata fetch for YouTube URLs
    final isYouTube = _isYouTubeUrl(item.url);
    if (isYouTube &&
        (item.title.startsWith('http://') ||
            item.title.startsWith('https://'))) {
      try {
        final video = await downloadService.yt.videos
            .get(item.url)
            .timeout(const Duration(seconds: 15));
        final resolved = item.copyWith(title: video.title);
        _updateQueue(item, resolved);
        item = resolved;
      } catch (_) {
        // Keep URL title if resolution fails
      }
    }

    final token = DownloadToken();
    final key = '${item.url}|${item.format}';
    _tokens[key] = token;
    _updateQueue(
        item,
        item.copyWith(
            status: DownloadStatus.downloading, progress: 0, error: null));
    logs.add(
        'Preparing download: ${item.title} [${item.format.toUpperCase()}]');

    String? ffmpegPath = settings.ffmpegPath;
    try {
      ffmpegPath = await _ensureFfmpegPath(settings, item.format);
    } catch (e) {
      final msg = _cleanError(e);
      final updated = item.copyWith(status: DownloadStatus.failed, error: msg);
      _updateQueue(item, updated);
      logs.add('FFmpeg setup failed: $msg');
      _tokens.remove(key);
      return;
    }

    final maxAttempts = (_settings?.retryCount ?? 2).clamp(1, 5);
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (token.cancelled) break;
      try {
        final previewItem = PreviewItem(
          id: item.url,
          title: item.title,
          url: item.url,
          uploader: item.uploader ?? '',
          duration: null,
          thumbnailUrl: null,
        );

        DownloadResult result;
        if (isYouTube) {
          // YouTube → use youtube_explode_dart (with yt-dlp fast-path on desktop)
          result = await downloadService.download(
            previewItem,
            format: item.format,
            outputDir: settings.downloadDir,
            ffmpegPath: ffmpegPath,
            token: token,
            ytDlpPath: settings.ytDlpPath,
            sponsorBlockEnabled: settings.sponsorBlockEnabled,
            onProgress: (pct, status, {String? speed, String? eta}) {
              final updated = item.copyWith(progress: pct, status: status, speed: speed, eta: eta);
              _updateQueue(item, updated);
            },
            preferredVideoQuality:
                item.videoQuality ?? settings.preferredVideoQuality,
            preferredAudioBitrate: settings.preferredAudioBitrate,
          );
        } else {
          // Non-YouTube → route to yt-dlp generic download
          result = await downloadService.downloadGeneric(
            previewItem,
            format: item.format,
            outputDir: settings.downloadDir,
            ffmpegPath: ffmpegPath,
            token: token,
            ytDlpPath: settings.ytDlpPath,
            sponsorBlockEnabled: settings.sponsorBlockEnabled,
            onProgress: (pct, status, {String? speed, String? eta}) {
              final updated = item.copyWith(progress: pct, status: status, speed: speed, eta: eta);
              _updateQueue(item, updated);
            },
            preferredVideoQuality: settings.preferredVideoQuality,
            preferredAudioBitrate: settings.preferredAudioBitrate,
          );
        }
        final updated = item.copyWith(
          progress: 100,
          status: DownloadStatus.completed,
          outputPath: result.path,
          thumbnailBytes: result.thumbnail ?? item.thumbnailBytes,
        );
        _updateQueue(item, updated);
        logs.add('Download complete: ${result.path}');
        _tokens.remove(key);
        // Fire-and-forget: notification/stats failures must never
        // mask a successful download.
        unawaited(onDownloadCompleted(
          title: item.title,
          artist: item.uploader ?? '',
          source: 'youtube',
          format: item.format,
          success: true,
        ).catchError((_) {}));
        return; // success – exit retry loop
      } catch (e) {
        final msg = _cleanError(e);
        // Don't retry YouTube permanent errors (bot detection, unavailable, etc.)
        final isRetryable = !_isYouTubePermanentError(msg) &&
            !token.cancelled &&
            !msg.contains('Cancelled');
        if (attempt < maxAttempts && isRetryable) {
          logs.add('Download attempt $attempt failed: $msg – retrying...');
          _updateQueue(item, item.copyWith(progress: 0, error: null));
          await Future.delayed(
              Duration(seconds: (_settings?.retryBackoffSeconds ?? 3)));
        } else {
          final updated =
              item.copyWith(status: DownloadStatus.failed, error: msg);
          _updateQueue(item, updated);
          logs.add('Download failed: $msg');
          unawaited(onDownloadCompleted(
            title: item.title,
            artist: item.uploader ?? '',
            source: 'youtube',
            format: item.format,
            success: false,
          ).catchError((_) {}));
        }
      }
    }
    _tokens.remove(key);
  }

  Future<void> downloadAll() async {
    if (_downloadAllRunning)
      return; // already processing; new items picked up by the loop below
    _downloadAllRunning = true;
    try {
      while (true) {
        final pending = queue
            .where((item) => item.status == DownloadStatus.queued)
            .toList();
        if (pending.isEmpty) break;

        // Show ongoing notification so OS keeps process alive
        await notificationService.showActiveDownloadsBanner(pending.length);

        final workers = (_settings?.maxWorkers ?? 3).clamp(1, 10);

        Future<void> worker() async {
          while (true) {
            QueueItem? next;
            if (pending.isEmpty) break;
            // Take the first pending item (work-stealing).
            next = pending.removeAt(0);
            await downloadSingle(next);
          }
        }

        await Future.wait(
          List.generate(workers.clamp(1, pending.length), (_) => worker()),
        );
        // Loop back to check if new items were queued while we were downloading
      }
    } finally {
      _downloadAllRunning = false;
      await notificationService.cancelActiveDownloadsBanner();
    }
  }

  void cancelDownload(QueueItem item) {
    final key = '${item.url}|${item.format}';
    _tokens[key]?.cancel();
    final updated =
        item.copyWith(status: DownloadStatus.cancelled, error: 'Cancelled');
    _updateQueue(item, updated);
  }

  void resumeDownload(QueueItem item) {
    // Guard against duplicate concurrent downloads (downloadAll may pick this
    // item up before downloadSingle progresses past its first await).
    final key = '${item.url}|${item.format}';
    if (_tokens.containsKey(key) && !_tokens[key]!.cancelled) return;
    final reset =
        item.copyWith(status: DownloadStatus.queued, progress: 0, error: null);
    _updateQueue(item, reset);
    downloadSingle(reset);
  }

  void changeQueueItemFormat(QueueItem item, String newFormat) {
    // Prevent duplicate: another queue item with the same URL + new format
    if (queue.any((q) => q.url == item.url && q.format == newFormat)) {
      return;
    }
    final updated = item.copyWith(format: newFormat);
    _updateQueue(item, updated);
  }

  Future<void> installFfmpeg(Uri url,
      {String? checksum, void Function(int, String)? onProgress}) async {
    final path = await installerService.installFfmpeg(
      url: url,
      checksumSha256: checksum,
      onProgress: onProgress,
    );
    final settings = _settings;
    if (settings == null) {
      return;
    }
    await saveSettings(settings.copyWith(ffmpegPath: path));
  }

  Future<void> convert(File file, String target) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    try {
      final ffmpegPath = await _ensureFfmpegPath(settings, target);
      final result = await convertService.convertFile(file, target,
          ffmpegPath: ffmpegPath);
      convertResults.add(result);
      logs.add('Conversion complete: ${result.name}');
      notifyListeners();
    } catch (e) {
      logs.add('Conversion failed: $e');
      notifyListeners();
    }
  }

  Future<void> saveConvertedResult(ConvertResult result) async {
    if (kIsWeb) {
      logs.add('Saving files is not supported on web.');
      return;
    }
    final settings = _settings;
    // On Android, if the configured download folder is a SAF tree (content://)
    // use the native channel to copy the file into the tree so it's visible
    // to other apps. Otherwise fall back to writing to the resolved path.
    if (Platform.isAndroid &&
        settings != null &&
        settings.downloadDir.startsWith('content://')) {
      try {
        final cache = await PlatformDirs.getCacheDir();
        final tmp =
            File('${cache.path}${Platform.pathSeparator}${result.name}');
        await tmp.writeAsBytes(result.bytes, flush: true);
        final saf = AndroidSaf();
        final mime = _mimeForExtension(result.name.split('.').last);
        final dest = await saf.copyToTree(
          treeUri: settings.downloadDir,
          sourcePath: tmp.path,
          displayName: result.name,
          mimeType: mime,
        );
        try {
          await tmp.delete();
        } catch (_) {}
        if (dest != null && dest.isNotEmpty) {
          logs.add('Saved converted file: $dest');
          return;
        }
      } catch (e) {
        logs.add('SAF save failed: $e');
        // fall through to legacy path
      }
    }

    final path = await _resolveSavePath(result.name);
    if (path == null) {
      return;
    }
    final file = File(path);
    await file.writeAsBytes(result.bytes, flush: true);
    logs.add('Saved converted file: $path');
  }

  Future<String?> _resolveSavePath(String filename) async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) {
      final extDir = await PlatformDirs.getExternalDir();
      if (extDir != null) {
        return '${extDir.path}${Platform.pathSeparator}$filename';
      }
      final filesDir = await PlatformDirs.getFilesDir();
      if (filesDir != null) {
        return '${filesDir.path}${Platform.pathSeparator}$filename';
      }
      return null;
    }

    return FilePicker.platform.saveFile(fileName: filename);
  }

  String _mimeForExtension(String ext) {
    final e = ext.toLowerCase();
    switch (e) {
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'mp4':
        return 'video/mp4';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  void _updateQueue(QueueItem original, QueueItem updated) {
    final index = queue.indexWhere(
        (q) => q.url == original.url && q.format == original.format);
    if (index == -1) {
      return;
    }
    final next = List<QueueItem>.from(queue);
    next[index] = updated;
    queue = next;
    notifyListeners();
    unawaited(_saveQueue());
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filtered = queue
          .where((q) =>
              q.status == DownloadStatus.queued ||
              q.status == DownloadStatus.failed ||
              q.status == DownloadStatus.cancelled ||
              q.status == DownloadStatus.completed)
          .toList();
      final data = jsonEncode(filtered.map((q) => q.toJson()).toList());
      await prefs.setString(_queueKey, data);
    } catch (_) {}
  }

  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final restored = list
          .map((e) => QueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (restored.isNotEmpty) {
        queue = List<QueueItem>.from(queue)..addAll(restored);
        notifyListeners();
      }
    } catch (_) {
      // Corrupted data — remove to avoid repeated failures
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_queueKey);
      } catch (_) {}
    }
  }

  /// Strip 'Exception: ' prefix and simplify verbose error messages.
  static String _cleanError(Object e) {
    var s = '$e';
    // Remove class name prefixes like "VideoUnplayableException: " etc.
    final prefixes = [
      'Exception: ',
      'VideoUnplayableException: ',
      'VideoUnavailableException: ',
      'VideoRequiresPurchaseException: ',
      'TimeoutException: ',
      'RequestLimitExceededException: ',
      'FatalFailureException: ',
    ];
    for (final prefix in prefixes) {
      if (s.startsWith(prefix)) {
        s = s.substring(prefix.length);
        break;
      }
    }
    // Trim multi-line messages to the first meaningful line
    final lines = s.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length > 2) {
      return lines.take(2).join(' ');
    }
    return s;
  }

  /// Returns true for YouTube errors that will never succeed on retry
  /// (bot detection, video unavailable/private, unplayable).
  static bool _isYouTubePermanentError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('unplayable') ||
        lower.contains('unavailable') ||
        lower.contains('sign in') ||
        lower.contains('confirm you\'re not a bot') ||
        lower.contains('private') ||
        lower.contains('does not exist') ||
        lower.contains('taken down') ||
        lower.contains('not supported on web');
  }

  Future<String?> _ensureFfmpegPath(AppSettings settings, String format) async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) {
      return settings.ffmpegPath;
    }

    final formatLower = format.toLowerCase();

    // Non-media formats (images, docs) don't need FFmpeg at all
    const nonMediaFormats = {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'bmp',
      'tiff',
      'tif',
      'webp',
      'pdf',
      'txt',
      'zip',
      'cbz',
      'epub'
    };
    if (nonMediaFormats.contains(formatLower)) {
      return settings.ffmpegPath;
    }

    // MP4 is downloaded natively but may need FFmpeg for thumbnail embed.
    // Still try to resolve PATH so we have a working path when available.
    if (formatLower == 'mp4') {
      return await downloadService.ffmpeg
              .resolveAvailablePath(settings.ffmpegPath) ??
          settings.ffmpegPath;
    }

    // Check configured path AND system PATH
    final resolved =
        await downloadService.ffmpeg.resolveAvailablePath(settings.ffmpegPath);
    if (resolved != null) return resolved;

    _ffmpegInstall ??= _installFfmpeg(settings);
    try {
      return await _ffmpegInstall;
    } finally {
      _ffmpegInstall = null;
    }
  }

  Future<String?> _installFfmpeg(AppSettings settings) async {
    if (kIsWeb) {
      throw Exception('FFmpeg is not available on web.');
    }
    if (Platform.isLinux) {
      throw Exception(
        'FFmpeg is required for audio conversion but was not found on your system PATH.\n'
        'Install it with: sudo apt install ffmpeg\n'
        'Or on Fedora: sudo dnf install ffmpeg\n'
        'Or set the path manually in Settings.',
      );
    }
    if (!Platform.isWindows) {
      throw Exception(
        'FFmpeg is required for audio conversion but was not found.\n'
        'Install it via your system package manager or set the path in Settings.',
      );
    }

    logs.add('FFmpeg not found. Downloading automatically...');
    const url =
        'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
    try {
      final path = await installerService
          .installFfmpeg(
            url: Uri.parse(url),
            onProgress: (pct, message) {
              if (pct == 0 || pct == 60 || pct == 100) {
                logs.add('FFmpeg $message ($pct%)');
              }
            },
          )
          .timeout(const Duration(minutes: 5),
              onTimeout: () => throw TimeoutException(
                  'FFmpeg download timed out after 5 minutes'));
      await saveSettings(settings.copyWith(ffmpegPath: path));
      logs.add('FFmpeg installed: $path');
      return path;
    } catch (e) {
      logs.add('FFmpeg auto-install failed: $e');
      throw Exception(
        'FFmpeg is required for audio conversion but could not be installed automatically. '
        'Install FFmpeg manually and ensure it is on your system PATH, '
        'or set the path in Settings.',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // New feature methods
  // ═══════════════════════════════════════════════════════════════════════

  /// Multi-source search
  Future<List<models.SearchResult>> multiSearch(String query) async {
    try {
      final results = await searchService.searchAll(query);
      logs.add('Search found ${results.length} results for "$query"');
      return results;
    } catch (e) {
      logs.add('Search failed: $e');
      return [];
    }
  }

  /// Detect whether a URL is a YouTube video/playlist.
  static bool _isYouTubeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      return host.contains('youtube.com') ||
          host.contains('youtu.be') ||
          host.contains('music.youtube.com');
    } catch (_) {
      return false;
    }
  }

  /// Add a SearchResult to the download queue.
  ///
  /// YouTube results are queued with a `youtube.com/watch?v=` URL.
  /// Generic (non-YouTube) results are queued with the raw URL stored in [id].
  void addSearchResultToQueue(models.SearchResult result,
      {String? format, String? videoQuality}) {
    final fmt = format ?? _settings?.defaultAudioFormat ?? 'mp3';

    // If source is 'generic', the ID *is* the URL (set by BrowserScreen)
    final isGeneric = result.source == 'generic';
    final url =
        isGeneric ? result.id : 'https://www.youtube.com/watch?v=${result.id}';

    addToQueue(
      PreviewItem(
        id: result.id,
        title: result.title,
        url: url,
        uploader: result.artist,
        duration: result.duration,
        thumbnailUrl: result.thumbnailUrl,
      ),
      fmt,
      videoQuality: videoQuality,
    );
  }

  /// Bulk import: parses queries and adds each best match to the queue.
  Future<void> processBulkImport(List<String> queries, {String? format}) async {
    int found = 0;
    int failed = 0;
    for (final query in queries) {
      try {
        final results =
            await searchService.youtubeSearcher.search(query, limit: 1);
        if (results.isEmpty) {
          failed++;
          continue;
        }
        addSearchResultToQueue(results.first, format: format);
        found++;
      } catch (_) {
        failed++;
      }
    }
    logs.add(
        'Bulk import: $found queued, $failed failed out of ${queries.length}');
    notifyListeners();
  }

  /// Record a completed download in statistics and show notification.
  Future<void> onDownloadCompleted({
    required String title,
    required String artist,
    required String source,
    required String format,
    required bool success,
  }) async {
    await statisticsService.recordDownload(
      success: success,
      artist: artist,
      source: source,
      format: format,
    );
    if (success && (_settings?.showNotifications ?? false)) {
      await notificationService.showDownloadComplete(title, artist);
    }
  }

  @override
  void dispose() {
    watchedPlaylistService.dispose();
    previewPlayer.dispose();
    try {
      youtube.close();
    } catch (_) {}
    super.dispose();
  }
}
