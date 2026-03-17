import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/search_result.dart';
import '../services/multi_source_search_service.dart';
import '../services/preview_player_service.dart';
import '../state/app_controller.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
// Fix: use an explicit show clause so the analyzer knows exactly which
// symbol is needed.  This resolves both the unused_import warning (the
// import IS used, just not visible without the clause) and the
// non_type_as_type_argument error that appeared when home_screen.dart's
// own imports caused a cascading ambiguity.
import 'home_screen.dart' show HomeScreenState;

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
  String _selectedFormat = 'mp3';

  // Tracks what files already exist in the user-selected download directory.
  Set<String> _downloadedFileKeys = {};
  final List<Set<String>> _downloadedFileTokens = [];
  DateTime? _lastDownloadFolderScan;
  bool _scanningDownloadFolder = false;

  @override
  void initState() {
    super.initState();
    _refreshDownloadedFiles();
  }

  String _normalizeKey(String input) {
    var s = input.toLowerCase();
    // Remove common featuring markers
    s = s.replaceAll(RegExp(r'\b(feat|ft|featuring)\b\.?', caseSensitive: false), '');
    // Replace ampersands
    s = s.replaceAll('&', ' and ');
    // Remove bracketed info (e.g. (remix), [live], {explicit})
    s = s.replaceAll(RegExp(r'[\[\(\{].*?[\]\)\}]'), '');
    // Keep only alphanumeric + spaces
    s = s.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    // Collapse whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  Set<String> _tokenize(String input) {
    return _normalizeKey(input).split(' ').where((t) => t.isNotEmpty).toSet();
  }

  bool _isAlreadyDownloaded(SearchResult r) {
    if (_downloadedFileKeys.isEmpty) return false;

    final title = _normalizeKey(r.title);
    final full = _normalizeKey('${r.artist} ${r.title}');
    final tokens = _tokenize('${r.artist} ${r.title}');

    if (_downloadedFileKeys.contains(full) || _downloadedFileKeys.contains(title)) {
      return true;
    }

    for (final key in _downloadedFileKeys) {
      if (key.contains(title) || title.contains(key) || key.contains(full) || full.contains(key)) {
        return true;
      }
    }

    if (tokens.isNotEmpty) {
      for (final existing in _downloadedFileTokens) {
        if (existing.isEmpty) continue;
        final intersection = tokens.intersection(existing).length;
        final minSize = min(tokens.length, existing.length);
        if (minSize > 0 && intersection / minSize >= 0.65) {
          return true;
        }
      }
    }

    return false;
  }

  Future<void> _refreshDownloadedFiles({bool showSnack = true}) async {
    if (!mounted) return;
    final settings = context.read<AppController>().settings;
    final folder = settings?.downloadDir;
    if (folder == null || folder.isEmpty) return;
    if (folder.startsWith('content://')) return;

    setState(() => _scanningDownloadFolder = true);

    // Scan the download folder so we can mark already-downloaded results.
    // Only support the three target output formats.
    final extWhitelist = {'.mp3', '.m4a', '.mp4'};

    final scanned = <String>{};
    final scannedTokens = <Set<String>>[];
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!extWhitelist.contains(ext)) continue;
        final base = p.basenameWithoutExtension(entity.path);
        final key = _normalizeKey(base);
        scanned.add(key);
        scannedTokens.add(_tokenize(base));
      }
    } catch (e) {
      // Ignore scan errors; just don't mark any results as downloaded.
      debugPrint('Download folder scan failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _downloadedFileKeys = scanned;
      _downloadedFileTokens
        ..clear()
        ..addAll(scannedTokens);
      _scanningDownloadFolder = false;
      _lastDownloadFolderScan = DateTime.now();
    });

    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download folder scan complete')),
      );
    }
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results =
          await widget.searchService.searchAll(query, limitPerSource: 15);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      _refreshDownloadedFiles();
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
              final refreshButton = IconButton(
                icon: _scanningDownloadFolder
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: _scanningDownloadFolder
                    ? 'Scanning download folder…'
                    : 'Refresh downloaded file status',
                onPressed: _scanningDownloadFolder ? null : () => _refreshDownloadedFiles(),
              );

              if (narrow) {
                return Column(
                  children: [
                    Row(children: [searchField, refreshButton]),
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
                  refreshButton,
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
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_lastDownloadFolderScan != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Last scan: ${TimeOfDay.fromDateTime(_lastDownloadFolderScan!).format(context)}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final r = _results[index];
              final cs = Theme.of(context).colorScheme;
              final alreadyDownloaded = _isAlreadyDownloaded(r);
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
                color: alreadyDownloaded
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.65)
                    : null,
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
                                    fontSize: 12, color: cs.onSurfaceVariant),
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
                        if (alreadyDownloaded) ...[
                          Icon(Icons.check_circle, size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                        ],
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
    // Walk up the widget tree to find HomeScreen's state so we can open
    // the in-app browser rather than launching an external app.
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    if (homeState != null) {
      homeState.openBrowserWith(url);
    } else {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}