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
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text('Searching across all sources\u2026',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final r = _results[index];
              final cs = Theme.of(context).colorScheme;
              final leadingWidget = r.thumbnailUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(r.thumbnailUrl,
                          width: 56, height: 56, fit: BoxFit.cover),
                    )
                  : Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.music_note,
                          size: 28, color: cs.onSurfaceVariant),
                    );

              return Card(
                margin: EdgeInsets.zero,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.onDownload(r, _selectedFormat),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        leadingWidget,
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 3),
                              Text(
                                '${r.artist}  \u2022  ${_formatDuration(r.duration)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(r.source,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onPrimaryContainer)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'Preview in browser',
                          onPressed: () => _launchPreview(r.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: 'Download',
                          onPressed: () =>
                              widget.onDownload(r, _selectedFormat),
                        ),
                      ],
                    ),
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
