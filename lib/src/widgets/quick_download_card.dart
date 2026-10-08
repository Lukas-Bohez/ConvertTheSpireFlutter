import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import '../models/media_part.dart';
import '../models/search_result.dart';
import '../services/playlist_service.dart';
import '../services/yt_dlp_service.dart';
import '../utils/l10n.dart';
import '../utils/youtube_link.dart';
import 'video_or_playlist_dialog.dart';

/// A small card used on the Home page for quickly pasting a URL and starting a download.
///
/// It fetches basic metadata for YouTube URLs and shows a preview before enqueueing.
/// Queues [result] for download: all of it, or only [parts] of it.
typedef QuickDownloadCallback = Future<void> Function(
    SearchResult result, String format, String quality,
    {List<MediaPart> parts});

class QuickDownloadCard extends StatefulWidget {
  final QuickDownloadCallback onDownload;
  final void Function(String url, String format, String quality)?
      onPlaylistDetected;

  const QuickDownloadCard({
    super.key,
    required this.onDownload,
    this.onPlaylistDetected,
  });

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
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pasteUrlFirst)),
      );
      return;
    }

    final link = YouTubeLink.parse(url);
    final isYouTube = link != null;
    var isPlaylist = link?.hasDownloadablePlaylist ?? false;
    if (link != null && link.isVideoInPlaylist) {
      // A link copied while a playlist plays carries both; ask which one.
      final choice = await askVideoOrPlaylist(context);
      if (choice == null || !mounted) return;
      isPlaylist = choice == VideoOrPlaylist.playlist;
    }

    setState(() => _isLoading = true);
    try {
      if (isYouTube && isPlaylist) {
        // Playlist detected - redirect to Playlist Manager if callback is set
        final cb = widget.onPlaylistDetected;
        if (cb != null) {
          cb(link.playlistUrl, _format, _quality);
          if (mounted) {
            _controller.clear();
          }
          return;
        }
        // Fallback: legacy checklist sheet (no callback wired)
        final yt = YoutubeExplode();
        final playlistService = PlaylistService(yt: yt);
        final List<SearchResult> tracks =
            await playlistService.getYouTubePlaylistTracks(link.playlistUrl);
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
              SnackBar(
                  content:
                      Text(context.l10n.queuedTracksDownload(selected.length))),
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
            final video = await yt.videos.get(link.videoId ?? url);
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
        final choice = await showModalBottomSheet<List<MediaPart>>(
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
        // Null when closed; empty for all of it; or the parts to download.
        if (choice != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.queuedDownload)),
            );
          }
          await widget.onDownload(result, _format, _quality, parts: choice);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.downloadStarted)),
            );
            _controller.clear();
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotFetchVideoInfo)),
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
            Text(context.l10n.quickDownload,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      labelText: context.l10n.pasteUrl,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.link),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: context.l10n.pasteFromClipboard,
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
                ),
              ],
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
                              // Lets the choice shrink to the half-width slot on a phone.
                              isExpanded: true,
                              initialValue: _format,
                              decoration: InputDecoration(
                                labelText: context.l10n.format2,
                                border: const OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'mp3', child: Text('MP3')),
                                DropdownMenuItem(
                                    value: 'm4a', child: Text('M4A')),
                                DropdownMenuItem(
                                    value: 'mp4', child: Text('MP4')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _format = value);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _quality,
                              decoration: InputDecoration(
                                labelText: context.l10n.quality,
                                border: const OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                    value: '360p', child: Text('360p')),
                                const DropdownMenuItem(
                                    value: '480p', child: Text('480p')),
                                const DropdownMenuItem(
                                    value: '720p', child: Text('720p')),
                                const DropdownMenuItem(
                                    value: '1080p', child: Text('1080p')),
                                const DropdownMenuItem(
                                    value: '1440p', child: Text('1440p')),
                                const DropdownMenuItem(
                                    value: '2160p', child: Text('2160p')),
                                const DropdownMenuItem(
                                    value: '4320p', child: Text('4320p')),
                                DropdownMenuItem(
                                    value: 'best', child: Text(context.l10n.best)),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _quality = value);
                                }
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: Text(context.l10n.actionDownload),
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
                          isExpanded: true,
                          initialValue: _format,
                          decoration: InputDecoration(
                            labelText: context.l10n.format2,
                            border: const OutlineInputBorder(),
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
                          isExpanded: true,
                          initialValue: _quality,
                          decoration: InputDecoration(
                            labelText: context.l10n.quality,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: '360p', child: Text('360p')),
                            const DropdownMenuItem(
                                value: '480p', child: Text('480p')),
                            const DropdownMenuItem(
                                value: '720p', child: Text('720p')),
                            const DropdownMenuItem(
                                value: '1080p', child: Text('1080p')),
                            const DropdownMenuItem(
                                value: '1440p', child: Text('1440p')),
                            const DropdownMenuItem(
                                value: '2160p', child: Text('2160p')),
                            const DropdownMenuItem(
                                value: '4320p', child: Text('4320p')),
                            DropdownMenuItem(
                                value: 'best', child: Text(context.l10n.best)),
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
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.download),
                          label: Text(context.l10n.actionDownload),
                          onPressed: _isLoading ? null : _doDownload,
                        ),
                      ),
                    ],
                  ),
            const SizedBox(height: 8),
            Text(
              context.l10n.enterVideoPlaylistUrlPreview,
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
  State<_PlaylistChecklistSheet> createState() =>
      _PlaylistChecklistSheetState();
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
          Text(context.l10n.selectTracksDownload,
              style: Theme.of(context).textTheme.titleMedium),
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
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            track.thumbnailUrl,
                            width: 56,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.music_video,
                              size: 28,
                            ),
                          ),
                        )
                      : const Icon(Icons.music_video, size: 28),
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
            child: Text(context.l10n.downloadSelected2),
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

  /// Only parts of it (issue #41), as competitors offer.
  bool _partsOnly = false;
  final List<MediaPart> _parts = [];

  Duration get _duration => widget.result.duration;

  bool get _partsValid =>
      _parts.isNotEmpty &&
      _parts.every((p) => p.isValid && p.end <= _duration);

  void _addPart() {
    // After the last one, or the first 30 seconds.
    final from = _parts.isEmpty ? Duration.zero : _parts.last.end;
    var to = from + const Duration(seconds: 30);
    if (to > _duration) to = _duration;
    setState(() => _parts.add(MediaPart(
        from >= _duration ? Duration.zero : from,
        from >= _duration ? _duration : to)));
  }

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
        // yt-dlp/FFmpeg tooling is irrelevant on Android - skip size estimation.
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
        _error = context.l10n.couldNotFetchSize;
        _loading = false;
      });
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return context.l10n.unknown;
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
    final canCut = _duration > const Duration(seconds: 1);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: widget.result.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        widget.result.thumbnailUrl,
                        width: 56,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 40,
                          color: cs.surfaceContainerHighest,
                          child: const Icon(Icons.photo, size: 28),
                        ),
                      )
                    : Container(
                        width: 56,
                        height: 40,
                        color: cs.surfaceContainerHighest,
                        child: const Icon(Icons.photo, size: 28),
                      ),
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
                    Text(
                        widget.result.artist.isNotEmpty
                            ? widget.result.artist
                            : widget.result.source,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(context.l10n.format3(widget.format),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(context.l10n.quality2(widget.quality),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          _loading
              ? Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(context.l10n.fetchingEstimatedSize),
                  ],
                )
              : _error != null
                  ? Text(_error!, style: TextStyle(color: cs.error))
                  : Text(context.l10n.estimatedSize(_formatSize(_estimatedSize)),
                      style: Theme.of(context).textTheme.bodyMedium),
          if (canCut) ...[
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.movie_outlined),
                    label: Text(context.l10n.downloadWhole)),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.content_cut_rounded),
                    label: Text(context.l10n.downloadOnlyParts)),
              ],
              selected: {_partsOnly},
              onSelectionChanged: (v) {
                setState(() => _partsOnly = v.first);
                if (_partsOnly && _parts.isEmpty) _addPart();
              },
            ),
          ],
          if (_partsOnly) ...[
            const SizedBox(height: 8),
            Text(context.l10n.downloadPartsHint,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            for (var i = 0; i < _parts.length; i++)
              _PartEditor(
                key: ObjectKey(_parts[i]),
                part: _parts[i],
                duration: _duration,
                onChanged: (p) => setState(() => _parts[i] = p),
                onRemove: _parts.length > 1
                    ? () => setState(() => _parts.removeAt(i))
                    : null,
              ),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.downloadAddPart),
              onPressed: _addPart,
            ),
            if (!_partsValid)
              Text(context.l10n.partTimesInvalid,
                  style: TextStyle(color: cs.error, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _partsOnly && !_partsValid
                  ? null
                  : () => Navigator.pop(
                      context, _partsOnly ? List.of(_parts) : <MediaPart>[]),
              child: Text(_partsOnly
                  ? context.l10n.addPartsToQueue(_parts.length)
                  : context.l10n.addQueue),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.downloadWillEnqueuedUsingSettings,
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

/// One part to download: from and to, typed (`1:05`) or dragged.
class _PartEditor extends StatefulWidget {
  const _PartEditor({
    super.key,
    required this.part,
    required this.duration,
    required this.onChanged,
    this.onRemove,
  });

  final MediaPart part;
  final Duration duration;
  final ValueChanged<MediaPart> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_PartEditor> createState() => _PartEditorState();
}

class _PartEditorState extends State<_PartEditor> {
  late final _from =
      TextEditingController(text: MediaPart.formatTime(widget.part.start));
  late final _to =
      TextEditingController(text: MediaPart.formatTime(widget.part.end));
  late MediaPart _part = widget.part;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _typed() {
    final from = MediaPart.parseTime(_from.text);
    final to = MediaPart.parseTime(_to.text);
    if (from == null || to == null) return;
    _part = MediaPart(from, to);
    widget.onChanged(_part);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final max = widget.duration.inMilliseconds / 1000;
    double sec(Duration d) => (d.inMilliseconds / 1000).clamp(0, max);
    Widget field(TextEditingController c, String label) => SizedBox(
          width: 92,
          child: TextField(
            controller: c,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _typed(),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          Row(
            children: [
              field(_from, l10n.partFrom),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('–'),
              ),
              field(_to, l10n.partTo),
              const Spacer(),
              if (widget.onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: l10n.loopDeletePart,
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          RangeSlider(
            values: RangeValues(sec(_part.start), sec(_part.end)),
            max: max,
            onChanged: (v) {
              _part = MediaPart(Duration(milliseconds: (v.start * 1000).round()),
                  Duration(milliseconds: (v.end * 1000).round()));
              _from.text = MediaPart.formatTime(_part.start);
              _to.text = MediaPart.formatTime(_part.end);
              widget.onChanged(_part);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
