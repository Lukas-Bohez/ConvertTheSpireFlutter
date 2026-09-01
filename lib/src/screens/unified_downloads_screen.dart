import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/unified_download_task.dart';
import '../services/unified_download_service.dart';
import '../widgets/delete_download_dialog.dart';
import '../widgets/download_filter_toolbar.dart';

/// TrackSpire Downloads — one dashboard for BitTorrent transfers and
/// direct-HTTP downloads (APKs, archives, browser-detected media links).
///
/// No Android TV-specific code in this file on purpose: GlobalCursorOverlay
/// (lib/src/widgets/global_cursor_overlay.dart) wraps the whole app in
/// lib/src/app.dart and already drives D-pad input into any screen built
/// from ordinary Material widgets — Card, ListView, IconButton, FilterChip
/// all just work. Nothing here needs FocusTraversalGroup or a custom focus
/// visualizer on top of that.
///
/// Discoverability idea, not required to ship: lib/src/utils/browser_submission.dart
/// already resolves typed address-bar shortcuts like route names via
/// `routeToIndex`. Adding "downloads" as one more entry would let a user
/// jump here just by typing it in the browser's own address bar.
class UnifiedDownloadsScreen extends StatefulWidget {
  const UnifiedDownloadsScreen({super.key});

  @override
  State<UnifiedDownloadsScreen> createState() => _UnifiedDownloadsScreenState();
}

class _UnifiedDownloadsScreenState extends State<UnifiedDownloadsScreen> {
  DownloadProtocolFilter _protocol = DownloadProtocolFilter.all;
  DownloadStatusFilter _status = DownloadStatusFilter.all;
  UnifiedDownloadCategory? _category;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final service = context.watch<UnifiedDownloadService>();
    final filtered = _applyFilters(service.tasks);

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: Column(
        children: [
          DownloadFilterToolbar(
            protocol: _protocol,
            status: _status,
            category: _category,
            query: _query,
            onProtocolChanged: (v) => setState(() => _protocol = v),
            onStatusChanged: (v) => setState(() => _status = v),
            onCategoryChanged: (v) => setState(() => _category = v),
            onQueryChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final task = filtered[index];
                      return _DownloadItemCard(
                        task: task,
                        onPause: () => service.pause(task.id),
                        onResume: () => service.resume(task.id),
                        onCancel: () => service.cancel(task.id),
                        onRetry: () => service.retry(task.id),
                        onRemove: () => service.removeEntry(task.id),
                        onDeleteFile: () => _confirmAndDelete(context, service, task),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<UnifiedDownloadTask> _applyFilters(List<UnifiedDownloadTask> all) {
    return all.where((t) {
      if (_protocol == DownloadProtocolFilter.torrents &&
          t.type != UnifiedDownloadType.torrent) {
        return false;
      }
      if (_protocol == DownloadProtocolFilter.directHttp &&
          t.type != UnifiedDownloadType.directHttp) {
        return false;
      }
      if (_status == DownloadStatusFilter.active && !t.isActive) return false;
      if (_status == DownloadStatusFilter.paused &&
          t.status != UnifiedDownloadStatus.paused) {
        return false;
      }
      if (_status == DownloadStatusFilter.completed &&
          t.status != UnifiedDownloadStatus.completed) {
        return false;
      }
      if (_category != null && t.category != _category) return false;
      if (_query.trim().isNotEmpty &&
          !t.title.toLowerCase().contains(_query.trim().toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    UnifiedDownloadService service,
    UnifiedDownloadTask task,
  ) async {
    final confirmed = await showDeleteDownloadDialog(context, task);
    if (confirmed == true) {
      await service.deleteFile(task.id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No downloads yet',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

class _DownloadItemCard extends StatelessWidget {
  final UnifiedDownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final VoidCallback onDeleteFile;

  const _DownloadItemCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
    required this.onDeleteFile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ProtocolBadge(type: task.type),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (task.status == UnifiedDownloadStatus.downloading ||
                task.status == UnifiedDownloadStatus.paused)
              LinearProgressIndicator(value: task.totalBytes > 0 ? task.progress : null),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  _statusLabel(task),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const Spacer(),
                ..._actionsFor(task),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(UnifiedDownloadTask t) {
    switch (t.status) {
      case UnifiedDownloadStatus.queued:
        return 'Queued';
      case UnifiedDownloadStatus.downloading:
        final pct = t.totalBytes > 0 ? '${(t.progress * 100).toStringAsFixed(0)}% · ' : '';
        return '$pct${_formatSpeed(t.downloadSpeedBytesPerSec)}';
      case UnifiedDownloadStatus.paused:
        return 'Paused · ${_formatBytes(t.bytesDownloaded)}';
      case UnifiedDownloadStatus.completed:
        return 'Completed';
      case UnifiedDownloadStatus.failed:
        return t.errorMessage ?? 'Failed';
      case UnifiedDownloadStatus.canceled:
        return 'Canceled';
    }
  }

  List<Widget> _actionsFor(UnifiedDownloadTask t) {
    switch (t.status) {
      case UnifiedDownloadStatus.downloading:
        return [
          IconButton(icon: const Icon(Icons.pause), tooltip: 'Pause', onPressed: onPause),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: onCancel),
        ];
      case UnifiedDownloadStatus.queued:
        return [
          IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: onCancel),
        ];
      case UnifiedDownloadStatus.paused:
        return [
          IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Resume', onPressed: onResume),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Cancel', onPressed: onCancel),
        ];
      case UnifiedDownloadStatus.failed:
        return [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Retry', onPressed: onRetry),
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove', onPressed: onRemove),
        ];
      case UnifiedDownloadStatus.canceled:
        return [
          IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove', onPressed: onRemove),
        ];
      case UnifiedDownloadStatus.completed:
        return [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete file…',
            onPressed: onDeleteFile,
          ),
        ];
    }
  }
}

class _ProtocolBadge extends StatelessWidget {
  final UnifiedDownloadType type;
  const _ProtocolBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = type == UnifiedDownloadType.torrent ? 'TORRENT' : 'HTTP';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSecondaryContainer),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatSpeed(int bytesPerSec) => '${_formatBytes(bytesPerSec)}/s';
