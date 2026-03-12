import 'package:flutter/material.dart';
import '../utils/snack.dart';
import '../widgets/empty_state.dart';

import '../services/watched_playlist_service.dart';

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
    if (mounted) setState(() => _urls = urls);
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
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.playlist_play, color: cs.primary),
                        title: Text(url,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle:
                            const Text('Checked periodically for new tracks'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove playlist',
                          onPressed: () => _removePlaylist(url),
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
