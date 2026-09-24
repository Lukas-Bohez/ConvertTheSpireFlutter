import 'dart:async';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/utils/l10n.dart';
import 'package:convert_the_spire_reborn/src/vault/models/torrent.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/drag_drop.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/create_torrent_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrent_detail_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:convert_the_spire_reborn/src/vault/vault_bootstrap.dart';
import 'package:convert_the_spire_reborn/src/widgets/empty_state.dart';
import 'package:convert_the_spire_reborn/src/widgets/tv_file_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum _SortMode {
  dateAdded,
  nameAZ,
  nameZA,
  sizeAsc,
  sizeDesc,
  progress,
  status,
}

extension _SortLabel on _SortMode {
  String label(BuildContext context) {
    switch (this) {
      case _SortMode.dateAdded:
        return context.l10n.dateAdded;
      case _SortMode.nameAZ:
        return context.l10n.nameZ;
      case _SortMode.nameZA:
        return context.l10n.nameZ2;
      case _SortMode.sizeAsc:
        return context.l10n.sizeSmallest;
      case _SortMode.sizeDesc:
        return context.l10n.sizeLargest;
      case _SortMode.progress:
        return context.l10n.progress;
      case _SortMode.status:
        return context.l10n.status;
    }
  }

  IconData get icon {
    switch (this) {
      case _SortMode.dateAdded:
        return Icons.calendar_today_outlined;
      case _SortMode.nameAZ:
        return Icons.sort_by_alpha;
      case _SortMode.nameZA:
        return Icons.sort_by_alpha;
      case _SortMode.sizeAsc:
        return Icons.data_usage_outlined;
      case _SortMode.sizeDesc:
        return Icons.data_usage;
      case _SortMode.progress:
        return Icons.download_outlined;
      case _SortMode.status:
        return Icons.circle_outlined;
    }
  }
}

class TorrentsScreen extends StatefulWidget {
  final VoidCallback? onOpenSettingsTab;

  const TorrentsScreen({super.key, this.onOpenSettingsTab});

  @override
  State<TorrentsScreen> createState() => _TorrentsScreenState();
}

class _TorrentsScreenState extends State<TorrentsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;
  _SortMode _sortMode = _SortMode.dateAdded;
  bool _fabExpanded = false;
  bool _pickerBusy = false;
  Timer? _searchDebounce;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim());
    });
  }

  String? _androidDocumentsUriForPath(String directoryPath) {
    final normalized = directoryPath.replaceAll('\\', '/');
    const prefixes = <String>['/storage/emulated/0/', '/sdcard/'];
    for (final prefix in prefixes) {
      if (normalized.startsWith(prefix)) {
        final relative = normalized.substring(prefix.length);
        final encodedDocId = Uri.encodeComponent('primary:$relative');
        return 'content://com.android.externalstorage.documents/document/$encodedDocId';
      }
    }
    return null;
  }

  Future<bool> _tryOpenFolderOnAndroid(String directoryPath) async {
    final docUri = _androidDocumentsUriForPath(directoryPath);
    if (docUri != null) {
      try {
        if (await launchUrl(
          Uri.parse(docUri),
          mode: LaunchMode.externalApplication,
        )) {
          return true;
        }
      } catch (_) {}
    }

    try {
      if (await launchUrl(
        Uri.file(directoryPath),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  _SortMode _sortModeFromSettings(int value) {
    if (value < 0 || value >= _SortMode.values.length) {
      return _SortMode.dateAdded;
    }
    return _SortMode.values[value];
  }

  Future<void> _loadSortMode() async {
    await SettingsService.instance.load();
    if (!mounted) return;
    setState(() {
      _sortMode = _sortModeFromSettings(
        SettingsService.instance.torrentSortMode,
      );
    });
  }

  Future<void> _setSortMode(_SortMode mode) async {
    setState(() => _sortMode = mode);
    await SettingsService.instance.setTorrentSortMode(mode.index);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSortMode());
    // Gate the first DB access on vault bootstrap completing so the torrents
    // list and the app-startup chain never race an open against the same DB
    // file (low-end PCs hit this as an instant crash entering Torrents).
    unawaited(_initTorrents());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDownloadFolderOnInit();
    });
  }

  Future<void> _initTorrents() async {
    try {
      await VaultBootstrap.ensureInitialized();
      if (!mounted) return;
      await TorrentService.instance.refreshTorrentStates();
    } catch (e) {
      debugPrint('TorrentsScreen: initial load failed: $e');
    }
  }

  Future<void> _checkDownloadFolderOnInit() async {
    final folder = SettingsService.instance.downloadDestination.trim();
    if (folder.isEmpty) {
      if (!mounted) return;
      _showSetDownloadFolderDialog();
    }
  }

  Future<bool> _validateDownloadFolder() async {
    final folder = SettingsService.instance.downloadDestination.trim();
    if (folder.isEmpty) {
      if (mounted) {
        _showSetDownloadFolderDialog();
      }
      return false;
    }

    // Check if folder exists and is accessible
    try {
      final dir = Directory(folder);
      if (!dir.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.downloadFolderNoLongerExists(folder)),
              action: SnackBarAction(
                label: context.l10n.change,
                onPressed: _showSetDownloadFolderDialog,
              ),
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cannotAccessDownloadFolder(e)),
            action: SnackBarAction(
              label: context.l10n.change,
              onPressed: _showSetDownloadFolderDialog,
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return false;
    }
  }

  void _showSetDownloadFolderDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.setDownloadFolder2),
        // overflow-fix: keep long settings guidance readable in constrained dialogs.
        content: SingleChildScrollView(
          child: Text(
            context.l10n.mustSetDownloadFolderBefore,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onOpenSettingsTab?.call();
            },
            child: Text(context.l10n.openSettings),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtSpeed(double bps) {
    if (bps < 1024) return '${bps.round()} B/s';
    if (bps < 1024 * 1024) return context.l10n.kbS((bps / 1024).toStringAsFixed(1));
    return context.l10n.mbS((bps / (1024 * 1024)).toStringAsFixed(1));
  }

  String _fmtEta(double seconds) {
    final etaSec = seconds.round();
    if (etaSec < 60) return '${etaSec}s';
    if (etaSec < 3600) return '${(etaSec / 60).round()}m';
    return '${(etaSec / 3600).toStringAsFixed(1)}h';
  }

  Color _stateColor(BuildContext ctx, String state, String statusLabel) {
    final cs = Theme.of(ctx).colorScheme;
    final label = statusLabel.toLowerCase();
    if (label.contains('stalled')) return cs.error;
    if (state.contains('seed')) return cs.tertiary;
    if (state.contains('download')) return cs.primary;
    if (state.contains('error') || state.contains('stall')) return cs.error;
    if (state.contains('pause')) return cs.outline;
    return cs.outlineVariant;
  }

  List<TorrentViewState> _sorted(List<TorrentViewState> all) {
    var list = all.toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) => t.name.toLowerCase().contains(q)).toList();
    }

    list.sort((a, b) {
      switch (_sortMode) {
        case _SortMode.dateAdded:
          return (b.model.addedAt ?? 0).compareTo(a.model.addedAt ?? 0);
        case _SortMode.nameAZ:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortMode.nameZA:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case _SortMode.sizeAsc:
          return (a.model.totalSize ?? 0).compareTo(b.model.totalSize ?? 0);
        case _SortMode.sizeDesc:
          return (b.model.totalSize ?? 0).compareTo(a.model.totalSize ?? 0);
        case _SortMode.progress:
          return b.progress.compareTo(a.progress);
        case _SortMode.status:
          return a.statusLabel.compareTo(b.statusLabel);
      }
    });

    return list;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _toggleTorrent(TorrentViewState ts) async {
    try {
      if (ts.isActive) {
        TorrentEngineService.instance.pauseTorrent(ts.model.id);
        await TorrentService.instance.updateTorrentStatus(
          ts.model.id,
          'paused',
        );
      } else {
        if (TorrentEngineService.instance.isRunning(ts.model.id)) {
          TorrentEngineService.instance.resumeTorrent(ts.model.id);
        } else {
          await TorrentEngineService.instance.startTorrent(ts.model.id);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.unableToggle(e))));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _redownloadTorrent(TorrentViewState ts) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.redownloadFromScratch),
        // overflow-fix: torrent names can be long; keep dialog content scroll-safe.
        content: SingleChildScrollView(
          child: Text(
            context.l10n.willDeletedFromDiskDownloaded2(ts.model.name),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.redownload),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TorrentEngineService.instance.forceRedownload(ts.model.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.restartedFromScratch(ts.name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.redownloadFailed(e))));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _deleteTorrent(TorrentViewState ts) async {
    var deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(context.l10n.removeTorrent),
          // overflow-fix: keep dynamic torrent name prompts scroll-safe.
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.willRemovedFromList(ts.name),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: deleteFiles,
                  onChanged: (value) =>
                      setDialogState(() => deleteFiles = value ?? false),
                  title: Text(context.l10n.alsoDeleteDownloadedFiles),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(deleteFiles ? context.l10n.removeDeleteFiles : context.l10n.actionRemove),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await TorrentEngineService.instance.stopTorrent(ts.model.id);
      if (deleteFiles) {
        await TorrentService.instance.purgeTorrentArtifacts(ts.model.id);
      }
      await TorrentService.instance.removeTorrent(ts.model.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            deleteFiles
                ? context.l10n.torrentRemovedFilesDeleted
                : context.l10n.torrentRemoved,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.removeFailed(e))));
    }
  }

  Future<void> _openTorrentFolder(TorrentModel torrent) async {
    final String pathToOpen;
    if (torrent.filePath != null && torrent.filePath!.isNotEmpty) {
      final lp = torrent.filePath!.toLowerCase();
      pathToOpen = lp.endsWith('.torrent')
          ? SettingsService.instance.downloadDestination
          : torrent.filePath!;
    } else {
      pathToOpen = SettingsService.instance.downloadDestination;
    }

    if (pathToOpen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noDownloadFolderConfigured)),
      );
      return;
    }

    final String directoryPath;
    if (Directory(pathToOpen).existsSync()) {
      directoryPath = pathToOpen;
    } else if (File(pathToOpen).existsSync()) {
      directoryPath = File(pathToOpen).parent.path;
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.folderDoesNotExist)));
      return;
    }

    // Android: try Documents provider first, then fallback to showing the path.
    if (Platform.isAndroid) {
      final opened = await _tryOpenFolderOnAndroid(directoryPath);
      if (opened) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.unableOpenFolderAutomaticallyFiles2(directoryPath),
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
      return;
    }

    try {
      if (Platform.isWindows) {
        try {
          await Process.start(
            'explorer.exe',
            <String>[directoryPath],
            mode: ProcessStartMode.detached,
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.failedOpenFolder2(directoryPath)),
            ),
          );
        }
        return;
      }

      final uri = Uri.file(directoryPath);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(context.l10n.failedOpenFolder2(directoryPath))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.couldNotOpenFolder(e))));
    }
  }

  Future<void> _pickTorrentFile() async {
    if (!await _validateDownloadFolder()) return;
    if (_pickerBusy) return;
    _pickerBusy = true;
    try {
      final path = await pickSingleFilePath(
        context,
        dialogTitle: context.l10n.selectTorrentFile,
        allowedExtensions: const <String>['torrent'],
      );
      if (path == null || path.isEmpty) {
        return;
      }
      await TorrentService.instance.addTorrentFromTorrentFile(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.torrentAddedFromFile)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.failedAddTorrentFile(e))));
    } finally {
      _pickerBusy = false;
    }
  }

  Future<void> _openCreateTorrent() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateTorrentScreen()));
  }

  Future<void> _handleDropPath(String path) async {
    if (!await _validateDownloadFolder()) return;
    try {
      if (path.toLowerCase().endsWith('.torrent')) {
        await TorrentService.instance.addTorrentFromTorrentFile(path);
      } else {
        await TorrentService.instance.addTorrentFromPath(path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.torrentAddedViaDragDrop)),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.importFailed(e))));
    }
  }

  Future<void> _showAddMagnetDialog() async {
    if (!await _validateDownloadFolder()) return;
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.addTorrent),
        content: TextField(
          controller: ctrl,
          minLines: 1,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: context.l10n.pasteMagnetLinkMagnetXt,
            prefixIcon: const Icon(Icons.link),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(context.l10n.actionAdd),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await TorrentService.instance.addTorrentFromMagnetLink(result);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.torrentAdded)));
    } on TorrentAlreadyExistsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.torrentAlreadyList)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.failedAdd(e))));
    }
  }

  Future<void> _handleAddAction(String value) async {
    switch (value) {
      case 'magnet':
        await _showAddMagnetDialog();
        break;
      case 'file':
        await _pickTorrentFile();
        break;
      case 'create':
        await _openCreateTorrent();
        break;
    }
  }

  PopupMenuButton<String> _buildAddMenuButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.add_circle_outline),
      tooltip: context.l10n.addCreateTorrent,
      onSelected: (value) => unawaited(_handleAddAction(value)),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'magnet',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.add_link),
            title: Text(context.l10n.addMagnetLink),
          ),
        ),
        PopupMenuItem<String>(
          value: 'file',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.file_open_outlined),
            title: Text(context.l10n.addTorrentFile),
          ),
        ),
        PopupMenuItem<String>(
          value: 'create',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(context.l10n.createTorrent2),
          ),
        ),
      ],
    );
  }

  Widget _buildFab() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (!isMobile) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabExpanded) ...[
          FloatingActionButton.small(
            heroTag: 'create_torrent_fab',
            onPressed: _openCreateTorrent,
            tooltip: context.l10n.createTorrent2,
            child: const Icon(Icons.create_new_folder_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'pick_torrent_fab',
            onPressed: _pickTorrentFile,
            tooltip: context.l10n.pickTorrentFile,
            child: const Icon(Icons.file_open_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'paste_magnet_fab',
            onPressed: _showAddMagnetDialog,
            icon: const Icon(Icons.add_link),
            label: Text(context.l10n.pasteMagnet),
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton(
          heroTag: 'torrent_fab_toggle',
          onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
          tooltip: _fabExpanded ? context.l10n.closeActions : context.l10n.addTorrent,
          child: Icon(_fabExpanded ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: TorrentDragDrop(
          onTorrentFile: _handleDropPath,
          onPath: _handleDropPath,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: StreamBuilder<List<TorrentViewState>>(
              stream: TorrentService.instance.torrentStatesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final torrents = _sorted(all);

                // Empty: no torrents at all
                if (all.isEmpty) {
                  return _buildEmptyState();
                }

                // Empty: search returned nothing
                if (torrents.isEmpty) {
                  return _buildNoSearchResults();
                }

                final width = MediaQuery.of(context).size.width;
                final useGrid = width > 900;
                final bottomPad = Platform.isAndroid ? 96.0 : 12.0;
                final horizontalPad = width > 1600 ? 24.0 : 12.0;

                if (useGrid) {
                  return GridView.builder(
                    cacheExtent: 200,
                    padding: EdgeInsets.fromLTRB(
                      horizontalPad,
                      12,
                      horizontalPad,
                      bottomPad,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 430,
                      mainAxisExtent: 182,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: torrents.length,
                    itemBuilder: (context, index) => _buildTorrentCard(
                        context, torrents[index],
                        isGridCard: true),
                  );
                }

                return ListView.builder(
                  cacheExtent: 200,
                  padding: EdgeInsets.only(bottom: bottomPad),
                  itemCount: torrents.length,
                  itemBuilder: (context, index) =>
                      _buildTorrentCard(context, torrents[index]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: _showSearch
          ? TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.l10n.searchTorrents,
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: Theme.of(context).textTheme.titleMedium,
              onChanged: _onSearchChanged,
            )
          : Text(context.l10n.tabTorrents),
      actions: [
        _buildAddMenuButton(),
        // Search toggle
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          tooltip: _showSearch ? context.l10n.cancelSearch : context.l10n.searchTorrents2,
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _searchQuery = '';
              _searchController.clear();
            }
          }),
        ),
        // Sort popup
        PopupMenuButton<_SortMode>(
          icon: const Icon(Icons.sort),
          tooltip: context.l10n.sortBy,
          onSelected: _setSortMode,
          itemBuilder: (ctx) => _SortMode.values
              .map(
                (m) => PopupMenuItem<_SortMode>(
                  value: m,
                  child: Row(
                    children: [
                      Icon(
                        m.icon,
                        size: 16,
                        color: _sortMode == m
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          m.label(context),
                          style: TextStyle(
                            fontWeight: _sortMode == m
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: _sortMode == m
                                ? Theme.of(ctx).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                      if (_sortMode == m) ...[
                        const Spacer(),
                        Icon(
                          Icons.check,
                          size: 14,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        // Open download folder (desktop only)
        if (!Platform.isAndroid)
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: context.l10n.openDownloadFolder,
            onPressed: () async {
              final pseudo = TorrentModel(
                id: '',
                name: '',
                type: 'magnet_link',
                filePath: SettingsService.instance.downloadDestination,
              );
              await _openTorrentFolder(pseudo);
            },
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: context.l10n.actionRefresh,
          onPressed: _refresh,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final hasFolder =
        SettingsService.instance.downloadDestination.trim().isNotEmpty;
    return EmptyState(
      icon: hasFolder
          ? Icons.download_for_offline_outlined
          : Icons.folder_open_outlined,
      title: hasFolder ? context.l10n.noTorrentsYet : context.l10n.setDownloadFolderFirst,
      subtitle: hasFolder
          ? (Platform.isAndroid
              ? context.l10n.tapAddCreateTorrents
              : Platform.isIOS
                  ? context.l10n.tapAddCreateTorrents
                  : context.l10n.useTopBarAddCreate)
          : context.l10n.goSettingsDownloadLocationChoose,
      action: hasFolder
          ? Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _showAddMagnetDialog,
                  icon: const Icon(Icons.add_link, size: 18),
                  label: Text(context.l10n.addMagnet),
                ),
                OutlinedButton.icon(
                  onPressed: _pickTorrentFile,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: Text(context.l10n.addTorrentFile2),
                ),
                OutlinedButton.icon(
                  onPressed: _openCreateTorrent,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: Text(context.l10n.createTorrent),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    launchUrl(
                      Uri.parse('https://quizthespire.com/'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(context.l10n.visitQuizSpire),
                ),
              ],
            )
          : FilledButton.icon(
              onPressed: _showSetDownloadFolderDialog,
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(context.l10n.goSettings),
            ),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 56,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.noResults(_searchQuery),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _searchQuery = '';
              _searchController.clear();
              _showSearch = false;
            }),
            child: Text(context.l10n.clearSearch),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentCard(
    BuildContext context,
    TorrentViewState ts, {
    bool isGridCard = false,
  }) {
    final torrent = ts.model;
    final stateColor = _stateColor(context, ts.state, ts.statusLabel);
    final cs = Theme.of(context).colorScheme;
    final totalSize = torrent.totalSize ?? 0;
    final progress = ts.progress.clamp(0.0, 1.0);
    final progressPercent = (progress * 100).toStringAsFixed(1);
    final remainingBytes =
        totalSize > 0 ? (totalSize - ts.downloaded).clamp(0, totalSize) : 0;
    final etaText = ts.downloadSpeed > 512 && remainingBytes > 0
        ? _fmtEta(remainingBytes / ts.downloadSpeed)
        : null;
    final denseDesktop = isGridCard;

    void copyMagnetLink() {
      final magnet = torrent.magnetLink;
      if (magnet != null && magnet.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: magnet));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.magnetLinkCopied)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.noMagnetLinkAvailable)),
        );
      }
    }

    void showLongPressActions() {
      final magnet = torrent.magnetLink;
      final path = torrent.filePath ?? '';
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(context.l10n.copyMagnetLink),
                onTap: () {
                  Navigator.pop(ctx);
                  if (magnet != null && magnet.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: magnet));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.magnetLinkCopied)),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.noMagnetLinkAvailable)),
                    );
                  }
                },
              ),
              if (path.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(context.l10n.copyFilePath),
                  subtitle: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: path));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.filePathCopied)),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    }

    void openDetails() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorrentDetailScreen(torrent: torrent),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: _HoverLift(
        child: Card(
          key: ValueKey(ts.id),
          margin: EdgeInsets.symmetric(
            horizontal: isGridCard ? 0 : 12,
            vertical: isGridCard ? 0 : 5,
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.20)),
          ),
          child: InkWell(
            onTap: openDetails,
            onLongPress: showLongPressActions,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                denseDesktop ? 12 : 14,
                denseDesktop ? 10 : 12,
                8,
                denseDesktop ? 8 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          torrent.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isGridCard ? 15.5 : 14.5,
                            height: 1.18,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: isGridCard ? 2 : 1,
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        splashRadius: 18,
                        tooltip: context.l10n.more,
                        onSelected: (v) {
                          switch (v) {
                            case 'toggle':
                              _toggleTorrent(ts);
                              break;
                            case 'folder':
                              _openTorrentFolder(torrent);
                              break;
                            case 'copy':
                              copyMagnetLink();
                              break;
                            case 'redownload':
                              _redownloadTorrent(ts);
                              break;
                            case 'delete':
                              _deleteTorrent(ts);
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'toggle',
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                ts.isActive
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                              ),
                              title: Text(ts.isActive ? context.l10n.actionPause : context.l10n.actionResume),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'folder',
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder_open),
                              title: Text(context.l10n.openFolder),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'copy',
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.link),
                              title: Text(context.l10n.copyMagnetLink),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'redownload',
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.replay),
                              title: Text(context.l10n.redownloadFromScratch2),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              dense: true,
                              leading: const Icon(Icons.delete_outline),
                              title: Text(context.l10n.actionRemove),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: denseDesktop ? 7 : 10),
                  Wrap(
                    spacing: denseDesktop ? 7 : 8,
                    runSpacing: denseDesktop ? 4 : 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: stateColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ts.statusLabel,
                          style: TextStyle(
                            fontSize: denseDesktop ? 10.5 : 11,
                            fontWeight: FontWeight.w700,
                            color: stateColor,
                          ),
                        ),
                      ),
                      if (totalSize > 0)
                        Text(
                          _fmtSize(totalSize),
                          style: TextStyle(
                            fontSize: denseDesktop ? 10.5 : 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        '$progressPercent%',
                        style: TextStyle(
                          fontSize: denseDesktop ? 11 : 11.5,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: denseDesktop ? 7 : 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: denseDesktop ? 5 : 6,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                    ),
                  ),
                  SizedBox(height: denseDesktop ? 5 : 12),
                  Wrap(
                    spacing: denseDesktop ? 8 : 10,
                    runSpacing: denseDesktop ? 3 : 6,
                    children: [
                      if (ts.downloadSpeed > 512)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_downward,
                                size: denseDesktop ? 11 : 12,
                                color: cs.primary),
                            const SizedBox(width: 2),
                            Text(
                              _fmtSpeed(ts.downloadSpeed),
                              style: TextStyle(
                                  fontSize: denseDesktop ? 10.5 : 11,
                                  color: cs.primary),
                            ),
                          ],
                        ),
                      if (ts.uploadSpeed > 512)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_upward,
                                size: denseDesktop ? 11 : 12,
                                color: cs.tertiary),
                            const SizedBox(width: 2),
                            Text(
                              _fmtSpeed(ts.uploadSpeed),
                              style: TextStyle(
                                  fontSize: denseDesktop ? 10.5 : 11,
                                  color: cs.tertiary),
                            ),
                          ],
                        ),
                      if (etaText != null)
                        Text(
                          'ETA $etaText',
                          style: TextStyle(
                            fontSize: denseDesktop ? 11 : 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      if (ts.peers > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline,
                                size: denseDesktop ? 11 : 12,
                                color: cs.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text(
                              '${ts.peers}',
                              style: TextStyle(
                                fontSize: denseDesktop ? 11 : 11.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  final Widget child;

  const _HoverLift({required this.child});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.01 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: _hovered ? const Offset(0, -0.01) : Offset.zero,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
