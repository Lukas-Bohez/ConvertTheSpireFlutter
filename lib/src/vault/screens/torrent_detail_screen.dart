import 'dart:io';

import 'package:convert_the_spire_reborn/src/utils/l10n.dart';
import 'package:convert_the_spire_reborn/src/vault/models/torrent.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/torrent_status_text.dart';

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

String _fmtLastEvent(BuildContext context, DateTime? at) {
  if (at == null) return context.l10n.never;
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 5) return context.l10n.justNow;
  if (diff.inMinutes < 1) return context.l10n.sAgo(diff.inSeconds);
  if (diff.inHours < 1) return context.l10n.mAgo(diff.inMinutes);
  return context.l10n.hAgo(diff.inHours);
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _StatPill(
      {required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
  State<TorrentDetailScreen> createState() => _TorrentDetailScreenState();
}

class _TorrentDetailScreenState extends State<TorrentDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TorrentViewState?>(
      stream: TorrentService.instance.torrentStateStream(widget.torrent.id),
      builder: (context, snapshot) {
        final view = snapshot.data;
        final torrent = view?.model ?? widget.torrent;
        final statusLabel = view == null
            ? (torrent.status ?? context.l10n.unknown)
            : localizedTorrentStatus(context, view.statusLabel);
        final retryCountdown =
            TorrentService.instance.metadataRetryRemaining(torrent.id);
        final lastAnnounce =
            TorrentEngineService.instance.lastAnnounceAt(torrent.id);
        final cs = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: Text(torrent.name, overflow: TextOverflow.ellipsis),
            actions: [
              if (torrent.magnetLink != null)
                IconButton(
                  tooltip: context.l10n.copyMagnetLink,
                  icon: const Icon(Icons.link),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: torrent.magnetLink!));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.magnetLinkCopied)));
                  },
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding:
                EdgeInsets.fromLTRB(16, 16, 16, Platform.isAndroid ? 32 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero progress card ───────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
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
                          context.l10n.shared(_fmtBytes(view!.uploaded)),
                          style: Theme.of(context).textTheme.bodySmall,
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
                    // Same variant as its siblings (Force reannounce, Force
                    // DHT refresh, …) — these are conceptually parallel
                    // actions and previously used a tonal FilledButton,
                    // which rendered with a different emphasis/color.
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(context.l10n.forceRefresh),
                      onPressed: () async {
                        await TorrentEngineService.instance
                            .forceRefresh(torrent.id);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(context.l10n.connectionRefreshTriggered)));
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.radar_outlined, size: 16),
                      label: Text(context.l10n.forceReannounce),
                      onPressed: () async {
                        try {
                          await TorrentEngineService.instance
                              .forceTrackerReannounce(torrent.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.trackerReannounceTriggered),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.l10n.reannounceFailed(e))),
                          );
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.hub_outlined, size: 16),
                      label: Text(context.l10n.forceDhtRefresh),
                      onPressed: () async {
                        try {
                          await TorrentEngineService.instance
                              .forceDhtRefresh(torrent.id);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.dhtRefreshTriggered),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.l10n.dhtRefreshFailed(e))),
                          );
                        }
                      },
                    ),
                    if ((torrent.status ?? '').toLowerCase().contains(
                          'pending_metadata',
                        ))
                      OutlinedButton.icon(
                        icon: const Icon(Icons.replay_circle_filled_outlined,
                            size: 16),
                        label: Text(context.l10n.retryMetadataNow),
                        onPressed: () async {
                          await TorrentService.instance.retryMetadataNow(
                            torrent.id,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(context.l10n.metadataRetryQueued),
                            ),
                          );
                        },
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.replay, size: 16),
                      label: Text(context.l10n.redownload),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error),
                      ),
                      onPressed: () => _confirmRedownload(torrent),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.content_copy, size: 16),
                      label: Text(context.l10n.copyLogs),
                      onPressed: () async {
                        final logs =
                            TorrentEngineService.instance.getLogs(torrent.id);
                        await Clipboard.setData(
                            ClipboardData(text: logs.join('\n')));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(context.l10n.logsCopiedClipboard)));
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: Text(context.l10n.verifyFiles),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.showSnackBar(SnackBar(
                            content: Text(
                                context.l10n.verifyingFilesDiskMayTake)));
                        try {
                          await TorrentEngineService.instance
                              .forceStateRecovery(torrent.id);
                          if (!mounted) return;
                          messenger.showSnackBar(SnackBar(
                              content: Text(context.l10n.verificationComplete)));
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                              SnackBar(content: Text(context.l10n.verifyFailed(e))));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Info table ───────────────────────────────────
                _InfoCard(children: [
                  _InfoRow(context.l10n.status, statusLabel),
                  _InfoRow(
                    context.l10n.typeLabel,
                    torrent.type == 'magnet_link'
                        ? context.l10n.magnetLink
                        : context.l10n.torrentFile,
                  ),
                  _InfoRow(context.l10n.totalSize2, _fmtBytes(torrent.totalSize ?? 0)),
                  _InfoRow(
                    context.l10n.uploaded,
                    _fmtBytes(view?.uploaded ?? torrent.bytesUp),
                  ),
                  if (torrent.totalPieces != null && torrent.totalPieces! > 0)
                    _InfoRow(
                      context.l10n.pieces,
                      '${torrent.havePieces} / ${torrent.totalPieces}',
                    ),
                  if (view != null) ...[
                    _InfoRow(
                      context.l10n.seeders,
                      context.l10n.dhtTracker(view.seeders, view.dhtNodes, view.trackers),
                    ),
                    _InfoRow(context.l10n.leechers, '${view.leechers}'),
                    if (view.connectionMessage.isNotEmpty)
                      _InfoRow(context.l10n.connection, view.connectionMessage),
                    _InfoRow(context.l10n.lastAnnounce, _fmtLastEvent(context, lastAnnounce)),
                    _InfoRow(
                      context.l10n.metadataRetry,
                      retryCountdown == null
                          ? 'n/a'
                          : _fmtDuration(retryCountdown),
                    ),
                  ],
                  if (torrent.filePath != null && torrent.filePath!.isNotEmpty)
                    _InfoRow(context.l10n.savePath, torrent.filePath!),
                  _InfoRow(context.l10n.infoHash, torrent.id, mono: true, small: true),
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
        title: Text(context.l10n.redownloadFromScratch),
        // overflow-fix: dynamic torrent names can overflow dialog text layout.
        content: SingleChildScrollView(
          child: Text(
            context.l10n.willDeletedFromDiskDownloaded(torrent.name),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.actionCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.redownload)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TorrentEngineService.instance.forceRedownload(torrent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.redownloadStarted)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.failed2(e))));
    }
  }
}
