import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/search_result.dart';
import '../services/playlist_service.dart';

/// Screen for loading a playlist, cross-referencing it against a local folder,
/// and taking action on missing / matched / extra tracks.
class PlaylistScreen extends StatefulWidget {
  final PlaylistService playlistService;
  final void Function(List<SearchResult> tracks, String format) onDownloadMissing;

  const PlaylistScreen({
    super.key,
    required this.playlistService,
    required this.onDownloadMissing,
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
  String? _error;
  String _selectedFormat = 'mp3';

  late final TabController _tabController;

  // Filter / sort state
  double _confidenceFilter = 0; // 0 = show all
  _SortMode _sortMode = _SortMode.original;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _loadPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _loading = true;
      _loadingMessage = 'Fetching playlist…';
      _error = null;
      _comparison = null;
      _playlistInfo = null;
    });

    try {
      // Fetch info + tracks in parallel
      final infoFuture = widget.playlistService.getPlaylistInfo(url);
      final tracksFuture = widget.playlistService.getYouTubePlaylistTracks(url);

      final info = await infoFuture;
      final tracks = await tracksFuture;

      if (!mounted) return;
      setState(() {
        _playlistInfo = info;
        _tracks = tracks;
        _loading = false;
        _loadingMessage = null;
        _tabController.index = 0; // Switch to Overview tab
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
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select music folder to compare',
    );
    if (result != null) {
      _folderController.text = result;
    }
  }

  Future<void> _compareToFolder() async {
    if (_tracks == null || _tracks!.isEmpty) return;
    final folder = _folderController.text.trim();
    if (folder.isEmpty) return;

    setState(() {
      _loading = true;
      _loadingMessage = 'Scanning folder & matching…';
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
        // Jump to the most interesting tab
        if (comparison.missingCount > 0) {
          _tabController.index = 2; // Missing tab
        } else {
          _tabController.index = 1; // Matched tab
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

  Future<void> _exportMissing() async {
    if (_comparison == null || _comparison!.missing.isEmpty) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export missing tracks',
      fileName: 'missing_tracks.txt',
      allowedExtensions: ['txt'],
      type: FileType.custom,
    );
    if (result != null) {
      await widget.playlistService.exportTrackList(_comparison!.missing, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${_comparison!.missing.length} tracks to $result')),
        );
      }
    }
  }

  Future<void> _exportM3U() async {
    if (_tracks == null || _tracks!.isEmpty) return;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save M3U playlist',
      fileName: '${_playlistInfo?.title ?? 'playlist'}.m3u',
      allowedExtensions: ['m3u'],
      type: FileType.custom,
    );
    if (result != null) {
      await widget.playlistService.generateM3U(_tracks!, result, format: _selectedFormat);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved M3U to $result')),
        );
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        // ── Top bar: URL + folder inputs ────────────────────────────────
        _buildInputSection(theme, cs),
        if (_loading) _buildLoadingBar(),
        if (_error != null) _buildErrorBar(),
        // ── Main content ────────────────────────────────────────────────
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
    );
  }

  // ─── Input Section ────────────────────────────────────────────────────────

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
                    tooltip: 'Browse…',
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
          Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  // ─── Tab bar ──────────────────────────────────────────────────────────────

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
                style: TextStyle(fontSize: 11, color: badgeColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }

  // ─── Overview Tab ─────────────────────────────────────────────────────────

  Widget _buildOverviewTab(ThemeData theme, ColorScheme cs) {
    return ListView(
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
                '${_playlistInfo!.author}  •  ${_tracks!.length} tracks  •  '
                '${_formatTotalDuration(_tracks!)}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'm3u') _exportM3U();
                  if (v == 'missing') _exportMissing();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'm3u', child: Text('Export as M3U')),
                  if (_comparison != null && _comparison!.missing.isNotEmpty)
                    const PopupMenuItem(value: 'missing', child: Text('Export missing list')),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            ),
          ),

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
                        'low confidence — review them in the Matched tab.',
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
              onPressed: () => widget.onDownloadMissing(_comparison!.missing, _selectedFormat),
              icon: const Icon(Icons.download),
              label: Text('Download All ${_comparison!.missingCount} Missing Tracks'),
            ),
        ] else ...[
          // No comparison yet — show track list
          const SizedBox(height: 8),
          Text('${_tracks!.length} tracks loaded. Select a folder above to compare.',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          const SizedBox(height: 12),
          ...List.generate(
            _tracks!.length,
            (i) {
              final t = _tracks![i];
              return ListTile(
                dense: true,
                leading: Text('${i + 1}', style: theme.textTheme.bodySmall),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist),
                trailing: Text(_formatDuration(t.duration),
                    style: theme.textTheme.bodySmall),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCards(ThemeData theme, ColorScheme cs) {
    final c = _comparison!;
    return Row(
      children: [
        _summaryCard('Total', '${c.total}', Icons.queue_music, cs.primary, theme),
        _summaryCard('Matched', '${c.downloadedCount}', Icons.check_circle, Colors.green, theme),
        _summaryCard('Missing', '${c.missingCount}', Icons.cancel, Colors.orange, theme),
        _summaryCard('Extras', '${c.extraCount}', Icons.library_music, Colors.blue, theme),
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
              Text(value, style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold, color: color)),
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
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold)),
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

  // ─── Matched Tab ──────────────────────────────────────────────────────────

  Widget _buildMatchedTab(ThemeData theme) {
    if (_comparison == null) {
      return const Center(child: Text('Run a comparison first'));
    }

    var matches = List<TrackMatch>.from(_comparison!.matched);

    // Filter by confidence
    if (_confidenceFilter > 0) {
      matches = matches.where((m) => m.confidence >= _confidenceFilter).toList();
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
                  DropdownMenuItem(value: _SortMode.original, child: Text('Playlist order')),
                  DropdownMenuItem(value: _SortMode.title, child: Text('Title A-Z')),
                  DropdownMenuItem(value: _SortMode.confidence, child: Text('Confidence ↑')),
                ],
                onChanged: (v) => setState(() => _sortMode = v ?? _SortMode.original),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: matches.isEmpty
              ? const Center(child: Text('No matches at this confidence level'))
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final m = matches[i];
                    return _MatchedTile(match: m);
                  },
                ),
        ),
      ],
    );
  }

  // ─── Missing Tab ──────────────────────────────────────────────────────────

  Widget _buildMissingTab(ThemeData theme) {
    if (_comparison == null) {
      return const Center(child: Text('Run a comparison first'));
    }
    if (_comparison!.missing.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text('All playlist tracks are in the folder!',
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Action bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => widget.onDownloadMissing(_comparison!.missing, _selectedFormat),
                icon: const Icon(Icons.download, size: 18),
                label: Text('Download All (${_comparison!.missingCount})'),
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
          child: ListView.builder(
            itemCount: _comparison!.missing.length,
            itemBuilder: (context, i) {
              final t = _comparison!.missing[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.music_off, color: Colors.orange),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t.artist}  •  ${_formatDuration(t.duration)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.download, size: 20),
                  tooltip: 'Download this track',
                  onPressed: () => widget.onDownloadMissing([t], _selectedFormat),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Extras Tab ───────────────────────────────────────────────────────────

  Widget _buildExtrasTab(ThemeData theme) {
    if (_comparison == null) {
      return const Center(child: Text('Run a comparison first'));
    }
    if (_comparison!.extras.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('No extra files — folder matches the playlist perfectly',
                style: theme.textTheme.titleMedium),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.blue.shade300),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_comparison!.extraCount} files in the folder are not in the playlist',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _comparison!.extras.length,
            itemBuilder: (context, i) {
              final f = _comparison!.extras[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.audio_file, color: Colors.blue),
                title: Text(f.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(f.filePath, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }

  String _formatTotalDuration(List<SearchResult> tracks) {
    final total = tracks.fold<Duration>(
        Duration.zero, (sum, t) => sum + t.duration);
    if (total.inHours > 0) {
      return '${total.inHours}h ${total.inMinutes.remainder(60)}m';
    }
    return '${total.inMinutes}m';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helper widgets
// ═══════════════════════════════════════════════════════════════════════════════

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
