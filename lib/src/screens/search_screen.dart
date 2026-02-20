import 'dart:async';

import 'package:flutter/material.dart';

import '../models/search_result.dart';
import '../services/multi_source_search_service.dart';
import '../services/preview_player_service.dart';

/// Screen for searching multiple audio sources in parallel.
class SearchScreen extends StatefulWidget {
  final MultiSourceSearchService searchService;
  final PreviewPlayerService previewPlayer;
  final void Function(SearchResult result, String format) onDownload;

  const SearchScreen({
    super.key,
    required this.searchService,
    required this.previewPlayer,
    required this.onDownload,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  List<SearchResult> _results = [];
  bool _loading = false;
  String? _error;
  Timer? _hoverTimer;
  String? _previewingId;
  String _selectedFormat = 'mp3';

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await widget.searchService.searchAll(query, limitPerSource: 15);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _startPreview(SearchResult result) {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(seconds: 2), () async {
      try {
        final url = await widget.searchService.youtubeSearcher.getAudioUrl(result.id);
        if (!mounted) return;
        setState(() => _previewingId = result.id);
        await widget.previewPlayer.previewAudio(url);
      } catch (_) {}
    });
  }

  void _stopPreview() {
    _hoverTimer?.cancel();
    widget.previewPlayer.stopPreview();
    setState(() => _previewingId = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    _hoverTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 500;
              final searchField = Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Search for music across sources…',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _search(),
                ),
              );
              final formatDropdown = DropdownButton<String>(
                value: _selectedFormat,
                items: const [
                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                  DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                  DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedFormat = v);
                },
              );
              final searchButton = ElevatedButton(
                onPressed: _loading ? null : _search,
                child: const Text('Search'),
              );

              if (narrow) {
                return Column(
                  children: [
                    Row(children: [searchField]),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        formatDropdown,
                        const Spacer(),
                        searchButton,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  searchField,
                  const SizedBox(width: 8),
                  formatDropdown,
                  const SizedBox(width: 8),
                  searchButton,
                ],
              );
            },
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final r = _results[index];
              return MouseRegion(
                onEnter: (_) => _startPreview(r),
                onExit: (_) => _stopPreview(),
                child: ListTile(
                  leading: r.thumbnailUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(r.thumbnailUrl, width: 48, height: 48, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.music_note, size: 48),
                  title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${r.artist}  •  ${_formatDuration(r.duration)}  •  ${r.source}',
                    maxLines: 1,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_previewingId == r.id)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.volume_up, size: 18, color: Colors.teal),
                        ),
                      IconButton(
                        icon: const Icon(Icons.download),
                        tooltip: 'Download',
                        onPressed: () => widget.onDownload(r, _selectedFormat),
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
