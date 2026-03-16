import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import '../models/search_result.dart';

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
      // If it's a YouTube URL, fetch some metadata for a nice preview.
      final isYouTube = url.contains('youtube.com') || url.contains('youtu.be');
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
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
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
        await widget.onDownload(result, _format, _quality);
        if (mounted) {
          _controller.clear();
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
            Row(
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

class _DownloadPreviewSheet extends StatelessWidget {
  final SearchResult result;
  final String format;
  final String quality;

  const _DownloadPreviewSheet({
    required this.result,
    required this.format,
    required this.quality,
  });

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
                backgroundImage: result.thumbnailUrl.isNotEmpty
                    ? NetworkImage(result.thumbnailUrl)
                    : null,
                child: result.thumbnailUrl.isEmpty
                    ? const Icon(Icons.photo, size: 28)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(result.artist.isNotEmpty ? result.artist : result.source,
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
          Text('Format: $format', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text('Quality: $quality', style: Theme.of(context).textTheme.bodyMedium),
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
