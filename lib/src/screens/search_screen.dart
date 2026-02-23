import 'dart:async';

import 'package:flutter/material.dart';

import '../models/search_result.dart';
import '../services/multi_source_search_service.dart';
import '../services/preview_player_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';

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
  // preview removed, use external button
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


  @override
  void dispose() {
    _controller.dispose();
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
              final leadingWidget = r.thumbnailUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(r.thumbnailUrl, width: 48, height: 48, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.music_note, size: 48);

              final previewButton = IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Preview in browser',
                onPressed: () => _launchPreview(r.id),
              );

              final downloadButton = IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download',
                onPressed: () => widget.onDownload(r, _selectedFormat),
              );

              return ListTile(
                leading: leadingWidget,
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${r.artist}  •  ${_formatDuration(r.duration)}  •  ${r.source}',
                  maxLines: 1,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [previewButton, downloadButton],
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

  void _launchPreview(String id) {
    final url = 'https://www.youtube.com/watch?v=$id';
    // try to find the HomeScreen state to move to browser tab; if not
    // available (e.g. tests) fall back to external launch.
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    if (homeState != null) {
      homeState.openBrowserWith(url);
    } else {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
