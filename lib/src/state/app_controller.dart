import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/convert_result.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../services/convert_service.dart';
import '../services/download_service.dart';
import '../services/installer_service.dart';
import '../services/log_service.dart';
import '../services/settings_store.dart';
import '../services/youtube_service.dart';

class AppController extends ChangeNotifier {
  final SettingsStore settingsStore;
  final YouTubeService youtube;
  final DownloadService downloadService;
  final ConvertService convertService;
  final InstallerService installerService;
  final LogService logs;

  AppSettings? _settings;
  AppSettings? get settings => _settings;

  bool previewLoading = false;
  List<PreviewItem> previewItems = <PreviewItem>[];
  List<QueueItem> queue = <QueueItem>[];
  final Map<String, DownloadToken> _tokens = {};
  final List<ConvertResult> convertResults = <ConvertResult>[];

  AppController({
    required this.settingsStore,
    required this.youtube,
    required this.downloadService,
    required this.convertService,
    required this.installerService,
    required this.logs,
  });

  Future<void> init() async {
    _settings = await settingsStore.load();
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings next) async {
    _settings = next;
    await settingsStore.save(next);
    notifyListeners();
  }

  Future<void> preview(String url, bool expandPlaylist) async {
    if (_settings == null) {
      return;
    }
    previewLoading = true;
    notifyListeners();
    try {
      final items = await youtube.preview(
        url,
        expandPlaylist: expandPlaylist,
        limit: _settings!.previewMaxEntries,
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
    _tokens[item.url]?.cancel();
    queue = List<QueueItem>.from(queue)..remove(item);
    notifyListeners();
  }

  Future<void> downloadSingle(QueueItem item) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    final token = DownloadToken();
    _tokens[item.url] = token;
    _updateQueue(item, item.copyWith(status: DownloadStatus.downloading, progress: 0, error: null));

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
        ffmpegPath: settings.ffmpegPath,
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
    } catch (e) {
      final updated = item.copyWith(status: DownloadStatus.failed, error: '$e');
      _updateQueue(item, updated);
      logs.add('Download failed: $e');
    } finally {
      _tokens.remove(item.url);
    }
  }

  Future<void> downloadAll() async {
    final pending = queue.where((item) => item.status != DownloadStatus.downloading).toList();
    for (final item in pending) {
      await downloadSingle(item);
    }
  }

  void cancelDownload(QueueItem item) {
    _tokens[item.url]?.cancel();
    final updated = item.copyWith(status: DownloadStatus.cancelled, error: 'Cancelled');
    _updateQueue(item, updated);
  }

  void resumeDownload(QueueItem item) {
    final reset = item.copyWith(status: DownloadStatus.queued, progress: 0, error: null);
    _updateQueue(item, reset);
    downloadSingle(reset);
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
    final result = await convertService.convertFile(file, target, ffmpegPath: settings.ffmpegPath);
    convertResults.add(result);
    notifyListeners();
  }

  Future<void> saveConvertedResult(ConvertResult result) async {
    final path = await _resolveSavePath(result.name);
    if (path == null) {
      return;
    }
    final file = File(path);
    await file.writeAsBytes(result.bytes, flush: true);
    logs.add('Saved converted file: $path');
  }

  Future<String?> _resolveSavePath(String filename) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getDownloadsDirectory();
      if (dir == null) {
        final docs = await getApplicationDocumentsDirectory();
        return '${docs.path}${Platform.pathSeparator}$filename';
      }
      return '${dir.path}${Platform.pathSeparator}$filename';
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
}
