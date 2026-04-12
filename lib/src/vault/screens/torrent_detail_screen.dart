import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:convert_the_spire_reborn/src/vault/models/torrent.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

String _fmtDuration(Duration duration) {
  final total = duration.inSeconds;
  final mins = (total ~/ 60).toString().padLeft(2, '0');
  final secs = (total % 60).toString().padLeft(2, '0');
  return '$mins:$secs';
}

String _fmtLastEvent(DateTime? at) {
  if (at == null) return 'Never';
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 5) return 'Just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  return '${diff.inHours}h ago';
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _StatPill(
      {required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: children),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  final bool small;
  const _InfoRow(this.label, this.value,
      {this.mono = false, this.small = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant)),
            ),
            Expanded(
              child: SelectableText(
                value,
                style: TextStyle(
                    fontSize: small ? 11 : 13,
                    fontFamily: mono ? 'monospace' : null),
              ),
            ),
          ],
        ),
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TorrentDetailScreen extends StatefulWidget {
  final TorrentModel torrent;
  const TorrentDetailScreen({super.key, required this.torrent});

  @override
  State<TorrentDetailScreen> createState() =>
      _TorrentDetailScreenState();
}

class _TorrentDetailScreenState extends State<TorrentDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TorrentViewState?>(
      stream: TorrentService.instance
          .torrentStateStream(widget.torrent.id),
      builder: (context, snapshot) {
        final view = snapshot.data;
        final torrent = view?.model ?? widget.torrent;
        final statusLabel =
            view?.statusLabel ?? (torrent.status ?? 'Unknown');
        final retryCountdown =
          TorrentService.instance.metadataRetryRemaining(torrent.id);
        final lastAnnounce =
          TorrentEngineService.instance.lastAnnounceAt(torrent.id);
        final cs = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(torrent.name,
                overflow: TextOverflow.ellipsis),
            actions: [
              if (torrent.magnetLink != null)
                IconButton(
                  tooltip: 'Copy magnet link',
                  icon: const Icon(Icons.link),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: torrent.magnetLink!));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Magnet link copied')));
                  },
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16,
                Platform.isAndroid ? 32 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero progress card ───────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: Text(statusLabel,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimaryContainer)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (view?.isSeeding == true)
                        Text(
                          'Shared: ${_fmtBytes(view!.uploaded)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Speed / peers pills ──────────────────────────
                if (view != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatPill(
                        icon: Icons.arrow_downward,
                        value: '${_fmtBytes(view.downloadSpeed.round())}/s',
                        color: cs.primary,
                      ),
                      _StatPill(
                        icon: Icons.arrow_upward,
                        value: '${_fmtBytes(view.uploadSpeed.round())}/s',
                        color: cs.tertiary,
                      ),
                      _StatPill(
                        icon: Icons.people_outline,
                        value: '${view.peers} peers',
                        color: cs.secondary,
                      ),
                      if (view.seeders > 0)
                        _StatPill(
                          icon: Icons.cloud_upload_outlined,
                          value: '${view.seeders} seeds',
                          color: cs.tertiary,
                        ),
                    ],
                  ),
                const SizedBox(height: 16),

                // ── Action buttons ───────────────────────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Force refresh'),
                      onPressed: () async {
                        await TorrentEngineService.instance
                            .forceRefresh(torrent.id);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Connection refresh triggered')));
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.radar_outlined, size: 16),
                      label: const Text('Force reannounce'),
                      onPressed: () async {
                        try {
                          await TorrentEngineService.instance
                              .forceTrackerReannounce(torrent.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tracker reannounce triggered'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Reannounce failed: $e')),
                          );
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.hub_outlined, size: 16),
                      label: const Text('Force DHT refresh'),
                      onPressed: () async {
                        try {
                          await TorrentEngineService.instance
                              .forceDhtRefresh(torrent.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('DHT refresh triggered'),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('DHT refresh failed: $e')),
                          );
                        }
                      },
                    ),
                    if ((torrent.status ?? '').toLowerCase().contains(
                      'pending_metadata',
                    ))
                      OutlinedButton.icon(
                        icon: const Icon(Icons.replay_circle_filled_outlined, size: 16),
                        label: const Text('Retry metadata now'),
                        onPressed: () async {
                          await TorrentService.instance.retryMetadataNow(
                            torrent.id,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Metadata retry queued'),
                            ),
                          );
                        },
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Redownload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error),
                      ),
                      onPressed: () => _confirmRedownload(torrent),
                    ),
                    OutlinedButton.icon(
                      icon:
                          const Icon(Icons.content_copy, size: 16),
                      label: const Text('Copy logs'),
                      onPressed: () async {
                        final logs = TorrentEngineService.instance
                            .getLogs(torrent.id);
                        await Clipboard.setData(
                            ClipboardData(text: logs.join('\n')));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Logs copied to clipboard')));
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: const Text('Verify files'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(const SnackBar(
                            content: Text(
                                'Verifying files on disk  -  this may take a moment…')));
                        try {
                          await TorrentEngineService.instance
                              .forceStateRecovery(torrent.id);
                          if (!mounted) return;
                          messenger.showSnackBar(const SnackBar(
                              content: Text('Verification complete.')));
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(SnackBar(
                              content: Text('Verify failed: $e')));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Info table ───────────────────────────────────
                _InfoCard(children: [
                  _InfoRow('Status', statusLabel),
                  _InfoRow(
                    'Type',
                    torrent.type == 'magnet_link'
                        ? 'Magnet link'
                        : 'Torrent file',
                  ),
                  _InfoRow('Total size',
                      _fmtBytes(torrent.totalSize ?? 0)),
                  _InfoRow(
                    'Uploaded',
                    _fmtBytes(view?.uploaded ?? torrent.bytesUp),
                  ),
                  if (torrent.totalPieces != null &&
                      torrent.totalPieces! > 0)
                    _InfoRow(
                      'Pieces',
                      '${torrent.havePieces} / ${torrent.totalPieces}',
                    ),
                  if (view != null) ...[
                    _InfoRow(
                      'Seeders',
                      '${view.seeders} '
                          '(DHT: ${view.dhtNodes}, '
                          'Tracker: ${view.trackers})',
                    ),
                    _InfoRow('Leechers', '${view.leechers}'),
                    if (view.connectionMessage.isNotEmpty)
                      _InfoRow(
                          'Connection', view.connectionMessage),
                    _InfoRow('Last announce', _fmtLastEvent(lastAnnounce)),
                    _InfoRow(
                      'Metadata retry',
                      retryCountdown == null
                          ? 'n/a'
                          : _fmtDuration(retryCountdown),
                    ),
                  ],
                  if (torrent.filePath != null &&
                      torrent.filePath!.isNotEmpty)
                    _InfoRow('Save path', torrent.filePath!),
                  _InfoRow('Info hash', torrent.id,
                      mono: true, small: true),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmRedownload(TorrentModel torrent) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redownload from scratch?'),
        content: Text(
          '"${torrent.name}" will be deleted from disk and downloaded '
          'again from 0%. The .torrent source file is kept.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Redownload')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TorrentEngineService.instance
          .forceRedownload(torrent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Redownload started')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}