import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utils/l10n.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final android = _isAndroid;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tabGuide)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [cs.primaryContainer, cs.tertiaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.download_for_offline_outlined,
                      color: cs.onPrimaryContainer,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.vaultSpire,
                        style: tt.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.fastPrivateBittorrentClientDownloading,
                  style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(label: context.l10n.openSource, icon: Icons.code_outlined),
                    _Chip(label: context.l10n.privacyFirst, icon: Icons.lock_outline),
                    _Chip(label: context.l10n.noAds, icon: Icons.block_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            icon: Icons.gavel_outlined,
            color: cs.error,
            title: context.l10n.legalUseOnly,
            body:
                context.l10n.vaultSpireDesignedExclusivelyLegal,
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.rocket_launch_outlined,
            color: cs.primary,
            title: context.l10n.gettingStarted,
            body: android
                ? context.l10n.tapButtonPasteMagnetLink
                : context.l10n.dragTorrentFileOntoWindow,
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.bar_chart_outlined,
            color: cs.tertiary,
            title: context.l10n.understandingDownloadProgress,
            body:
                context.l10n.downloadingPiecesBeingReceivedFrom,
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.fact_check_outlined,
            color: cs.secondary,
            title: context.l10n.verifyingRedownloading,
            body: context.l10n.ifDownloadedFileSeemsCorrupt,
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.privacy_tip_outlined,
            color: cs.primary,
            title: context.l10n.privacyData,
            body: context.l10n.vaultSpireStoresAllData,
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.tips_and_updates_outlined,
            color: cs.tertiary,
            title: android ? context.l10n.androidTips : context.l10n.desktopTips,
            body: android
                ? context.l10n.disableBatteryOptimisationVaultSpire
                : context.l10n.appKeepsDownloadingWhenMinimised,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    android
                        ? context.l10n.proTipSeedRatioMatters
                        : context.l10n.proTipBittorrentProtocolPeer,
                    style: tt.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Chip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.surface.withValues(alpha: 0.5),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurface),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Section extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, color: widget.color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Text(
                  widget.body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
