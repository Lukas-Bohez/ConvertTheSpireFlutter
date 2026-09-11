import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/search_result.dart';
import '../services/ad_service.dart';
import '../services/android_saf.dart';
import '../services/media_organizer.dart';
import '../services/platform_dirs.dart';
import '../services/playlist_service.dart';
import '../state/app_controller.dart';
import '../utils/snack.dart';
import '../widgets/tv_file_browser.dart';

/// Screen for loading a playlist, cross-referencing it against a local folder,
/// and taking action on missing / matched / extra tracks.
class PlaylistScreen extends StatefulWidget {
  final PlaylistService playlistService;
  final void Function(List<SearchResult> tracks, String format)
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _processPendingRequest(pending));
    }
  }

  void _onPendingRequest() {
    final pending = widget.pendingRequest?.value;
    if (pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _processPendingRequest(pending));
  }

  Future<void> _processPendingRequest(PendingPlaylistRequest request) async {
    // Clear the pending request immediately so re-pasting the URL works
    widget.pendingRequest?.value = null;

    _urlController.text = request.url;
    await _loadPlaylist();
    _folderController.text = request.folder;
    await _compareToFolder();
  }

  // --â”€ Actions --------------------------------------------------------------

  Future<void> _loadPlaylist() async {
    AdService.instance.registerInteraction();
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _loadingMessage = 'Fetching playlistâ€¦';
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

  Future<void> _pickFolder() async {
    AdService.instance.registerInteraction();
    final result = await pickDirectoryPath(
      context,
      dialogTitle: 'Select music folder to compare',
    );
    if (result != null) {
      _folderController.text = result;
    }
  }

  Future<void> _compareToFolder({bool jumpToBestTab = true}) async {
    AdService.instance.registerInteraction();
    if (_tracks == null || _tracks!.isEmpty) return;
    final folder = _folderController.text.trim();
    if (folder.isEmpty) return;

    setState(() {
      _loading = true;
      _loadingMessage = 'Scanning folder & matchingâ€¦';
    });

    try {
      final comparison = await widget.playlistService.compareToFolder(
        _tracks!,
        folder,
      );
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
// --â”€ Extras auto-resolve -------------------------------------------------

  AppSettings? get _extrasSettings {
    // Best-effort read: if the action runs outside a build pass (e.g. an
    // async resolve triggered by a button), degrade to null and let the
    // caller prompt for a folder instead of failing the whole operation.
    try {
      return context.read<AppController>()?.settings;
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
      debugPrint('[Extras] SAFEGUARD: destination file is empty for ${f.fileName}');
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
      _comparison?.extras
          ?.where((e) => e.kind == kind)
          ?.toList() ??
      const <ExtraFile>[];

  /// Resolves the configured destination folder for a file extension:
  /// per-format folder from settings when set, else the default download dir.
  String _formatTargetFor(String extension) {
    final settings = _extrasSettings;
    final fallback = settings?.downloadDir?.trim() ?? '';
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
      final staging = Directory(p.join(
          cacheDir.path, 'extras_move_${DateTime.now().millisecondsSinceEpoch}'));
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
          Snack.show(context, 'No files could be moved',
              level: SnackLevel.error);
        }
        return;
      }

      final result = await MediaOrganizer.moveAndDeduplicate(
          [staging.path], targetFolder);
      final moved = result['moved'] ?? 0;
      final deleted = result['deleted'] ?? 0;
      debugPrint('[Extras] moveAndDeduplicate result: $result');

      // True move semantics: remove the originals that were copied over.
      // SAFETY: only delete an original after positively verifying it exists
      // at the new destination. If moveAndDeduplicate moved nothing
      // (e.g. unwritable target), all originals are kept untouched â€” a
      // "resolve" action must never destroy a file that was never moved.
      var removed = 0;
      if (moved == 0) {
        debugPrint('[Extras] SAFEGUARD: 0 files moved to destination; '
            'keeping ${files.length} originals');
      } else {
        for (final f in files) {
          if (!mounted) break;
          if (_destinationVerified(f, targetFolder)) {
            if (await _deleteExtraFile(f)) removed++;
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
        Snack.show(context,
            '$label: moved $moved files, deleted $deleted duplicates',
            level: moved > 0 ? SnackLevel.success : SnackLevel.info);
      }
      await _compareToFolder(jumpToBestTab: false);
    } catch (e) {
      debugPrint('[Extras] Auto-resolve failed: $e');
      if (mounted) {
        Snack.show(context, 'Auto-resolve failed: $e', level: SnackLevel.error);
      }
    } finally {
      if (mounted) setState(() => _extrasBusy = false);
    }
  }

  /// Prompts for a target folder and stores it for reuse.
  Future<void> _chooseExtrasTarget(String dialogTitle) async {
    final result =
        await pickDirectoryPath(context, dialogTitle: dialogTitle);
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
        Snack.show(context, 'Deleted $removed incomplete download files',
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
        await _chooseExtrasTarget('Choose a folder for ${entry.key} files');
        target = _extrasTargetFolder ?? '';
      }
      await _moveExtrasToTarget(
          entry.value, target, 'Moved ${entry.value.length} ${entry.key} files');
    }
  }

  /// Move files that are the right format but not in the playlist to the
  /// user-chosen folder (prompted once, reused for subsequent resolves).
  Future<void> _autoResolveNotInPlaylist() async {
    final extras = _extrasOfKind(PlaylistExtraKind.notInPlaylist);
    if (extras.isEmpty || _extrasBusy) return;

    if (_extrasTargetFolder == null || _extrasTargetFolder!.trim().isEmpty) {
      await _chooseExtrasTarget('Choose folder to move extra files into');
    }
    await _moveExtrasToTarget(extras, _extrasTargetFolder?.trim() ?? '',
        'Moved ${extras.length} files not in playlist');
  }

  /// Resolves a single extra file according to its category.
  Future<void> _resolveExtra(ExtraFile f) async {
    if (_extrasBusy) return;
    switch (f.kind) {
      case PlaylistExtraKind.incompleteDownload:
        setState(() => _extrasBusy = true);
        try {
          if (await _deleteExtraFile(f) && mounted) {
            Snack.show(context, 'Deleted ${f.fileName}',
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
          await _chooseExtrasTarget('Choose a folder for ${f.extension} files');
          target = _extrasTargetFolder ?? '';
        }
        await _moveExtrasToTarget([f], target, 'Moved ${f.fileName}');
        break;
      case PlaylistExtraKind.notInPlaylist:
        if (_extrasTargetFolder == null || _extrasTargetFolder!.trim().isEmpty) {
          await _chooseExtrasTarget('Choose folder to move extra files into');
        }
        await _moveExtrasToTarget([f], _extrasTargetFolder?.trim() ?? '',
            'Moved ${f.fileName}');
        break;
    }
  }

  /// Short human label for a category's per-item action.
  String _extrasItemActionLabel(ExtraFile f) {
    return switch (f.kind) {
      PlaylistExtraKind.incompleteDownload => 'Delete this file',
      PlaylistExtraKind.wrongFormat =>
        'Move ${f.extension} file to format folder',
      PlaylistExtraKind.notInPlaylist => 'Move to target folder',
    };
  }

  /// Short subtitle line for a category's per-item tile.
  String _extrasItemSubtitle(ExtraFile f) {
    return switch (f.kind) {
      PlaylistExtraKind.incompleteDownload =>
        'Incomplete download  â€¢  ${f.extension}',
      PlaylistExtraKind.wrongFormat =>
        '${f.extension}  â€¢  different from folder format',
      PlaylistExtraKind.notInPlaylist => f.extension,
    };
  }

  Future<void> _exportMissing() async {
    AdService.instance.registerInteraction();
    if (_comparison == null || _comparison!.missing.isEmpty) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export missing tracks',
      fileName: 'missing_tracks.txt',
      allowedExtensions: ['txt'],
      type: FileType.custom,
    );
    if (result != null) {
      await widget.playlistService
          .exportTrackList(_comparison!.missing, result);
      if (mounted) {
        Snack.show(context,
            'Exported ${_comparison!.missing.length} tracks to $result',
            level: SnackLevel.success);
      }
    }
  }

  Future<void> _exportM3U() async {
    AdService.instance.registerInteraction();
    if (_tracks == null || _tracks!.isEmpty) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save M3U playlist',
      fileName: '${_playlistInfo?.title ?? 'playlist'}.m3u',
      allowedExtensions: ['m3u'],
      type: FileType.custom,
    );
    if (result != null) {
      if (_comparison != null && _comparison!.matched.isNotEmpty) {
        await widget.playlistService
            .generateM3UFromMatches(_comparison!.matched, result);
      } else {
        await widget.playlistService
            .generateM3U(_tracks!, result, format: _selectedFormat);
      }
      if (mounted) {
        Snack.show(context, 'Saved M3U to $result', level: SnackLevel.success);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _folderController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // --â”€ Build ----------------------------------------------------------------

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

  // --â”€ Input Section --------------------------------------------------------

  Widget _buildInputSection(ThemeData theme, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'YouTube playlist URL',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _loadPlaylist(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _loadPlaylist,
                  icon: const Icon(Icons.playlist_play, size: 20),
                  label: const Text('Load'),
                ),
              ],
            ),
            if (_tracks != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _folderController,
                      decoration: const InputDecoration(
                        hintText: 'Local music folder path',
                        prefixIcon: Icon(Icons.folder),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _compareToFolder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _pickFolder,
                    icon: const Icon(Icons.folder_open),
                    tooltip: 'Browseâ€¦',
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _compareToFolder,
                    icon: const Icon(Icons.compare_arrows, size: 20),
                    label: const Text('Compare'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Download format: '),
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

  // --â”€ Tab bar --------------------------------------------------------------

  Widget _buildTabBar(ColorScheme cs) {
    final matched = _comparison?.downloadedCount ?? 0;
    final missing = _comparison?.missingCount ?? 0;
    final extras = _comparison?.extraCount ?? 0;

    return TabBar(
      controller: _tabController,
      tabs: [
        const Tab(text: 'Overview'),
        Tab(child: _tabLabel('Matched', matched, Colors.green)),
        Tab(child: _tabLabel('Missing', missing, Colors.orange)),
        Tab(child: _tabLabel('Extras', extras, Colors.blue)),
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

  // --â”€ Overview Tab --------------------------------------------------------â”€

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
                  '${_playlistInfo!.author}  â€¢  ${_tracks!.length} tracks  â€¢  '
                  '${_formatTotalDuration(_tracks!)}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'm3u') _exportM3U();
                    if (v == 'missing') _exportMissing();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'm3u', child: Text('Export as M3U')),
                    if (_comparison != null && _comparison!.missing.isNotEmpty)
                      const PopupMenuItem(
                          value: 'missing', child: Text('Export missing list')),
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
                          '${_comparison!.uncertainMatches().length} tracks matched with '
                          'low confidence - review them in the Matched tab.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _tabController.animateTo(1),
                        child: const Text('Review'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // Quick actions
            if (_comparison!.missing.isNotEmpty)
              FilledButton.icon(
                onPressed: () => widget.onDownloadMissing(
                    _comparison!.missing, _selectedFormat),
                icon: const Icon(Icons.download),
                label: Text(
                    'Download All ${_comparison!.missingCount} Missing Tracks'),
              ),
          ] else ...[
            // No comparison yet - show track list
            const SizedBox(height: 8),
            Text(
                '${_tracks!.length} tracks loaded. Select a folder above to compare.',
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
            'Total', '${c.total}', Icons.queue_music, cs.primary, theme),
        _summaryCard('Matched', '${c.downloadedCount}', Icons.check_circle,
            Colors.green, theme),
        _summaryCard(
            'Missing', '${c.missingCount}', Icons.cancel, Colors.orange, theme),
        _summaryCard('Extras', '${c.extraCount}', Icons.library_music,
            Colors.blue, theme),
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
                Text('Completion', style: theme.textTheme.titleSmall),
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

  // --â”€ Matched Tab ----------------------------------------------------------

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
        // Toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              // Confidence filter chips
              const Text('Min confidence: '),
              ...[0.0, 0.55, 0.70, 0.85].map((v) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(v == 0 ? 'All' : '${(v * 100).toInt()}%'),
                      selected: _confidenceFilter == v,
                      onSelected: (_) => setState(() => _confidenceFilter = v),
                      visualDensity: VisualDensity.compact,
                    ),
                  )),
              const Spacer(),
              // Sort dropdown
              DropdownButton<_SortMode>(
                value: _sortMode,
                underline: const SizedBox(),
                isDense: true,
                items: const [
                  DropdownMenuItem(
                      value: _SortMode.original, child: Text('Playlist order')),
                  DropdownMenuItem(
                      value: _SortMode.title, child: Text('Title A-Z')),
                  DropdownMenuItem(
                      value: _SortMode.confidence, child: Text('Confidence â†‘')),
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
              ? const Center(child: Text('No matches at this confidence level'))
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

  // --â”€ Missing Tab ----------------------------------------------------------

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
            Text('All playlist tracks are in the folder!',
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Action bar (selection + download)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _missingSelection.isEmpty
                    ? null
                    : () => widget.onDownloadMissing(
                          _missingSelection.toList(),
                          _selectedFormat,
                        ),
                icon: const Icon(Icons.download, size: 18),
                label: Text(
                    'Download Selected (${_missingSelection.length}/${_comparison!.missingCount})'),
              ),
              const SizedBox(width: 8),
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
                        ? 'Clear Selection'
                        : 'Select All'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _exportMissing,
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('Export List'),
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                        'Range select started. Tap another item to select a range.',
                      ),
                      duration: Duration(seconds: 2),
                    ));
                  },
                  leading: Checkbox(
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == null) return;

                        // Range selection (shift-click style): long-press to set a
                        // starting point, then tap another item to select the range.
                        if (_lastMissingSelectedIndex != null &&
                            _lastMissingSelectedIndex != i) {
                          final start = _lastMissingSelectedIndex!;
                          final end = i;
                          final range = start < end
                              ? List.generate(end - start + 1, (j) => start + j)
                              : List.generate(start - end + 1, (j) => end + j);
                          for (final idx in range) {
                            final item = _comparison!.missing[idx];
                            if (value) {
                              _missingSelection.add(item);
                            } else {
                              _missingSelection.remove(item);
                            }
                          }
                          _lastMissingSelectedIndex = null;
                        } else {
                          if (value) {
                            _missingSelection.add(t);
                          } else {
                            _missingSelection.remove(t);
                          }
                          _lastMissingSelectedIndex = i;
                        }
                      });
                    },
                  ),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text('${t.artist}  â€¢  ${_formatDuration(t.duration)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.download, size: 20),
                    tooltip: 'Download this track',
                    onPressed: () =>
                        widget.onDownloadMissing([t], _selectedFormat),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // --â”€ Extras Tab ----------------------------------------------------------â”€

  Widget _buildRunCompareHint(ThemeData theme) {
    final folder = _folderController.text.trim();
    final canCompare =
        _tracks != null && _tracks!.isNotEmpty && folder.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('Run a comparison first',
              style: theme.textTheme.titleMedium),
          if (folder.isNotEmpty)
            Text('Folder: $folder',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          if (canCompare) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _compareToFolder,
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: const Text('Compare Now'),
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
            Text('No extra files - folder matches the playlist perfectly',
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
          title: 'Incomplete downloads',
          subtitle: "Partially-downloaded temp artifacts - safe to delete",
          icon: Icons.warning_amber,
          color: Colors.orange,
          files: incomplete,
          actionIcon: Icons.delete_outline,
          onItemAction: _resolveExtra,
          resolveAllLabel: 'Delete all',
          onResolveAll: _autoResolveIncomplete,
        ),
        const SizedBox(height: 8),
        _buildExtrasSection(
          theme,
          title: 'Wrong format',
          subtitle:
              "Files whose format differs from the folder's dominant format",
          icon: Icons.audio_file,
          color: Colors.amber,
          files: wrongFormat,
          actionIcon: Icons.insert_drive_file,
          onItemAction: _resolveExtra,
          resolveAllLabel: 'Move all',
          onResolveAll: _autoResolveWrongFormat,
        ),
        const SizedBox(height: 8),
        _buildExtrasSection(
          theme,
          title: 'Not in playlist',
          subtitle: 'Right-format files that no playlist track matches',
          icon: Icons.library_music,
          color: Colors.blue,
          files: notInPlaylist,
          actionIcon: Icons.insert_drive_file,
          onItemAction: _resolveExtra,
          resolveAllLabel: 'Move all',
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
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: theme.textTheme.titleSmall),
                          const SizedBox(width: 6),
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
                  ),
                ),
                const SizedBox(width: 8),
                if (files.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: _extrasBusy ? null : onResolveAll,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: Text(resolveAllLabel),
                  ),
              ],
            ),
          ),
          ...shown.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: ListTile(
                  dense: true,
                  leading: Icon(icon, color: color, size: 18),
                  title: Text(f.fileName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${_extrasItemSubtitle(f)}  â€¢  ${f.filePath}',
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
              child: Text('â€¦and ${files.length - shown.length} more',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  // --â”€ Helpers --------------------------------------------------------------

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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Helper widgets
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
              label: Text(_methodLabel(match.method),
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

  String _methodLabel(MatchMethod m) {
    return switch (m) {
      MatchMethod.exact => 'Exact',
      MatchMethod.contains => 'Contains',
      MatchMethod.artistTitle => 'Artist+Title',
      MatchMethod.tokenOverlap => 'Tokens',
      MatchMethod.fuzzy => 'Fuzzy',
    };
  }
}
