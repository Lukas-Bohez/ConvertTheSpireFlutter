import 'package:flutter/material.dart';

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
    await widget.watchedService.addPlaylist(url);
    _urlController.clear();
    await _loadUrls();
  }

  Future<void> _removePlaylist(String url) async {
    await widget.watchedService.removePlaylist(url);
    await _loadUrls();
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    final found = await widget.watchedService.checkAllPlaylists();
    if (mounted) {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$found new track(s) queued for download')),
      );
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'Paste playlist URL',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addPlaylist(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.add),
                onPressed: _addPlaylist,
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: const Icon(Icons.refresh),
                tooltip: 'Check now',
                onPressed: _checking ? null : _checkNow,
              ),
            ],
          ),
        ),
        if (_checking) const LinearProgressIndicator(),
        Expanded(
          child: _urls.isEmpty
              ? const Center(child: Text('No watched playlists yet'))
              : ListView.builder(
                  itemCount: _urls.length,
                  itemBuilder: (context, index) {
                    final url = _urls[index];
                    return ListTile(
                      title: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: const Text('Checked periodically for new tracks'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removePlaylist(url),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
