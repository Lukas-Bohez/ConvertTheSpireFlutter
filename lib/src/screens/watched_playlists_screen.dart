import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/watched_playlist_service.dart';
import '../utils/l10n.dart';
import '../utils/snack.dart';
import '../widgets/empty_state.dart';
import '../widgets/monetization_widgets.dart';
import '../widgets/tv_file_browser.dart';

/// Result of the add/edit entry dialog.
class _WatchedEntryInputs {
  final String url;
  final String? folder;
  final String? format;

  const _WatchedEntryInputs({required this.url, this.folder, this.format});
}

/// Screen for managing watched playlists that auto-download new tracks.
class WatchedPlaylistsScreen extends StatefulWidget {
  final WatchedPlaylistService watchedService;

  const WatchedPlaylistsScreen({super.key, required this.watchedService});

  @override
  State<WatchedPlaylistsScreen> createState() => _WatchedPlaylistsScreenState();
}

class _WatchedPlaylistsScreenState extends State<WatchedPlaylistsScreen>
    with AutomaticKeepAliveClientMixin {
  final _urlController = TextEditingController();
  List<WatchedPlaylistEntry> _entries = [];
  bool _checking = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final entries = await widget.watchedService.getEntries();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  static bool _isPlaylistUrl(String url) =>
      url.contains('youtube.com/playlist') || url.contains('youtu.be');

  Future<void> _addPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!_isPlaylistUrl(url)) {
      if (mounted) {
        Snack.show(context, context.l10n.pleaseEnterValidYoutubePlaylist,
            level: SnackLevel.warning);
      }
      return;
    }
    final result = await showDialog<_WatchedEntryInputs>(
      context: context,
      builder: (ctx) => _WatchedEntryDialog(initialUrl: url),
    );
    if (result == null || !mounted) return;
    await widget.watchedService.addEntry(
      url: result.url,
      folder: result.folder,
      format: result.format,
    );
    _urlController.clear();
    await _loadEntries();
  }

  Future<void> _editEntry(WatchedPlaylistEntry entry) async {
    final result = await showDialog<_WatchedEntryInputs>(
      context: context,
      builder: (ctx) => _WatchedEntryDialog(
        initialUrl: entry.url,
        initialFormat: entry.format,
        initialFolder: entry.folder,
        isEdit: true,
      ),
    );
    if (result == null || !mounted) return;
    await widget.watchedService.updateEntry(
      entry.id,
      folder: result.folder,
      format: result.format,
    );
    await _loadEntries();
  }

  Future<void> _removeEntry(WatchedPlaylistEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removePlaylist),
        // overflow-fix: keep confirmation text scroll-safe on compact devices.
        content: SingleChildScrollView(
          child: Text(context.l10n.stopWatchingPlaylistCanRe),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.actionCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.actionRemove)),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.watchedService.removeEntry(entry.id);
    await _loadEntries();
  }
Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final found = await widget.watchedService.checkAllPlaylists();
      if (mounted) {
        setState(() => _checking = false);
        Snack.show(context, context.l10n.newTrackSQueuedDownload(found),
            level: SnackLevel.info);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
        Snack.show(context, context.l10n.failedCheckPlaylists(e),
            level: SnackLevel.error);
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      child: Column(
        children: [
          // The feature explanation lives here once, not on every card.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.watchedPlaylistsCheckedPeriodicallyAny,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: context.l10n.pasteYoutubePlaylistUrl,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.link),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _addPlaylist(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: Icon(Icons.add,
                          color: Theme.of(context).colorScheme.onPrimary),
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      tooltip: context.l10n.addPlaylist,
                      onPressed: _addPlaylist,
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      icon: const Icon(Icons.refresh),
                      tooltip: context.l10n.checkAllNewTracks,
                      onPressed: _checking ? null : _checkNow,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_checking) const LinearProgressIndicator(),
          Expanded(
            child: _entries.isEmpty
                ? EmptyState(
                    icon: Icons.playlist_add,
                    title: context.l10n.noWatchedPlaylistsYet,
                    subtitle:
                        context.l10n.addYoutubePlaylistUrlAbove,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemCount: _entries.length + (_entries.length ~/ 6),
                    itemBuilder: (context, index) {
                      const adInterval = 7;
                      if ((index + 1) % adInterval == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: AdNativeSlot(),
                        );
                      }
                      final realIndex = index - (index ~/ adInterval);
                      final entry = _entries[realIndex];
                      return _buildEntryCard(cs, entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
Widget _buildEntryCard(ColorScheme cs, WatchedPlaylistEntry entry) {
    final format = entry.format?.trim().toUpperCase();
    final formatLabel = (format == null || format.isEmpty)
        ? context.l10n.formatAppDefault
        : context.l10n.watchedFormat(format);
    final folder = entry.folder;
    final folderLabel = (folder == null || folder.trim().isEmpty)
        ? context.l10n.folderDefault
        : context.l10n.watchedFolder(folder.split(RegExp(r'[/\\]')).last);

    // Format is always shown so two entries watching the same URL (but
    // different destinations) are clearly distinct even when folders match.
    return Card(
      child: ListTile(
        leading: Icon(Icons.playlist_play, color: cs.primary),
        title: Text(entry.url, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              folderLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.l10n.editWatchSettings,
              onPressed: () => _editEntry(entry),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.l10n.removePlaylist2,
              onPressed: () => _removeEntry(entry),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single dialog that collects URL (add mode), folder, and format for one
/// entry — replacing the old two-step folder dialog.
class _WatchedEntryDialog extends StatefulWidget {
  final String initialUrl;
  final String? initialFormat;
  final String? initialFolder;
  final bool isEdit;

  const _WatchedEntryDialog({
    required this.initialUrl,
    this.initialFormat,
    this.initialFolder,
    this.isEdit = false,
  });

  @override
  State<_WatchedEntryDialog> createState() => _WatchedEntryDialogState();
}

class _WatchedEntryDialogState extends State<_WatchedEntryDialog> {
  late final TextEditingController _urlController;
  String? _format; // null = app default format
  String? _folder; // null = app default download folder

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _format = widget.initialFormat;
    _folder = widget.initialFolder;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final directory = await pickDirectoryPath(
      context,
      dialogTitle: context.l10n.selectWatchedFolder,
    );
    if (directory == null || !mounted) return;
    setState(() => _folder = directory);
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (!widget.isEdit) {
      if (url.isEmpty ||
          (!url.contains('youtube.com/playlist') && !url.contains('youtu.be'))) {
        Snack.show(context, context.l10n.pleaseEnterValidYoutubePlaylist,
            level: SnackLevel.warning);
        return;
      }
    }
    Navigator.pop(
      context,
      _WatchedEntryInputs(
        url: url.isEmpty ? widget.initialUrl : url,
        folder: _folder,
        format: _format,
      ),
    );
  }
@override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Reuse the app's real supported formats so this list never drifts out
    // of sync if the downloader gains or loses a format.
    final formats = DownloadService.supportedFormats.toList()..sort();
    return AlertDialog(
      title: Text(
          widget.isEdit ? context.l10n.editWatchedPlaylist : context.l10n.addWatchedPlaylist),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _urlController,
              enabled: !widget.isEdit,
              decoration: InputDecoration(
                hintText: context.l10n.pasteYoutubePlaylistUrl,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('wp-format-'
                  '${widget.isEdit ? (widget.initialFormat ?? 'default') : 'new'}'),
              initialValue: _format ?? '',
              decoration: InputDecoration(
                labelText: context.l10n.downloadFormat2,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.audio_file),
              ),
              items: [
                DropdownMenuItem<String>(
                    value: '', child: Text(context.l10n.appDefault)),
                for (final fmt in formats)
                  DropdownMenuItem<String>(
                      value: fmt, child: Text(fmt.toUpperCase())),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _format = value.isEmpty ? null : value);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(context.l10n.chooseFolder),
                  onPressed: _pickFolder,
                ),
                if (_folder != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _folder!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel),
                    tooltip: context.l10n.useDefaultFolder,
                    onPressed: () => setState(() => _folder = null),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isEdit ? context.l10n.update : context.l10n.actionAdd),
        ),
      ],
    );
  }
}