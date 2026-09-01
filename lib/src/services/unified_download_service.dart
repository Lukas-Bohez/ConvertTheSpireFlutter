import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import '../models/unified_download_task.dart';
import 'folder_history_service.dart';
import 'settings_store.dart';

/// TrackSpire Downloads — orchestrates Direct HTTP + BitTorrent downloads
/// behind one list for the Unified Downloads dashboard
/// (lib/src/screens/unified_downloads_screen.dart).
///
/// Does NOT replace the existing yt-dlp pipeline in
/// lib/src/services/download_service.dart — that keeps driving QueueItem
/// media conversions exactly as it does today. Pass a [mediaQueueProjection]
/// to show those alongside these for *display only*; this service never
/// writes to that pipeline.
///
/// Torrent starts are delegated through [torrentEngine], a small seam over
/// the real TorrentEngineService (lib/src/vault/services/torrent_engine_service.dart)
/// rather than importing vault/ directly — the vault subsystem currently
/// has its own settings/DI setup, separate from the main app's, so this
/// keeps that boundary intact until someone deliberately decides to merge
/// them. See the companion masterprompt's open questions for exactly what
/// to confirm before wiring a real implementation in.
class UnifiedDownloadService extends ChangeNotifier {
  UnifiedDownloadService({this.torrentEngine, this.mediaQueueProjection});

  /// Optional until the real TorrentEngineService accessor is confirmed —
  /// see masterprompt Module 2. Torrent enqueues fail closed with a clear
  /// error message on the task itself when this is null, rather than
  /// silently doing nothing.
  final TorrentEngineAdapter? torrentEngine;

  /// Optional read-only snapshot function over DownloadService's active
  /// QueueItems, mapped to UnifiedDownloadTask for display purposes only.
  /// Returns an empty list if not wired up.
  final List<UnifiedDownloadTask> Function()? mediaQueueProjection;

  static const _prefsKey = 'trackspire_unified_downloads_v1';

  final Map<String, UnifiedDownloadTask> _tasks = {};
  final Map<String, bool> _stopFlags = {};

  List<UnifiedDownloadTask> get tasks {
    final combined = [..._tasks.values, ...?mediaQueueProjection?.call()];
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }

  Future<void> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    for (final entry in raw) {
      try {
        final json = jsonDecode(entry) as Map<String, dynamic>;
        final task = UnifiedDownloadTask.fromJson(json);
        _tasks[task.id] = task;
      } catch (_) {
        // one corrupt entry should never take the rest of the list down
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _tasks.values.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_prefsKey, raw);
  }

  /// Same fallback chain the TrackSpire playlist-tracking masterprompt
  /// specified: explicit destination, then the app's single remembered
  /// "last folder" (FolderHistoryService — there's no per-format global
  /// folder yet in the real codebase), then the platform default.
  Future<String> _resolveDestinationDir(String? explicitDir) async {
    if (explicitDir != null && explicitDir.trim().isNotEmpty) return explicitDir;
    final last = await FolderHistoryService().getLastFolder();
    if (last != null && last.trim().isNotEmpty) return last;
    return SettingsStore().resolveDefaultDownloadDir();
  }

  // ---------------- Direct HTTP ----------------

  Future<UnifiedDownloadTask> enqueueHttp({
    required String url,
    required String title,
    required UnifiedDownloadCategory category,
    UnifiedPostDownloadAction postDownloadAction = UnifiedPostDownloadAction.none,
    String? destinationDir,
  }) async {
    // Hard safety gate, enforced here (not just in the UI) so no future
    // call site can bypass it by accident: a Play Store build must never
    // fetch and handle an app update itself. Callers on that flavor should
    // hand APK/update links to launchUrl(mode: LaunchMode.externalApplication)
    // instead and let the OS take it fully outside the app's own code.
    if (category == UnifiedDownloadCategory.appUpdate && kPlayStoreBuild) {
      throw StateError(
        'Refusing to self-download an app update on a Play Store build. '
        'See masterprompt_bitplayer_inapp_browser_downloads.md, Module 1.',
      );
    }

    final task = UnifiedDownloadTask(
      id: _newId(),
      title: title,
      sourceUrl: url,
      type: UnifiedDownloadType.directHttp,
      category: category,
      postDownloadAction: postDownloadAction,
      createdAt: DateTime.now(),
    );
    _tasks[task.id] = task;
    notifyListeners();
    unawaited(_persist());
    unawaited(
      _runHttpDownload(task.id, await _resolveDestinationDir(destinationDir)),
    );
    return task;
  }

  Future<void> _runHttpDownload(
    String taskId,
    String destinationDir, {
    int resumeFromBytes = 0,
  }) async {
    _stopFlags[taskId] = false;
    final task = _tasks[taskId];
    if (task == null) return;
    _update(taskId, (t) => t.copyWith(status: UnifiedDownloadStatus.downloading));

    final client = http.Client();
    try {
      await Directory(destinationDir).create(recursive: true);
      final savePath = task.savePath ??
          '$destinationDir${Platform.pathSeparator}'
              '${_fileNameFromUrl(task.sourceUrl, fallback: task.title)}';

      final request = http.Request('GET', Uri.parse(task.sourceUrl));
      var startAt = resumeFromBytes;
      if (startAt > 0) request.headers['Range'] = 'bytes=$startAt-';

      final response = await client.send(request);
      final isResumed = startAt > 0 && response.statusCode == 206;
      if (!isResumed) startAt = 0; // server ignored/doesn't support Range - start clean
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total =
          isResumed ? startAt + (response.contentLength ?? 0) : (response.contentLength ?? 0);
      final sink = File(savePath).openWrite(
        mode: isResumed ? FileMode.append : FileMode.write,
      );

      int received = startAt;
      final started = DateTime.now();
      await for (final chunk in response.stream) {
        if (_stopFlags[taskId] == true) break;
        sink.add(chunk);
        received += chunk.length;
        final secs = DateTime.now().difference(started).inMilliseconds / 1000.0;
        _update(
          taskId,
          (t) => t.copyWith(
            bytesDownloaded: received,
            totalBytes: total,
            downloadSpeedBytesPerSec:
                secs > 0 ? ((received - startAt) / secs).round() : 0,
          ),
        );
      }
      await sink.flush();
      await sink.close();

      // pause()/cancel() already set the task's terminal status
      // synchronously before this loop could notice the flag, so by the
      // time we get here _tasks[taskId]?.status reliably tells us which
      // one happened.
      final finalStatus = _tasks[taskId]?.status;
      if (finalStatus == UnifiedDownloadStatus.canceled) {
        await _safeDelete(savePath);
      } else if (finalStatus == UnifiedDownloadStatus.paused) {
        _update(taskId, (t) => t.copyWith(savePath: savePath, bytesDownloaded: received));
      } else {
        _update(
          taskId,
          (t) => t.copyWith(
            status: UnifiedDownloadStatus.completed,
            savePath: savePath,
            bytesDownloaded: received,
            completedAt: DateTime.now(),
          ),
        );
        await _maybeRunPostDownloadAction(taskId);
      }
    } catch (e) {
      _update(
        taskId,
        (t) => t.copyWith(status: UnifiedDownloadStatus.failed, errorMessage: e.toString()),
      );
    } finally {
      client.close();
      unawaited(_persist());
    }
  }

  Future<void> _maybeRunPostDownloadAction(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.savePath == null) return;
    switch (task.postDownloadAction) {
      case UnifiedPostDownloadAction.promptInstall:
        // Second check here even though enqueueHttp already refuses to get
        // this far for appUpdate on a Play Store build - costs nothing and
        // keeps this method safe if it's ever called from somewhere else.
        if (kPlayStoreBuild) return;
        // TODO(cline): call InstallerService().installApk(task.savePath!)
        // once that method exists. installer_service.dart today only has
        // installFfmpeg() (download + checksum + extract) - extend it with
        // the same shape rather than adding a second install service. See
        // masterprompt_bitplayer_fullversion_tv.md, Module 2, for the
        // REQUEST_INSTALL_PACKAGES / FileProvider details.
        break;
      case UnifiedPostDownloadAction.revealInFolder:
      case UnifiedPostDownloadAction.none:
        break;
    }
  }

  // ---------------- Torrent ----------------

  Future<UnifiedDownloadTask> enqueueTorrent({
    required String url, // magnet: URI, or an https URL to a .torrent file
    required String title,
    String? destinationDir,
  }) async {
    final task = UnifiedDownloadTask(
      id: _newId(),
      title: title,
      sourceUrl: url,
      type: UnifiedDownloadType.torrent,
      category: UnifiedDownloadCategory.media,
      createdAt: DateTime.now(),
    );
    _tasks[task.id] = task;
    notifyListeners();
    unawaited(_persist());

    final engine = torrentEngine;
    if (engine == null) {
      _update(
        task.id,
        (t) => t.copyWith(
          status: UnifiedDownloadStatus.failed,
          errorMessage: 'Torrent engine not wired up yet - see UnifiedDownloadService docs.',
        ),
      );
      unawaited(_persist());
      return task;
    }

    final dir = await _resolveDestinationDir(destinationDir);
    _update(task.id, (t) => t.copyWith(status: UnifiedDownloadStatus.downloading));
    try {
      if (url.toLowerCase().startsWith('magnet:')) {
        await engine.startFromMagnet(task.id, url, destinationPath: dir);
      } else {
        final bytes = await http.readBytes(Uri.parse(url));
        await engine.cacheTorrentSource(task.id, bytes);
        await engine.startTorrent(task.id, destinationPath: dir);
      }
    } catch (e) {
      _update(
        task.id,
        (t) => t.copyWith(status: UnifiedDownloadStatus.failed, errorMessage: e.toString()),
      );
    }
    unawaited(_persist());
    return task;
  }

  // ---------------- Shared controls ----------------

  void cancel(String id) {
    _stopFlags[id] = true;
    final task = _tasks[id];
    if (task?.type == UnifiedDownloadType.torrent) {
      // TorrentEngineService's own stopTorrent(id) already exists
      // (~line 3184) - call it here once torrentEngine exposes it in the
      // adapter, so the underlying task actually stops rather than just
      // disappearing from this list.
    }
    _update(id, (t) => t.copyWith(status: UnifiedDownloadStatus.canceled));
  }

  void pause(String id) {
    final task = _tasks[id];
    if (task?.type == UnifiedDownloadType.torrent) {
      // TorrentEngineService.pauseTorrent(id) already exists (~line 3216).
      // Route torrent pause there directly rather than through _stopFlags,
      // which only governs this service's own HTTP download loop.
      _update(id, (t) => t.copyWith(status: UnifiedDownloadStatus.paused));
      return;
    }
    _stopFlags[id] = true;
    _update(id, (t) => t.copyWith(status: UnifiedDownloadStatus.paused));
  }

  Future<void> resume(String id) async {
    final task = _tasks[id];
    if (task == null || task.status != UnifiedDownloadStatus.paused) return;
    if (task.type == UnifiedDownloadType.torrent) {
      // TorrentEngineService.resumeTorrent(id) already exists (~line 3232).
      await torrentEngine?.startTorrent(id, destinationPath: null);
      _update(id, (t) => t.copyWith(status: UnifiedDownloadStatus.downloading));
      return;
    }
    final dir = task.savePath != null
        ? File(task.savePath!).parent.path
        : await _resolveDestinationDir(null);
    unawaited(_runHttpDownload(id, dir, resumeFromBytes: task.bytesDownloaded));
  }

  Future<void> retry(String id) async {
    final task = _tasks[id];
    if (task == null) return;
    _update(
      id,
      (t) => t.copyWith(
        status: UnifiedDownloadStatus.queued,
        bytesDownloaded: 0,
        errorMessage: null,
      ),
    );
    if (task.type == UnifiedDownloadType.torrent) {
      final engine = torrentEngine;
      if (engine == null) return;
      final dir = await _resolveDestinationDir(null);
      _update(id, (t) => t.copyWith(status: UnifiedDownloadStatus.downloading));
      try {
        // Assumes cacheTorrentSource from the first attempt is still on
        // disk in the engine's own managed-source cache. If Cline finds
        // that's not reliable, re-fetch+re-cache here the same way
        // enqueueTorrent does for the non-magnet case.
        await engine.startTorrent(id, destinationPath: dir);
      } catch (e) {
        _update(
          id,
          (t) => t.copyWith(status: UnifiedDownloadStatus.failed, errorMessage: e.toString()),
        );
      }
    } else {
      final dir = await _resolveDestinationDir(null);
      unawaited(_runHttpDownload(id, dir));
    }
    unawaited(_persist());
  }

  /// Removes the entry from the dashboard WITHOUT touching any file on
  /// disk. This is deliberately a different method from [deleteFile] — the
  /// same "never silent, never implicit" rule TrackSpire's playlist
  /// pruning uses applies here too: clearing a row from a list is not the
  /// same action as deleting a file, and this codebase should never make
  /// them look like the same tap.
  void removeEntry(String id) {
    _tasks.remove(id);
    notifyListeners();
    unawaited(_persist());
  }

  /// The ONLY method in this service that deletes a file from disk. Call
  /// this only after the user has confirmed through
  /// lib/src/widgets/delete_download_dialog.dart — never from a background
  /// tick, never automatically on cancel of a completed item.
  Future<void> deleteFile(String id) async {
    final task = _tasks[id];
    if (task?.savePath == null) {
      _tasks.remove(id);
      notifyListeners();
      unawaited(_persist());
      return;
    }
    await _safeDelete(task!.savePath!);
    _tasks.remove(id);
    notifyListeners();
    unawaited(_persist());
  }

  // ---------------- Helpers ----------------

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _update(String id, UnifiedDownloadTask Function(UnifiedDownloadTask) fn) {
    final current = _tasks[id];
    if (current == null) return;
    _tasks[id] = fn(current);
    notifyListeners();
  }

  String _fileNameFromUrl(String url, {required String fallback}) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.isNotEmpty && segments.last.trim().isNotEmpty) {
        return Uri.decodeComponent(segments.last);
      }
    } catch (_) {}
    final safe = fallback.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return safe.isEmpty ? 'download' : safe;
  }

  // Same defensive shape as DownloadService._safeDelete
  // (lib/src/services/download_service.dart, ~line 1701): try, check
  // exists, delete, swallow. Duplicated rather than imported because that
  // method is private to DownloadService — if you'd rather not duplicate
  // it, expose a public static wrapper there instead and call it from here.
  Future<void> _safeDelete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Minimal seam over TorrentEngineService
/// (lib/src/vault/services/torrent_engine_service.dart) so this module
/// doesn't need to import vault/ directly. Write one small concrete class
/// implementing this against the real service once its main-app accessor
/// is confirmed (see masterprompt open questions). The three methods below
/// map onto real, existing methods:
///   - `cacheTorrentSource(String torrentId, List<int> torrentBytes)` — exact
///     match, confirmed at torrent_engine_service.dart ~line 1040.
///   - startTorrent(String torrentId, {String? destinationPath}) — exact
///     match, confirmed at ~line 1254.
///   - startFromMagnet — NOT confirmed. The engine has a private
///     _startFromMagnet around line 1620; find and use whatever its public
///     caller actually is rather than assuming this name.
abstract class TorrentEngineAdapter {
  Future<void> cacheTorrentSource(String torrentId, List<int> torrentBytes);
  Future<void> startTorrent(String torrentId, {String? destinationPath});
  Future<void> startFromMagnet(String torrentId, String magnetUri,
      {String? destinationPath});
}
