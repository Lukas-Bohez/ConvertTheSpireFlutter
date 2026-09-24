import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/queue_item.dart';
import '../models/search_result.dart';
import '../services/ad_service.dart';
import '../services/android_saf.dart';
import '../services/media_organizer.dart';
import '../services/platform_dirs.dart';
import '../services/playlist_service.dart';
import '../state/app_controller.dart';
import '../utils/folder_label.dart';
import '../utils/l10n.dart';
import '../utils/snack.dart';
import '../widgets/tv_file_browser.dart';

/// Screen for loading a playlist, cross-referencing it against a local folder,
/// and taking action on missing / matched / extra tracks.
class PlaylistScreen extends StatefulWidget {
  final PlaylistService playlistService;

  /// Queues [tracks] for download. [folder] is the folder that was compared,
  /// so missing tracks land next to the ones already there; null means the
  /// usual download folder.
  final void Function(List<SearchResult> tracks, String format, String? folder)
      onDownloadMissing;
  final ValueNotifier<PendingPlaylistRequest?>? pendingRequest;

  const PlaylistScreen({
    super.key,
    required this.playlistService,
    required this.onDownloadMissing,
    this.pendingRequest,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final _urlController = TextEditingController();
  final _folderController = TextEditingController();

  bool _loading = false;
  String? _loadingMessage;
  List<SearchResult>? _tracks;
  PlaylistInfo? _playlistInfo;
  PlaylistFolderComparison? _comparison;
  Set<SearchResult> _missingSelection = {};
  int? _lastMissingSelectedIndex;
  String? _error;
  String _selectedFormat = 'mp3';
  String? _playlistDiagnostics;

  /// AppController, captured post-frame so downloads that complete while this
  /// screen is open can reconcile the Missing tab in memory (see
  /// [_reconcileDownloadedMissing]). Null when the controller is not in scope.
  AppController? _appController;

  // Extras auto-resolve state
  bool _extrasBusy = false;
  // Target folder for "not in playlist" moves - prompted once, then reused.
  String? _extrasTargetFolder;

  late final TabController _tabController;

  // Filter / sort state
  double _confidenceFilter = 0; // 0 = show all
  _SortMode _sortMode = _SortMode.original;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    widget.pendingRequest?.addListener(_onPendingRequest);
    // Process any pending request that was set before initState ran
    final pending = widget.pendingRequest?.value;
    if (pending != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _processPendingRequest(pending));
    }
    // Listen to AppController so the Missing tab updates live when a
    // previously-missing track finishes downloading (read-only listener,
    // captured post-frame like _extrasSettings does).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final controller = context.read<AppController>();
        _appController = controller;
        controller.addListener(_onControllerChanged);
        _reconcileDownloadedMissing();
      } catch (_) {
        // AppController not in scope (widget used standalone) — the live
        // reconcile is unavailable; the Compare button still refreshes.
      }
      unawaited(_restoreCompareFolder());
    });
  }

  static const String _compareFolderPrefsKey = 'playlist_compare_folder';

  /// Fills in the folder so Compare works without a trip to the picker: the
  /// last folder compared, else where this app saves downloads.
  Future<void> _restoreCompareFolder() async {
    if (_folderController.text.trim().isNotEmpty) return;
    String? folder;
    try {
      final prefs = await SharedPreferences.getInstance();
      folder = prefs.getString(_compareFolderPrefsKey);
    } catch (_) {}
    if (folder == null || folder.trim().isEmpty) {
      folder = await _defaultCompareFolder();
    }
    if (!mounted || folder.trim().isEmpty) return;
    if (_folderController.text.trim().isNotEmpty) return;
    setState(() => _folderController.text = folder!);
  }

  /// The folder this app downloads [_selectedFormat] files into. On a phone
  /// with no folder picked that is the shared `Download/<format>` folder.
  Future<String> _defaultCompareFolder() async {
    final configured = _formatTargetFor('.$_selectedFormat').trim();
    if (configured.isNotEmpty) return configured;
    final downloads = await PlatformDirs.getPublicDownloadsDir();
    if (downloads == null || downloads.isEmpty) return '';
    return p.join(downloads, _selectedFormat);
  }

  Future<void> _rememberCompareFolder(String folder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_compareFolderPrefsKey, folder);
    } catch (_) {}
  }

  void _onPendingRequest() {
    final pending = widget.pendingRequest?.value;
    if (pending == null) return;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _processPendingRequest(pending));
  }

  Future<void> _processPendingRequest(PendingPlaylistRequest request) async {
    // Clear the pending request immediately so re-pasting the URL works
    widget.pendingRequest?.value = null;

    _urlController.text = request.url;
    // Keep the format chosen where the link was pasted; it used to fall
    // back to MP3 here whatever was picked.
    final format = request.format.toLowerCase();
    if (const {'mp3', 'm4a', 'mp4'}.contains(format)) {
      setState(() => _selectedFormat = format);
    }
    await _loadPlaylist();
    if (request.folder.trim().isNotEmpty) {
      _folderController.text = request.folder;
    } else if (_folderController.text.trim().isEmpty) {
      _folderController.text = await _defaultCompareFolder();
    }
    if (_folderController.text.trim().isEmpty) return;
    await _compareToFolder(promptForFolder: false);
  }

  // --─ Actions --------------------------------------------------------------

  Future<void> _loadPlaylist() async {
    AdService.instance.registerInteraction();
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _loadingMessage = context.l10n.fetchingPlaylist;
      _error = null;
      _comparison = null;
      _playlistInfo = null;
      _playlistDiagnostics = null;
    });

    try {
      final info = await widget.playlistService.getPlaylistInfo(url);
      final tracks = await widget.playlistService.getYouTubePlaylistTracks(url);

      if (!mounted) return;
      setState(() {
        _playlistInfo = info;
        _tracks = tracks;
        _playlistDiagnostics = widget.playlistService.lastPlaylistDiagnostics;
        _loading = false;
        _loadingMessage = null;
        _tabController.index = 0; // Switch to Overview tab
        _missingSelection.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingMessage = null;
      });
    }
  }

  /// Returns true when a folder was chosen.
  Future<bool> _pickFolder() async {
    AdService.instance.registerInteraction();
    final result = await pickDirectoryPath(
      context,
      dialogTitle: context.l10n.selectMusicFolderCompare,
    );
    if (result == null || result.isEmpty || !mounted) return false;
    setState(() => _folderController.text = result);
    return true;
  }

  /// Picks a folder, then compares against it straight away.
  Future<void> _pickFolderAndCompare() async {
    if (await _pickFolder() && _tracks != null && _tracks!.isNotEmpty) {
      await _compareToFolder();
    }
  }

  Future<void> _compareToFolder(
      {bool jumpToBestTab = true, bool promptForFolder = true}) async {
    AdService.instance.registerInteraction();
    if (_tracks == null || _tracks!.isEmpty) return;
    var folder = _folderController.text.trim();
    if (folder.isEmpty) {
      // Pressing Compare with no folder used to do nothing at all.
      if (!promptForFolder || !await _pickFolder()) return;
      folder = _folderController.text.trim();
    }

    setState(() {
      _loading = true;
      _error = null;
      _loadingMessage = context.l10n.scanningFolderMatching;
    });

    try {
      final comparison = await widget.playlistService.compareToFolder(
        _tracks!,
        folder,
      );
      unawaited(_rememberCompareFolder(folder));
      if (!mounted) return;
      setState(() {
        _comparison = comparison;
        _loading = false;
        _loadingMessage = null;
        _missingSelection = comparison.missing.toSet();
        // After an Extras auto-resolve refresh, stay where the user is.
        if (jumpToBestTab) {
          // Jump to the most interesting tab
          if (comparison.missingCount > 0) {
            _tabController.index = 2; // Missing tab
          } else {
            _tabController.index = 1; // Matched tab
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingMessage = null;
      });
    }
  }

  // --─ Live Missing-tab reconciliation --------------------------------------

  void _onControllerChanged() {
    if (!mounted) return;
    _reconcileDownloadedMissing();
  }

  /// Moves tracks out of the Missing tab the moment their download completes.
  ///
  /// "Download Selected" only *queues* work — it returns immediately while
  /// AppController downloads in the background — and previously nothing ever
  /// re-checked afterwards, so the Missing tab kept showing a stale snapshot
  /// from the last Compare run even after the queue panel showed the same
  /// track as completed. Instead of rescanning the folder, this reconciles
  /// against the queue itself: a track whose queue item has reached
  /// DownloadStatus.completed moves missing → matched in memory (the queue's
  /// outputPath is ground truth; the next full Compare will agree since the
  /// file is really in the folder).
  void _reconcileDownloadedMissing() {
    final comparison = _comparison;
    if (comparison == null || comparison.missing.isEmpty) return;
    final controller = _appController;
    if (controller == null) return;

    // Cheap early exits: nothing completed in the queue, nothing to move.
    final completed = controller.queue
        .where((q) => q.status == DownloadStatus.completed)
        .toList();
    if (completed.isEmpty) return;

    final downloaded = <SearchResult, QueueItem>{};
    for (final track in comparison.missing) {
      for (final q in completed) {
        if (_queueUrlMatchesTrack(q.url, track)) {
          downloaded[track] = q;
          break;
        }
      }
    }
    if (downloaded.isEmpty || !mounted) return;

    setState(() {
      final remaining =
          comparison.missing.where((t) => !downloaded.containsKey(t)).toList();
      final matched = List<TrackMatch>.of(comparison.matched);
      downloaded.forEach((track, q) {
        final path = q.outputPath ?? '';
        matched.add(TrackMatch(
          track: track,
          filePath: path,
          fileName: path.isEmpty ? '' : p.basename(path),
          // Downloaded by this app with a known output path — ground truth.
          confidence: 1.0,
          method: MatchMethod.exact,
          fileIndex: -1, // no folder-scan index; de-dup only applies to scans
        ));
      });
      _comparison = PlaylistFolderComparison(
        total: comparison.total,
        matched: matched,
        missing: remaining,
        extras: comparison.extras,
        folderPath: comparison.folderPath,
        filesScanned: comparison.filesScanned,
      );
      _missingSelection.removeAll(downloaded.keys);
    });
  }

  /// True when [queueUrl] is the download URL that was queued for [track].
  ///
  /// YouTube results are queued as `https://www.youtube.com/watch?v=<id>`
  /// (see AppController.addSearchResultToQueue); generic results queue their
  /// raw URL, which is stored in SearchResult.id itself.
  bool _queueUrlMatchesTrack(String queueUrl, SearchResult track) {
    if (track.id.isEmpty) return false;
    if (queueUrl == track.id) return true; // generic source: the id IS the url
    final uri = Uri.tryParse(queueUrl);
    if (uri == null) return false;
    return uri.queryParameters['v'] == track.id ||
        uri.path.endsWith('/${track.id}');
  }

  // --─ Extras auto-resolve -------------------------------------------------

  AppSettings? get _extrasSettings {
    // Best-effort read: if the action runs outside a build pass (e.g. an
    // async resolve triggered by a button), degrade to null and let the
    // caller prompt for a folder instead of failing the whole operation.
    try {
      return context.read<AppController>().settings;
    } catch (_) {
      return null;
    }
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Deletes an extra file, SAF-aware (content:// documents via the native
  /// channel). Returns true when the file is gone afterwards.
  Future<bool> _deleteExtraFile(ExtraFile f) async {
    try {
      if (f.filePath.startsWith('content://')) {
        final ok = await AndroidSaf().deleteSafUri(uri: f.filePath);
        debugPrint('[Extras] deleteSafUri(${f.fileName}) -> $ok');
        return ok;
      }
      final file = File(f.filePath);
      if (!file.existsSync()) return true;
      file.deleteSync();
      debugPrint('[Extras] Deleted ${f.filePath}');
      return true;
    } catch (e) {
      debugPrint('[Extras] Delete failed ${f.filePath}: $e');
      return false;
    }
  }

  /// Verifies that [f] exists at [targetFolder] before deleting the original.
  ///
  /// For filesystem targets this checks that a file with the same basename
  /// exists at the destination AND has a non-zero size (sanity check).
  /// For SAF (`content://`) targets, per-file path verification requires
  /// enumerating the tree via the native channel; callers should guard SAF
  /// deletes with moveAndDeduplicate's aggregate `moved` count (done in
  /// [_moveExtrasToTarget]).
  bool _destinationVerified(ExtraFile f, String targetFolder) {
    if (targetFolder.startsWith('content://')) {
      // SAF: cannot verify a specific file path without native enumeration.
      // Caller guards with `moved > 0` from moveAndDeduplicate.
      return true;
    }
    final destPath = p.join(targetFolder, p.basename(f.filePath));
    final dest = File(destPath);
    if (!dest.existsSync()) {
      debugPrint('[Extras] SAFEGUARD: destination missing for ${f.fileName}');
      return false;
    }
    if (dest.lengthSync() == 0) {
      debugPrint(
          '[Extras] SAFEGUARD: destination file is empty for ${f.fileName}');
      return false;
    }
    return true;
  }

  /// Copies an extra file into [stagingDir], normalising SAF content://
  /// sources through the native temp-copy channel first. Returns the staged
  /// file or null on failure.
  Future<File?> _stageExtraFile(ExtraFile f, String stagingDir) async {
    try {
      final destName = p.basename(f.filePath);
      final dest = File(p.join(stagingDir, destName));
      if (f.filePath.startsWith('content://')) {
        final temp = await PlatformDirs.copyToTemp(f.filePath);
        if (temp == null) {
          debugPrint('[Extras] copyToTemp failed for ${f.filePath}');
          return null;
        }
        File(temp).copySync(dest.path);
      } else {
        File(f.filePath).copySync(dest.path);
      }
      return dest;
    } catch (e) {
      debugPrint('[Extras] Staging failed ${f.filePath}: $e');
      return null;
    }
  }

  List<ExtraFile> _extrasOfKind(PlaylistExtraKind kind) =>
      _comparison?.extras.where((e) => e.kind == kind).toList() ??
      const <ExtraFile>[];

  /// Resolves the configured destination folder for a file extension:
  /// per-format folder from settings when set, else the default download dir.
  String _formatTargetFor(String extension) {
    final settings = _extrasSettings;
    final fallback = settings?.downloadDir.trim() ?? '';
    if (settings == null) return fallback;
    switch (extension.toLowerCase()) {
      case '.mp3':
        return _nonEmpty(settings.downloadDirMp3) ?? fallback;
      case '.m4a':
        return _nonEmpty(settings.downloadDirM4a) ?? fallback;
      case '.mp4':
        return _nonEmpty(settings.downloadDirMp4) ?? fallback;
      default:
        return fallback;
    }
  }

  /// Moves [files] into [targetFolder] using the app's SAF-aware
  /// `MediaOrganizer.moveAndDeduplicate` (copy + dedupe), then deletes the
  /// originals so the net effect is a true move. Re-runs the comparison
  /// afterwards so the Extras tab reflects the new state.
  Future<void> _moveExtrasToTarget(
    List<ExtraFile> files,
    String targetFolder,
    String label,
  ) async {
    if (files.isEmpty || targetFolder.trim().isEmpty) return;
    if (_extrasBusy) return;
    setState(() => _extrasBusy = true);
    try {
      // Prepare target (filesystem targets only; SAF trees already exist).
      if (!targetFolder.startsWith('content://')) {
        await Directory(targetFolder).create(recursive: true);
      }

      // Stage the specific files in a throwaway cache directory so we hand
      // only the intended files to moveAndDeduplicate, never whole folders.
      final cacheDir = await PlatformDirs.getCacheDir();
      final staging = Directory(p.join(cacheDir.path,
          'extras_move_${DateTime.now().millisecondsSinceEpoch}'));
      await staging.create(recursive: true);

      var staged = 0;
      for (final f in files) {
        if (await _stageExtraFile(f, staging.path) != null) staged++;
      }
      debugPrint('[Extras] Staged $staged/${files.length} files for "$label"');

      if (staged == 0) {
        try {
          staging.deleteSync();
        } catch (_) {}
        if (mounted) {
          Snack.show(context, context.l10n.noFilesCouldMoved,
              level: SnackLevel.error);
        }
        return;
      }

      final result =
          await MediaOrganizer.moveAndDeduplicate([staging.path], targetFolder);
      final moved = result['moved'] ?? 0;
      final deleted = result['deleted'] ?? 0;
      debugPrint('[Extras] moveAndDeduplicate result: $result');

      // True move semantics: remove the originals that were copied over.
      // SAFETY: only delete an original after positively verifying it exists
      // at the new destination. If moveAndDeduplicate moved nothing
      // (e.g. unwritable target), all originals are kept untouched — a
      // "resolve" action must never destroy a file that was never moved.
      if (moved == 0) {
        debugPrint('[Extras] SAFEGUARD: 0 files moved to destination; '
            'keeping ${files.length} originals');
      } else {
        for (final f in files) {
          if (!mounted) break;
          if (_destinationVerified(f, targetFolder)) {
            await _deleteExtraFile(f);
          } else {
            debugPrint('[Extras] SAFEGUARD: ${f.fileName} not verified at '
                'destination, keeping original');
          }
        }
      }
      try {
        staging.deleteSync();
      } catch (_) {}

      if (mounted) {
        Snack.show(
            context, context.l10n.movedFilesDeletedDuplicates(label, moved, deleted),
            level: moved > 0 ? SnackLevel.success : SnackLevel.info);
      }
      await _compareToFolder(jumpToBestTab: false);
    } catch (e) {
      debugPrint('[Extras] Auto-resolve failed: $e');
      if (mounted) {
        Snack.show(context, context.l10n.autoResolveFailed(e), level: SnackLevel.error);
      }
    } finally {
      if (mounted) setState(() => _extrasBusy = false);
    }
  }

  /// Prompts for a target folder and stores it for reuse.
  Future<void> _chooseExtrasTarget(String dialogTitle) async {
    final result = await pickDirectoryPath(context, dialogTitle: dialogTitle);
    if (result != null && result.isNotEmpty) {
      setState(() => _extrasTargetFolder = result);
    }
  }

  /// Remove every incomplete (`.temp.`) download in one pass.
  Future<void> _autoResolveIncomplete() async {
    final extras = _extrasOfKind(PlaylistExtraKind.incompleteDownload);
    if (extras.isEmpty || _extrasBusy) return;
    setState(() => _extrasBusy = true);
    try {
      var removed = 0;
      for (final f in extras) {
        if (await _deleteExtraFile(f)) removed++;
      }
      debugPrint('[Extras] Deleted $removed/${extras.length} incomplete');
      if (mounted) {
        Snack.show(context, context.l10n.deletedIncompleteDownloadFiles(removed),
            level: removed > 0 ? SnackLevel.success : SnackLevel.info);
      }
      await _compareToFolder(jumpToBestTab: false);
    } finally {
      if (mounted) setState(() => _extrasBusy = false);
    }
  }

  /// Move wrong-format files to the configured folder for their extension.
  Future<void> _autoResolveWrongFormat() async {
    final extras = _extrasOfKind(PlaylistExtraKind.wrongFormat);
    if (extras.isEmpty || _extrasBusy) return;

    // Group by extension so each group lands in its own configured folder.
    final byExtension = <String, List<ExtraFile>>{};
    for (final e in extras) {
      byExtension.putIfAbsent(e.extension.toLowerCase(), () => []).add(e);
    }
    for (final entry in byExtension.entries) {
      if (!mounted) return;
      var target = _formatTargetFor(entry.key);
      if (target.isEmpty) {
        await _chooseExtrasTarget(context.l10n.chooseFolderFiles(entry.key));
        target = _extrasTargetFolder ?? '';
      }
      await _moveExtrasToTarget(entry.value, target,
          context.l10n.movedFiles(entry.value.length, entry.key));
    }
  }

  /// Move files that are the right format but not in the playlist to the
  /// user-chosen folder (prompted once, reused for subsequent resolves).
  Future<void> _autoResolveNotInPlaylist() async {
    final extras = _extrasOfKind(PlaylistExtraKind.notInPlaylist);
    if (extras.isEmpty || _extrasBusy) return;

    if (_extrasTargetFolder == null || _extrasTargetFolder!.trim().isEmpty) {
      await _chooseExtrasTarget(context.l10n.chooseFolderMoveExtraFiles);
    }
    await _moveExtrasToTarget(extras, _extrasTargetFolder?.trim() ?? '',
        context.l10n.movedFilesNotPlaylist(extras.length));
  }

  /// Resolves a single extra file according to its category.
  Future<void> _resolveExtra(ExtraFile f) async {
    if (_extrasBusy) return;
    switch (f.kind) {
      case PlaylistExtraKind.incompleteDownload:
        setState(() => _extrasBusy = true);
        try {
          if (await _deleteExtraFile(f) && mounted) {
            Snack.show(context, context.l10n.deleted(f.fileName),
                level: SnackLevel.success);
          }
          await _compareToFolder(jumpToBestTab: false);
        } finally {
          if (mounted) setState(() => _extrasBusy = false);
        }
        break;
      case PlaylistExtraKind.wrongFormat:
        var target = _formatTargetFor(f.extension);
        if (target.isEmpty) {
          await _chooseExtrasTarget(context.l10n.chooseFolderFiles2(f.extension));
          target = _extrasTargetFolder ?? '';
        }
        await _moveExtrasToTarget([f], target, context.l10n.moved(f.fileName));
        break;
      case PlaylistExtraKind.notInPlaylist:
        if (_extrasTargetFolder == null ||
            _extrasTargetFolder!.trim().isEmpty) {
          await _chooseExtrasTarget(context.l10n.chooseFolderMoveExtraFiles);
        }
        await _moveExtrasToTarget(
            [f], _extrasTargetFolder?.trim() ?? '', context.l10n.moved(f.fileName));
        break;
    }
  }

  /// Short human label for a category's per-item action.
  String _extrasItemActionLabel(ExtraFile f) {
    return switch (f.kind) {
      PlaylistExtraKind.incompleteDownload => context.l10n.deleteFile4,
      PlaylistExtraKind.wrongFormat =>
        context.l10n.moveFileFormatFolder(f.extension),
      PlaylistExtraKind.notInPlaylist => context.l10n.moveTargetFolder,
    };
  }

  /// Short subtitle line for a category's per-item tile.
  String _extrasItemSubtitle(ExtraFile f) {
    return switch (f.kind) {
      PlaylistExtraKind.incompleteDownload =>
        context.l10n.incompleteDownload(f.extension),
      PlaylistExtraKind.wrongFormat =>
        context.l10n.differentFromFolderFormat(f.extension),
      PlaylistExtraKind.notInPlaylist => f.extension,
    };
  }

  // The content goes to the picker as bytes: Android and iOS refuse a save
  // dialog without them (it threw, so both exports did nothing on phones),
  // and on desktop the picker writes them to the chosen path itself.
  Future<void> _exportMissing() async {
    AdService.instance.registerInteraction();
    final missing = _comparison?.missing ?? const <SearchResult>[];
    if (missing.isEmpty) return;
    final text = widget.playlistService.buildTrackList(missing);
    await _saveExport(
      dialogTitle: context.l10n.exportMissingTracks,
      fileName: 'missing_tracks.txt',
      extension: 'txt',
      content: text,
      doneMessage: context.l10n.exportedTracks(missing.length),
    );
  }

  Future<void> _exportM3U() async {
    AdService.instance.registerInteraction();
    if (_tracks == null || _tracks!.isEmpty) return;
    final matched = _comparison?.matched ?? const <TrackMatch>[];
    final text = matched.isNotEmpty
        ? widget.playlistService.buildM3UFromMatches(matched)
        : widget.playlistService.buildM3U(_tracks!, format: _selectedFormat);
    final safeTitle = (_playlistInfo?.title ?? 'playlist')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    await _saveExport(
      dialogTitle: context.l10n.saveM3uPlaylist,
      fileName: '$safeTitle.m3u',
      extension: 'm3u',
      content: text,
      doneMessage: context.l10n.savedM3uPlaylist,
    );
  }

  Future<void> _saveExport({
    required String dialogTitle,
    required String fileName,
    required String extension,
    required String content,
    required String doneMessage,
  }) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        allowedExtensions: [extension],
        type: FileType.custom,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (result == null || !mounted) return;
      Snack.show(context, doneMessage, level: SnackLevel.success);
    } catch (e) {
      if (!mounted) return;
      Snack.show(context, context.l10n.couldNotSaveFile(e),
          level: SnackLevel.error);
    }
  }

  /// Where "Download missing" saves: the compared folder, so the tracks end
  /// up beside the rest of the playlist. On Android only a folder from the
  /// picker can be written to; the prefilled shared Downloads path is where
  /// downloads go anyway, so that one maps to the normal download folder.
  String? get _downloadFolderForMissing {
    final folder = _comparison?.folderPath.trim() ?? '';
    if (folder.isEmpty) return null;
    if (!kIsWeb && Platform.isAndroid && !folder.startsWith('content://')) {
      return null;
    }
    return folder;
  }

  void _downloadMissing(List<SearchResult> tracks) {
    if (tracks.isEmpty) return;
    widget.onDownloadMissing(tracks, _selectedFormat, _downloadFolderForMissing);
    Snack.show(
      context,
      tracks.length == 1
          ? context.l10n.downloading2(tracks.first.title)
          : context.l10n.downloadingTracks(tracks.length),
      level: SnackLevel.info,
    );
  }

  @override
  void dispose() {
    _appController?.removeListener(_onControllerChanged);
    _urlController.dispose();
    _folderController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // --─ Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: true,
      child: Column(
        children: [
          // -- Top bar: URL + folder inputs --------------------------------
          _buildInputSection(theme, cs),
          if (_loading) _buildLoadingBar(),
          if (_error != null) _buildErrorBar(),
          // -- Main content ------------------------------------------------
          if (_tracks != null) ...[
            _buildTabBar(cs),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(theme, cs),
                  _buildMatchedTab(theme),
                  _buildMissingTab(theme),
                  _buildExtrasTab(theme),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --─ Input Section --------------------------------------------------------

  Widget _buildInputSection(ThemeData theme, ColorScheme cs) {
    // Phones get the Compare button on its own row; beside a text field and
    // a browse button it squeezed the folder path down to a few letters.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final folder = _folderController.text.trim();
    // A folder from Android's picker is a content:// URI: show where it is
    // rather than the URI, and change it with the picker, not the keyboard.
    final pickedOnPhone = folder.startsWith('content://');

    final compareButton = FilledButton.tonalIcon(
      onPressed: _loading ? null : () => _compareToFolder(),
      icon: const Icon(Icons.compare_arrows, size: 20),
      label: Text(context.l10n.compare),
    );

    final Widget folderField = pickedOnPhone
        ? InputDecorator(
            decoration: InputDecoration(
              labelText: context.l10n.folderCompare,
              prefixIcon: const Icon(Icons.folder),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(
              friendlyFolderLabel(folder),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : TextField(
            controller: _folderController,
            decoration: InputDecoration(
              hintText: context.l10n.localMusicFolderPath,
              prefixIcon: const Icon(Icons.folder),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _compareToFolder(),
          );

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: context.l10n.youtubePlaylistUrl,
                      prefixIcon: const Icon(Icons.link),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _loadPlaylist(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _loadPlaylist,
                  icon: const Icon(Icons.playlist_play, size: 20),
                  label: Text(context.l10n.load),
                ),
              ],
            ),
            if (_tracks != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: folderField),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _loading ? null : _pickFolderAndCompare,
                    icon: const Icon(Icons.folder_open),
                    tooltip: pickedOnPhone ? context.l10n.changeFolder : context.l10n.browse2,
                  ),
                  if (!narrow) ...[
                    const SizedBox(width: 4),
                    compareButton,
                  ],
                ],
              ),
              if (narrow) ...[
                const SizedBox(height: 8),
                compareButton,
              ],
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(context.l10n.downloadFormat),
                  DropdownButton<String>(
                    value: _selectedFormat,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                      DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                      DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedFormat = v);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const LinearProgressIndicator(),
          if (_loadingMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(_loadingMessage!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_error!, style: const TextStyle(color: Colors.red))),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  // --─ Tab bar --------------------------------------------------------------

  Widget _buildTabBar(ColorScheme cs) {
    final matched = _comparison?.downloadedCount ?? 0;
    final missing = _comparison?.missingCount ?? 0;
    final extras = _comparison?.extraCount ?? 0;

    // Four labelled tabs with count badges do not fit a phone's width.
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return TabBar(
      controller: _tabController,
      isScrollable: narrow,
      tabAlignment: narrow ? TabAlignment.start : null,
      tabs: [
        Tab(text: context.l10n.overview),
        Tab(child: _tabLabel(context.l10n.matched, matched, Colors.green)),
        Tab(child: _tabLabel(context.l10n.missing, missing, Colors.orange)),
        Tab(child: _tabLabel(context.l10n.extras, extras, cs.primary)),
      ],
    );
  }

  Widget _tabLabel(String label, int count, Color badgeColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    color: badgeColor,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  // --─ Overview Tab --------------------------------------------------------─

  Widget _buildOverviewTab(ThemeData theme, ColorScheme cs) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        AdService.instance.registerInteraction();
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Playlist info card
          if (_playlistInfo != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.queue_music, size: 36),
                title: Text(_playlistInfo!.title,
                    style: theme.textTheme.titleMedium),
                subtitle: Text(
                  context.l10n.tracks(_playlistInfo!.author, _tracks!.length, _formatTotalDuration(_tracks!)),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'm3u') _exportM3U();
                    if (v == 'missing') _exportMissing();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'm3u', child: Text(context.l10n.exportM3u)),
                    if (_comparison != null && _comparison!.missing.isNotEmpty)
                      PopupMenuItem(
                          value: 'missing', child: Text(context.l10n.exportMissingList)),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ),
            ),

          if (_playlistDiagnostics != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Colors.amber.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_playlistDiagnostics!)),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Comparison summary
          if (_comparison != null) ...[
            if (_comparison!.filesScanned == 0) ...[
              _buildNoFilesFoundCard(theme),
              const SizedBox(height: 16),
            ],
            _buildSummaryCards(theme, cs),
            const SizedBox(height: 16),
            // Completion bar
            _buildCompletionBar(theme),
            const SizedBox(height: 16),
            // Uncertain matches warning
            if (_comparison!.uncertainMatches().isNotEmpty)
              Card(
                color: Colors.amber.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.l10n.tracksMatchedLowConfidenceReview(_comparison!.uncertainMatches().length),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _tabController.animateTo(1),
                        child: Text(context.l10n.review),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // Quick actions
            if (_comparison!.missing.isNotEmpty) ...[
              FilledButton.icon(
                onPressed: () => _downloadMissing(_comparison!.missing),
                icon: const Icon(Icons.download),
                label: Text(
                    context.l10n.downloadAllMissingTracks(_comparison!.missingCount)),
              ),
              const SizedBox(height: 6),
              Text(
                _downloadFolderForMissing == null
                    ? context.l10n.theyGoDownloadFolder
                    : context.l10n.theyGoIntoNextRest(friendlyFolderLabel(_downloadFolderForMissing!)),
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ] else ...[
            // No comparison yet - show track list
            const SizedBox(height: 8),
            Text(
                _folderController.text.trim().isEmpty
                    ? context.l10n.tracksLoadedChooseFolderAbove(_tracks!.length)
                    : context.l10n.tracksLoadedPressCompareSee(_tracks!.length),
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 12),
            ...List.generate(
              _tracks!.length,
              (i) {
                final t = _tracks![i];
                return ListTile(
                  dense: true,
                  leading: Text('${i + 1}', style: theme.textTheme.bodySmall),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.artist),
                  trailing: Text(_formatDuration(t.duration),
                      style: theme.textTheme.bodySmall),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ThemeData theme, ColorScheme cs) {
    final c = _comparison!;
    return Row(
      children: [
        _summaryCard(
            context.l10n.total, '${c.total}', Icons.queue_music, cs.primary, theme),
        _summaryCard(context.l10n.matched, '${c.downloadedCount}', Icons.check_circle,
            Colors.green, theme),
        _summaryCard(
            context.l10n.missing, '${c.missingCount}', Icons.cancel, Colors.orange, theme),
        _summaryCard(context.l10n.extras, '${c.extraCount}', Icons.library_music,
            cs.primary, theme),
      ],
    );
  }

  Widget _summaryCard(
      String label, String value, IconData icon, Color color, ThemeData theme) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 4),
              Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold, color: color)),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionBar(ThemeData theme) {
    final c = _comparison!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.completion, style: theme.textTheme.titleSmall),
                Text('${c.completionPercentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: c.completionPercentage / 100,
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  c.completionPercentage >= 100
                      ? Colors.green
                      : c.completionPercentage >= 50
                          ? Colors.teal
                          : Colors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --─ Matched Tab ----------------------------------------------------------

  Widget _buildMatchedTab(ThemeData theme) {
    if (_comparison == null) {
      return _buildRunCompareHint(theme);
    }

    var matches = List<TrackMatch>.from(_comparison!.matched);

    // Filter by confidence
    if (_confidenceFilter > 0) {
      matches =
          matches.where((m) => m.confidence >= _confidenceFilter).toList();
    }

    // Sort
    switch (_sortMode) {
      case _SortMode.confidence:
        matches.sort((a, b) => a.confidence.compareTo(b.confidence));
      case _SortMode.title:
        matches.sort((a, b) =>
            a.track.title.toLowerCase().compareTo(b.track.title.toLowerCase()));
      case _SortMode.original:
        break; // keep playlist order
    }

    return Column(
      children: [
        // Toolbar. A Wrap, not a Row: the chips and the sort menu are wider
        // than a phone and used to overflow off the right edge.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              // Confidence filter chips
              Text(context.l10n.minConfidence),
              ...[0.0, 0.55, 0.70, 0.85].map((v) => ChoiceChip(
                    label: Text(v == 0 ? context.l10n.playerAll : '${(v * 100).toInt()}%'),
                    selected: _confidenceFilter == v,
                    onSelected: (_) => setState(() => _confidenceFilter = v),
                    visualDensity: VisualDensity.compact,
                  )),
              const SizedBox(width: 8),
              // Sort dropdown
              DropdownButton<_SortMode>(
                value: _sortMode,
                underline: const SizedBox(),
                isDense: true,
                items: [
                  DropdownMenuItem(
                      value: _SortMode.original, child: Text(context.l10n.playlistOrder)),
                  DropdownMenuItem(
                      value: _SortMode.title, child: Text(context.l10n.titleZ)),
                  DropdownMenuItem(
                      value: _SortMode.confidence, child: Text(context.l10n.confidence)),
                ],
                onChanged: (v) =>
                    setState(() => _sortMode = v ?? _SortMode.original),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: matches.isEmpty
              ? Center(child: Text(context.l10n.noMatchesConfidenceLevel))
              : NotificationListener<ScrollEndNotification>(
                  onNotification: (_) {
                    AdService.instance.registerInteraction();
                    return false;
                  },
                  child: ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final m = matches[i];
                      return _MatchedTile(match: m);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // --─ Missing Tab ----------------------------------------------------------

  Widget _buildMissingTab(ThemeData theme) {
    if (_comparison == null) {
      return _buildRunCompareHint(theme);
    }
    if (_comparison!.missing.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text(context.l10n.allPlaylistTracksFolder,
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Action bar (selection + download). Wraps on phones, where three
        // buttons side by side ran off the screen.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: _missingSelection.isEmpty
                    ? null
                    : () => _downloadMissing(_missingSelection.toList()),
                icon: const Icon(Icons.download, size: 18),
                label: Text(
                    context.l10n.downloadSelected(_missingSelection.length, _comparison!.missingCount)),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    if (_missingSelection.length == _comparison!.missingCount) {
                      _missingSelection.clear();
                    } else {
                      _missingSelection = _comparison!.missing.toSet();
                    }
                  });
                },
                icon: const Icon(Icons.check_box, size: 18),
                label: Text(
                    _missingSelection.length == _comparison!.missingCount
                        ? context.l10n.clearSelection2
                        : context.l10n.selectAll),
              ),
              OutlinedButton.icon(
                onPressed: _exportMissing,
                icon: const Icon(Icons.save_alt, size: 18),
                label: Text(context.l10n.exportList),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              AdService.instance.registerInteraction();
              return false;
            },
            child: ListView.builder(
              itemCount: _comparison!.missing.length,
              itemBuilder: (context, i) {
                final t = _comparison!.missing[i];
                final selected = _missingSelection.contains(t);
                return ListTile(
                  dense: true,
                  onLongPress: () {
                    setState(() {
                      _lastMissingSelectedIndex = i;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                        context.l10n.rangeSelectStartedTapAnother,
                      ),
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  // The whole row toggles, not just the small checkbox, which
                  // was hard to hit with a thumb.
                  onTap: () => _setMissingSelected(i, !selected),
                  leading: Checkbox(
                    value: selected,
                    onChanged: (value) {
                      if (value != null) _setMissingSelected(i, value);
                    },
                  ),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text('${t.artist}  •  ${_formatDuration(t.duration)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.download, size: 20),
                    tooltip: context.l10n.downloadTrack,
                    onPressed: () => _downloadMissing([t]),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Selects or clears Missing row [i]. After a long-press, the next row
  /// selects everything in between (shift-click style).
  void _setMissingSelected(int i, bool value) {
    final missing = _comparison?.missing;
    if (missing == null || i < 0 || i >= missing.length) return;
    setState(() {
      final anchor = _lastMissingSelectedIndex;
      if (anchor != null && anchor != i && anchor < missing.length) {
        final lo = anchor < i ? anchor : i;
        final hi = anchor < i ? i : anchor;
        for (var idx = lo; idx <= hi; idx++) {
          if (value) {
            _missingSelection.add(missing[idx]);
          } else {
            _missingSelection.remove(missing[idx]);
          }
        }
        _lastMissingSelectedIndex = null;
      } else {
        if (value) {
          _missingSelection.add(missing[i]);
        } else {
          _missingSelection.remove(missing[i]);
        }
        _lastMissingSelectedIndex = i;
      }
    });
  }

  /// Shown when the folder held no music at all, which almost always means
  /// the wrong folder, or one the app can no longer read.
  Widget _buildNoFilesFoundCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_off_outlined,
                    color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.l10n.noMusicFiles(friendlyFolderLabel(_comparison!.folderPath)),
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.whyEveryTrackShowsMissing,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: _loading ? null : _pickFolderAndCompare,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(context.l10n.chooseAnotherFolder),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --─ Extras Tab ----------------------------------------------------------─

  Widget _buildRunCompareHint(ThemeData theme) {
    final folder = _folderController.text.trim();
    final hasTracks = _tracks != null && _tracks!.isNotEmpty;
    final canCompare = hasTracks && folder.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(context.l10n.runComparisonFirst, style: theme.textTheme.titleMedium),
          if (folder.isNotEmpty)
            Text(context.l10n.folder2(friendlyFolderLabel(folder)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          if (canCompare) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : () => _compareToFolder(),
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: Text(context.l10n.compareNow),
            ),
          ] else if (hasTracks) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _pickFolderAndCompare,
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(context.l10n.chooseFolder2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExtrasTab(ThemeData theme) {
    if (_comparison == null) {
      return _buildRunCompareHint(theme);
    }
    final incomplete = _extrasOfKind(PlaylistExtraKind.incompleteDownload);
    final wrongFormat = _extrasOfKind(PlaylistExtraKind.wrongFormat);
    final notInPlaylist = _extrasOfKind(PlaylistExtraKind.notInPlaylist);
    if (incomplete.isEmpty && wrongFormat.isEmpty && notInPlaylist.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(context.l10n.noExtraFilesFolderMatches,
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildExtrasSection(
          theme,
          title: context.l10n.incompleteDownloads,
          subtitle: context.l10n.partiallyDownloadedTempArtifactsSafe,
          icon: Icons.warning_amber,
          color: Colors.orange,
          files: incomplete,
          actionIcon: Icons.delete_outline,
          onItemAction: _resolveExtra,
          resolveAllLabel: context.l10n.deleteAll,
          onResolveAll: _autoResolveIncomplete,
        ),
        const SizedBox(height: 8),
        _buildExtrasSection(
          theme,
          title: context.l10n.wrongFormat,
          subtitle:
              context.l10n.filesWhoseFormatDiffersFrom,
          icon: Icons.audio_file,
          color: Colors.amber,
          files: wrongFormat,
          actionIcon: Icons.insert_drive_file,
          onItemAction: _resolveExtra,
          resolveAllLabel: context.l10n.moveAll,
          onResolveAll: _autoResolveWrongFormat,
        ),
        const SizedBox(height: 8),
        _buildExtrasSection(
          theme,
          title: context.l10n.notPlaylist,
          subtitle: context.l10n.rightFormatFilesNoPlaylist,
          icon: Icons.library_music,
          color: theme.colorScheme.primary,
          files: notInPlaylist,
          actionIcon: Icons.insert_drive_file,
          onItemAction: _resolveExtra,
          resolveAllLabel: context.l10n.moveAll,
          onResolveAll: _autoResolveNotInPlaylist,
        ),
      ],
    );
  }

  static const int _extrasMaxShownPerSection = 120;

  Widget _buildExtrasSection(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<ExtraFile> files,
    required IconData actionIcon,
    required void Function(ExtraFile) onItemAction,
    required String resolveAllLabel,
    required VoidCallback onResolveAll,
  }) {
    final shown = files.take(_extrasMaxShownPerSection).toList();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            // On a phone the resolve button goes under the heading; beside
            // it, the title and its count ran off the edge of the card.
            child: LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 480;
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${files.length}',
                            style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey)),
                ],
              );
              final resolveAll = files.isEmpty
                  ? null
                  : FilledButton.tonalIcon(
                      onPressed: _extrasBusy ? null : onResolveAll,
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: Text(resolveAllLabel),
                    );
              final headingRow = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: heading),
                  if (!narrow && resolveAll != null) ...[
                    const SizedBox(width: 8),
                    resolveAll,
                  ],
                ],
              );
              if (!narrow || resolveAll == null) return headingRow;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  headingRow,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: resolveAll,
                  ),
                ],
              );
            }),
          ),
          ...shown.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: ListTile(
                  dense: true,
                  leading: Icon(icon, color: color, size: 18),
                  title: Text(f.fileName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${_extrasItemSubtitle(f)}  •  ${f.filePath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey)),
                  trailing: IconButton(
                    icon: Icon(actionIcon, size: 18),
                    tooltip: _extrasItemActionLabel(f),
                    onPressed: () {
                      if (!_extrasBusy) onItemAction(f);
                    },
                  ),
                ),
              )),
          if (files.length > shown.length)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(context.l10n.more2(files.length - shown.length),
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  // --─ Helpers --------------------------------------------------------------

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  String _formatTotalDuration(List<SearchResult> tracks) {
    final total =
        tracks.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);
    if (total.inHours > 0) {
      return '${total.inHours}h ${total.inMinutes.remainder(60)}m';
    }
    return '${total.inMinutes}m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════════════

enum _SortMode { original, title, confidence }

/// A tile showing a matched track alongside its local file and confidence.
class _MatchedTile extends StatelessWidget {
  final TrackMatch match;

  const _MatchedTile({required this.match});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confColor = match.confidence >= 0.85
        ? Colors.green
        : match.confidence >= 0.65
            ? Colors.orange
            : Colors.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Confidence badge
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: confColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Text('${(match.confidence * 100).toInt()}%',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: confColor)),
                  Text(match.confidenceLabel,
                      style: TextStyle(fontSize: 9, color: confColor)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Track / file info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(match.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 13, color: Colors.grey),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(match.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.insert_drive_file,
                          size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(match.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Match method chip
            Chip(
              label: Text(_methodLabel(context, match.method),
                  style: const TextStyle(fontSize: 10)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  String _methodLabel(BuildContext context, MatchMethod m) {
    return switch (m) {
      MatchMethod.exact => context.l10n.exact,
      MatchMethod.contains => context.l10n.contains,
      MatchMethod.artistTitle => context.l10n.artistTitle,
      MatchMethod.tokenOverlap => context.l10n.tokens,
      MatchMethod.fuzzy => context.l10n.fuzzy,
    };
  }
}
