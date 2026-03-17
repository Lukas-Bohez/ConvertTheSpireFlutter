import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import '../models/search_result.dart';
import '../services/playlist_service.dart';
import '../services/yt_dlp_service.dart';

/// A small card used on the Home page for quickly pasting a URL and starting a download.
///
/// It fetches basic metadata for YouTube URLs and shows a preview before enqueueing.
class QuickDownloadCard extends StatefulWidget {
  final Future<void> Function(SearchResult result, String format, String quality)
      onDownload;

  const QuickDownloadCard({super.key, required this.onDownload});

  @override
  State<QuickDownloadCard> createState() => _QuickDownloadCardState();
}

class _QuickDownloadCardState extends State<QuickDownloadCard> {
  final _controller = TextEditingController();
  String _format = 'mp3';
  String _quality = 'best';
  bool _isLoading = false;

  Future<void> _doDownload() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final isYouTube = url.contains('youtube.com') || url.contains('youtu.be');
      final isPlaylist = url.contains('list=');
      if (isYouTube && isPlaylist) {
        // Playlist detected
        final yt = YoutubeExplode();
        final playlistService = PlaylistService(yt: yt);
        List<SearchResult> tracks = await playlistService.getYouTubePlaylistTracks(url);
        yt.close();
        if (!mounted) return;
        final selected = await showModalBottomSheet<List<SearchResult>>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) {
            // Ensure the modal sheet content is positioned above system UI (e.g., navigation bar)
            final mq = MediaQuery.of(ctx);
            return Padding(
              padding: EdgeInsets.only(
                bottom: mq.viewInsets.bottom + mq.padding.bottom,
              ),
              child: _PlaylistChecklistSheet(tracks: tracks),
            );
          },
        );
        if (selected != null && selected.isNotEmpty) {
          for (final track in selected) {
            await widget.onDownload(track, _format, _quality);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Queued ${selected.length} tracks for download')),
            );
            _controller.clear();
          }
        }
      } else {
        // Single video logic
        SearchResult result;
        if (isYouTube) {
          final yt = YoutubeExplode();
          try {
            final video = await yt.videos.get(url);
            result = SearchResult(
              id: video.id.value,
              title: video.title,
              artist: video.author,
              duration: video.duration ?? Duration.zero,
              thumbnailUrl: video.thumbnails.highResUrl,
              source: 'youtube',
            );
          } finally {
            yt.close();
          }
        } else {
          result = SearchResult(
            id: url,
            title: url,
            artist: '',
            duration: Duration.zero,
            thumbnailUrl: '',
            source: 'generic',
          );
        }
        if (!mounted) return;
        final confirmed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) {
            // Ensure the modal sheet content is positioned above system UI (e.g., navigation bar)
            final mq = MediaQuery.of(ctx);
            return Padding(
              padding: EdgeInsets.only(
                bottom: mq.viewInsets.bottom + mq.padding.bottom,
              ),
              child: _DownloadPreviewSheet(
                result: result,
                format: _format,
                quality: _quality,
              ),
            );
          },
        );
        if (confirmed == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Queued for download')),
            );
          }
          await widget.onDownload(result, _format, _quality);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download started')),
            );
            _controller.clear();
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not fetch video info.')), 
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 600;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick Download',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Paste URL',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  tooltip: 'Paste from clipboard',
                  onPressed: () async {
                    final clip = await Clipboard.getData('text/plain');
                    if (clip?.text != null) {
                      setState(() => _controller.text = clip!.text!);
                    }
                  },
                ),
              ),
              onSubmitted: (_) => _doDownload(),
            ),
            const SizedBox(height: 12),
            isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _format,
                              decoration: const InputDecoration(
                                labelText: 'Format',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                                DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                                DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _format = value);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _quality,
                              decoration: const InputDecoration(
                                labelText: 'Quality',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(value: '360p', child: Text('360p')),
                                DropdownMenuItem(value: '480p', child: Text('480p')),
                                DropdownMenuItem(value: '720p', child: Text('720p')),
                                DropdownMenuItem(value: '1080p', child: Text('1080p')),
                                DropdownMenuItem(value: '1440p', child: Text('1440p')),
                                DropdownMenuItem(value: '2160p', child: Text('2160p')),
                                DropdownMenuItem(value: '4320p', child: Text('4320p')),
                                DropdownMenuItem(value: 'best', child: Text('Best')),
                              ],
                              onChanged: (value) {
                                if (value != null) setState(() => _quality = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Download'),
                          onPressed: _isLoading ? null : _doDownload,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _format,
                          decoration: const InputDecoration(
                            labelText: 'Format',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                            DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                            DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _format = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _quality,
                          decoration: const InputDecoration(
                            labelText: 'Quality',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: '360p', child: Text('360p')),
                            DropdownMenuItem(value: '480p', child: Text('480p')),
                            DropdownMenuItem(value: '720p', child: Text('720p')),
                            DropdownMenuItem(value: '1080p', child: Text('1080p')),
                            DropdownMenuItem(value: '1440p', child: Text('1440p')),
                            DropdownMenuItem(value: '2160p', child: Text('2160p')),
                            DropdownMenuItem(value: '4320p', child: Text('4320p')),
                            DropdownMenuItem(value: 'best', child: Text('Best')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _quality = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Download'),
                          onPressed: _isLoading ? null : _doDownload,
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 8),
            Text(
              'Enter a video or playlist URL to preview it and add to the download queue.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// Playlist checklist modal
class _PlaylistChecklistSheet extends StatefulWidget {
  final List<SearchResult> tracks;
  const _PlaylistChecklistSheet({required this.tracks});

  @override
  State<_PlaylistChecklistSheet> createState() => _PlaylistChecklistSheetState();
}

class _PlaylistChecklistSheetState extends State<_PlaylistChecklistSheet> {
  late List<bool> _checked;

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(widget.tracks.length, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Select tracks to download', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: widget.tracks.length,
              itemBuilder: (ctx, i) {
                final track = widget.tracks[i];
                return CheckboxListTile(
                  value: _checked[i],
                  onChanged: (val) {
                    setState(() => _checked[i] = val ?? false);
                  },
                  title: Text(track.title),
                  subtitle: Text(track.artist),
                  secondary: track.thumbnailUrl.isNotEmpty
                      ? CircleAvatar(backgroundImage: NetworkImage(track.thumbnailUrl))
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              final selected = <SearchResult>[];
              for (int i = 0; i < widget.tracks.length; i++) {
                if (_checked[i]) selected.add(widget.tracks[i]);
              }
              Navigator.pop(context, selected);
            },
            child: const Text('Download Selected'),
          ),
        ],
      ),
    );
  }
}

class _DownloadPreviewSheet extends StatefulWidget {
  final SearchResult result;
  final String format;
  final String quality;

  const _DownloadPreviewSheet({
    required this.result,
    required this.format,
    required this.quality,
  });

  @override
  State<_DownloadPreviewSheet> createState() => _DownloadPreviewSheetState();
}

class _DownloadPreviewSheetState extends State<_DownloadPreviewSheet> {
  int? _estimatedSize;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchEstimatedSize();
  }

  Future<void> _fetchEstimatedSize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (Platform.isAndroid) {
        // yt-dlp/FFmpeg tooling is irrelevant on Android — skip size estimation.
        setState(() {
          _estimatedSize = null;
          _loading = false;
          _error = null;
        });
        return;
      }
      // You may need to adjust how you get ytDlpPath and ffmpegPath in your app context
      final ytDlpService = YtDlpService();
      final ytDlpPath = await ytDlpService.resolveAvailablePath(null);
      if (ytDlpPath == null) {
        // Don't surface "not available" on platforms where yt-dlp isn't relevant.
        setState(() {
          _estimatedSize = null;
          _loading = false;
          _error = null;
        });
        return;
      }
      final size = await ytDlpService.fetchEstimatedSize(
        url: widget.result.id,
        ytDlpPath: ytDlpPath,
        videoQuality: widget.quality,
      );
      setState(() {
        _estimatedSize = size;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not fetch size';
        _loading = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: widget.result.thumbnailUrl.isNotEmpty
                    ? NetworkImage(widget.result.thumbnailUrl)
                    : null,
                child: widget.result.thumbnailUrl.isEmpty
                    ? const Icon(Icons.photo, size: 28)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.result.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(widget.result.artist.isNotEmpty ? widget.result.artist : widget.result.source,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Format: ${widget.format}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('Quality: ${widget.quality}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          _loading
              ? const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Fetching estimated size...'),
                  ],
                )
              : _error != null
                  ? Text(_error!, style: TextStyle(color: cs.error))
                  : Text('Estimated size: ${_formatSize(_estimatedSize)}', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add to queue'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The download will be enqueued using your settings (quality, destination, etc.).',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
