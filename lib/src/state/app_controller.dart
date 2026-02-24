import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../services/settings_store.dart';
import '../services/statistics_service.dart';
import '../services/watched_playlist_service.dart';
import '../services/youtube_service.dart';

class AppController extends ChangeNotifier {
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

  bool previewLoading = false;
  List<PreviewItem> previewItems = <PreviewItem>[];
  List<QueueItem> queue = <QueueItem>[];
  final Map<String, DownloadToken> _tokens = {};
  final List<ConvertResult> convertResults = <ConvertResult>[];
  Future<String?>? _ffmpegInstall;
  bool _downloadAllRunning = false;

  AppController({
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
    await statisticsService.load();
    await notificationService.initialize();
    notifyListeners();

    // Auto-install FFmpeg on boot (desktop only; mobile bundles FFmpegKit)
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _ensureFfmpegOnBoot();
    }
  }

  /// Fire-and-forget FFmpeg check at startup so it's ready before downloads.
  void _ensureFfmpegOnBoot() {
    unawaited(Future(() async {
      final settings = _settings;
      if (settings == null) return;
      final resolved = await downloadService.ffmpeg.resolveAvailablePath(settings.ffmpegPath);
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

  Future<void> saveSettings(AppSettings next) async {
    _settings = next;
    await settingsStore.save(next);
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

  Future<void> preview(String url, bool expandPlaylist, {int startIndex = 0, int? limit}) async {
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

  void addToQueue(PreviewItem item, String format) {
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
        ),
      );
    notifyListeners();
  }

  void removeFromQueue(QueueItem item) {
    final key = '${item.url}|${item.format}';
    _tokens[key]?.cancel();
    queue = List<QueueItem>.from(queue)
      ..removeWhere((q) => q.url == item.url && q.format == item.format);
    notifyListeners();
  }

  Future<void> downloadSingle(QueueItem item) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    // Resolve title if it's still a raw URL (user downloaded without preview)
    if (item.title.startsWith('http://') || item.title.startsWith('https://')) {
      try {
        final video = await downloadService.yt.videos.get(item.url)
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
    _updateQueue(item, item.copyWith(status: DownloadStatus.downloading, progress: 0, error: null));
    logs.add('Preparing download: ${item.title} [${item.format.toUpperCase()}]');

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
        final result = await downloadService.download(
          previewItem,
          format: item.format,
          outputDir: settings.downloadDir,
          ffmpegPath: ffmpegPath,
          token: token,
          onProgress: (pct, status) {
            final updated = item.copyWith(progress: pct, status: status);
            _updateQueue(item, updated);
          },
        );
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
          await Future.delayed(Duration(seconds: (_settings?.retryBackoffSeconds ?? 3)));
        } else {
          final updated = item.copyWith(status: DownloadStatus.failed, error: msg);
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
    if (_downloadAllRunning) return; // already processing; new items picked up by the loop below
    _downloadAllRunning = true;
    try {
      while (true) {
        final pending = queue.where((item) => item.status == DownloadStatus.queued).toList();
        if (pending.isEmpty) break;

        final workers = (_settings?.maxWorkers ?? 3).clamp(1, 10);
        int index = 0;

        Future<void> worker() async {
          while (true) {
            final i = index;
            if (i >= pending.length) break;
            index++;
            await downloadSingle(pending[i]);
          }
        }

        await Future.wait(
          List.generate(workers.clamp(1, pending.length), (_) => worker()),
        );
        // Loop back to check if new items were queued while we were downloading
      }
    } finally {
      _downloadAllRunning = false;
    }
  }

  void cancelDownload(QueueItem item) {
    final key = '${item.url}|${item.format}';
    _tokens[key]?.cancel();
    final updated = item.copyWith(status: DownloadStatus.cancelled, error: 'Cancelled');
    _updateQueue(item, updated);
  }

  void resumeDownload(QueueItem item) {
    final reset = item.copyWith(status: DownloadStatus.queued, progress: 0, error: null);
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

  Future<void> installFfmpeg(Uri url, {String? checksum, void Function(int, String)? onProgress}) async {
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
      final result = await convertService.convertFile(file, target, ffmpegPath: ffmpegPath);
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

  void _updateQueue(QueueItem original, QueueItem updated) {
    final index = queue.indexWhere((q) => q.url == original.url && q.format == original.format);
    if (index == -1) {
      return;
    }
    final next = List<QueueItem>.from(queue);
    next[index] = updated;
    queue = next;
    notifyListeners();
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
    const nonMediaFormats = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'pdf', 'txt', 'zip', 'epub'};
    if (nonMediaFormats.contains(formatLower)) {
      return settings.ffmpegPath;
    }

    // MP4 is downloaded natively but may need FFmpeg for thumbnail embed.
    // Still try to resolve PATH so we have a working path when available.
    if (formatLower == 'mp4') {
      return await downloadService.ffmpeg.resolveAvailablePath(settings.ffmpegPath) ?? settings.ffmpegPath;
    }

    // Check configured path AND system PATH
    final resolved = await downloadService.ffmpeg.resolveAvailablePath(settings.ffmpegPath);
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
    const url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip';
    try {
      final path = await installerService.installFfmpeg(
        url: Uri.parse(url),
        onProgress: (pct, message) {
          if (pct == 0 || pct == 60 || pct == 100) {
            logs.add('FFmpeg $message ($pct%)');
          }
        },
      ).timeout(const Duration(minutes: 5),
          onTimeout: () => throw TimeoutException('FFmpeg download timed out after 5 minutes'));
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

  /// Add a SearchResult to the download queue.
  void addSearchResultToQueue(models.SearchResult result, {String? format}) {
    final fmt = format ?? _settings?.defaultAudioFormat ?? 'mp3';
    addToQueue(
      PreviewItem(
        id: result.id,
        title: result.title,
        url: 'https://www.youtube.com/watch?v=${result.id}',
        uploader: result.artist,
        duration: result.duration,
        thumbnailUrl: result.thumbnailUrl,
      ),
      fmt,
    );
  }

  /// Bulk import: parses queries and adds each best match to the queue.
  Future<void> processBulkImport(List<String> queries, {String? format}) async {
    int found = 0;
    int failed = 0;
    for (final query in queries) {
      try {
        final results = await searchService.youtubeSearcher.search(query, limit: 1);
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
    logs.add('Bulk import: $found queued, $failed failed out of ${queries.length}');
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
    previewPlayer.dispose();
    super.dispose();
  }
}
