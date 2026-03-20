import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/snack.dart';
import '../widgets/empty_state.dart';

import '../services/watched_playlist_service.dart';

class PlaylistFolderConfig {
  final String? defaultFolder;
  final String? mp3Folder;
  final String? m4aFolder;
  final String? mp4Folder;

  const PlaylistFolderConfig({
    this.defaultFolder,
    this.mp3Folder,
    this.m4aFolder,
    this.mp4Folder,
  });

  bool get hasAny =>
      (defaultFolder?.trim().isNotEmpty == true) ||
      (mp3Folder?.trim().isNotEmpty == true) ||
      (m4aFolder?.trim().isNotEmpty == true) ||
      (mp4Folder?.trim().isNotEmpty == true);
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
  List<String> _urls = [];
  final Map<String, PlaylistFolderConfig> _playlistFolders = {};
  bool _checking = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadUrls();
  }

  Future<void> _loadUrls() async {
    final urls = await widget.watchedService.getWatchedUrls();
    if (!mounted) return;
    setState(() => _urls = urls);
    await _loadPlaylistFolders(urls);
  }

  Future<void> _loadPlaylistFolders(List<String> urls) async {
    final folders = <String, PlaylistFolderConfig>{};
    for (final url in urls) {
      final defaultFolder = await widget.watchedService.getFolderForPlaylist(url);
      final mp3Folder = await widget.watchedService.getFolderForPlaylist(url, format: 'mp3');
      final m4aFolder = await widget.watchedService.getFolderForPlaylist(url, format: 'm4a');
      final mp4Folder = await widget.watchedService.getFolderForPlaylist(url, format: 'mp4');
      folders[url] = PlaylistFolderConfig(
        defaultFolder: defaultFolder,
        mp3Folder: mp3Folder,
        m4aFolder: m4aFolder,
        mp4Folder: mp4Folder,
      );
    }
    if (mounted) {
      setState(() => _playlistFolders
        ..clear()
        ..addAll(folders));
    }
  }

  Future<void> _addPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    if (!url.contains('youtube.com/playlist') && !url.contains('youtu.be')) {
      if (mounted) {
        Snack.show(context, 'Please enter a valid YouTube playlist URL',
            level: SnackLevel.warning);
      }
      return;
    }
    await widget.watchedService.addPlaylist(url);
    if (!mounted) return;
    _urlController.clear();
    await _loadUrls();
  }

  Future<void> _removePlaylist(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Playlist'),
        content:
            const Text('Stop watching this playlist? You can re-add it later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.watchedService.removePlaylist(url);
    await _loadUrls();
  }

  Future<void> _pickPlaylistFolder(String url) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Set playlist folder'),
        children: [
          SimpleDialogOption(
            child: const Text('All formats (default)'),
            onPressed: () => Navigator.pop(ctx, 'default'),
          ),
          SimpleDialogOption(
            child: const Text('MP3 folder'),
            onPressed: () => Navigator.pop(ctx, 'mp3'),
          ),
          SimpleDialogOption(
            child: const Text('M4A folder'),
            onPressed: () => Navigator.pop(ctx, 'm4a'),
          ),
          SimpleDialogOption(
            child: const Text('MP4 folder'),
            onPressed: () => Navigator.pop(ctx, 'mp4'),
          ),
          SimpleDialogOption(
            child: const Text('Clear folders'),
            onPressed: () => Navigator.pop(ctx, 'clear'),
          ),
        ],
      ),
    );

    if (choice == null) return;
    if (choice == 'clear') {
      await widget.watchedService.removeFolderForPlaylist(url);
      await _loadPlaylistFolders(_urls);
      if (mounted) {
        Snack.show(context, 'Playlist folders cleared', level: SnackLevel.info);
      }
      return;
    }

    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null || !mounted) return;

    if (choice == 'default') {
      await widget.watchedService.setFolderForPlaylist(url, directory);
    } else {
      await widget.watchedService.setFolderForPlaylist(url, directory,
          format: choice);
    }

    await _loadPlaylistFolders(_urls);
    if (mounted) {
      Snack.show(context, 'Folder set for playlist', level: SnackLevel.info);
    }
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final found = await widget.watchedService.checkAllPlaylists();
      if (mounted) {
        setState(() => _checking = false);
        Snack.show(context, '$found new track(s) queued for download',
            level: SnackLevel.info);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
        Snack.show(context, 'Failed to check playlists: $e',
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
    return Column(
      children: [
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
                      decoration: const InputDecoration(
                        hintText: 'Paste YouTube playlist URL',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.link),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addPlaylist(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add playlist',
                    onPressed: _addPlaylist,
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Check all for new tracks',
                    onPressed: _checking ? null : _checkNow,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_checking) const LinearProgressIndicator(),
        Expanded(
          child: _urls.isEmpty
              ? EmptyState(
                  icon: Icons.playlist_add,
                  title: 'No watched playlists yet',
                  subtitle:
                      'Add a YouTube playlist URL above to track new tracks',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemCount: _urls.length,
                  itemBuilder: (context, index) {
                    final url = _urls[index];
                    final folder = _playlistFolders[url];
                    String folderLabel;
                    if (folder == null || !folder.hasAny) {
                      folderLabel = 'Download folder: (default)';
                    } else if (folder.defaultFolder?.trim().isNotEmpty == true) {
                      folderLabel =
                          'Download folder: ${folder.defaultFolder!.split(RegExp(r'[/\\]')).last}';
                    } else {
                      final parts = <String>[];
                      if (folder.mp3Folder?.trim().isNotEmpty == true) {
                        parts.add('MP3: ${folder.mp3Folder!.split(RegExp(r'[/\\]')).last}');
                      }
                      if (folder.m4aFolder?.trim().isNotEmpty == true) {
                        parts.add('M4A: ${folder.m4aFolder!.split(RegExp(r'[/\\]')).last}');
                      }
                      if (folder.mp4Folder?.trim().isNotEmpty == true) {
                        parts.add('MP4: ${folder.mp4Folder!.split(RegExp(r'[/\\]')).last}');
                      }
                      folderLabel = parts.join(' • ');
                    }
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.playlist_play, color: cs.primary),
                        title: Text(url,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Checked periodically for new tracks'),
                            const SizedBox(height: 2),
                            Text(
                              folderLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.folder_open),
                              tooltip: 'Set folder for this playlist',
                              onPressed: () => _pickPlaylistFolder(url),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove playlist',
                              onPressed: () => _removePlaylist(url),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
