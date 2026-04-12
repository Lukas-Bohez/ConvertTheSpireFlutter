import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      appBar: AppBar(title: const Text('Guide')),
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
                        'Vault The Spire',
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
                  'A fast, private BitTorrent client for downloading '
                  'freely distributed files - open-source software, '
                  'Creative Commons media, public domain content, and '
                  'files you own the rights to.',
                  style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: 14),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Chip(label: 'Open Source', icon: Icons.code_outlined),
                    _Chip(label: 'Privacy First', icon: Icons.lock_outline),
                    _Chip(label: 'No Ads', icon: Icons.block_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            icon: Icons.gavel_outlined,
            color: cs.error,
            title: 'Legal Use Only',
            body: 'Vault The Spire is designed exclusively for legal downloading. '
                'This includes:\n\n'
                '- Open-source software (Linux distros, development tools, games released freely)\n'
                '- Creative Commons licensed music, video, and books\n'
                '- Public domain content (old films, historical recordings, classic literature)\n'
                '- Files you own and have backed up yourself\n'
                '- Content explicitly shared by creators for free distribution\n\n'
                    'Downloading or sharing copyrighted material without permission '
                    'is illegal in most countries. The developers of this app do not '
                    'condone or support unauthorized copyright violations.',
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.rocket_launch_outlined,
            color: cs.primary,
            title: 'Getting Started',
            body: android
                ? 'Tap the + button to paste a magnet link, or open a .torrent '
                    'file from your Files app to begin a download.\n\n'
                    'Set your download folder in Settings before starting large '
                    'downloads to make sure files go where you expect.\n\n'
                    'Watch progress in the Torrents tab. Tap any torrent to see '
                    'detailed speed, peers, and size information.'
                : 'Drag a .torrent file onto the window, or paste a magnet link '
                    'using the + button in the Torrents tab.\n\n'
                    'Set your download folder in Settings. For large downloads, '
                    'choose a drive with plenty of free space.\n\n'
                    'The app continues downloading in the system tray when you '
                    'close the window - use the tray icon to monitor progress.',
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.bar_chart_outlined,
            color: cs.tertiary,
            title: 'Understanding Download Progress',
            body: 'Downloading: Pieces are being received from peers across the '
                'internet. Larger torrents (10 GB+) can take hours on a typical '
                'home connection.\n\n'
                'Stalled / Searching for peers: The app is looking for other '
                'users sharing this file. Rarer files may take longer to find peers. '
                'Try Force Refresh in the torrent details.\n\n'
                'Seeding: Download is complete. The app is sharing your copy with '
                'others - this is good for the community and is how BitTorrent works.\n\n'
                'Checking: After a redownload or app restart, pieces are being '
                'verified against their checksums. This ensures file integrity.',
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.fact_check_outlined,
            color: cs.secondary,
            title: 'Verifying & Redownloading',
            body: 'If a downloaded file seems corrupt or won\'t open, tap the '
                'torrent to open its detail view, then tap "Verify files". '
                'This re-reads every piece from disk and checks it against the '
                'original checksums - no data is deleted.\n\n'
                'If verification finds bad pieces, or if you want to start '
                'completely fresh, tap "Redownload". This deletes the local '
                'copy and downloads everything again from peers.\n\n'
                'Large repacks (multi-part installer archives) sometimes need a '
                'verify pass after completing because pieces can arrive out of '
                'order across many files.',
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.privacy_tip_outlined,
            color: cs.primary,
            title: 'Privacy & Your Data',
            body: 'Vault The Spire stores all data locally on your device. '
                'No torrent history, download statistics, or file names are '
                'sent to any server.\n\n'
                'Your IP address is visible to other peers in any torrent swarm '
                'you join - this is how BitTorrent works. A VPN will mask your '
                'IP if privacy from other peers is important to you.\n\n'
                'The built-in browser does not sync history to any cloud. '
                'History is stored only on-device and can be cleared in Settings.',
          ),
          const SizedBox(height: 10),
          _Section(
            icon: Icons.tips_and_updates_outlined,
            color: cs.tertiary,
            title: android ? 'Android Tips' : 'Desktop Tips',
            body: android
                ? '- Disable battery optimisation for Vault The Spire in Android '
                    'Settings -> Apps to prevent the OS from pausing active downloads.\n\n'
                    '- If a torrent shows "File already in use", close any other '
                    'app that has the file open, then tap Redownload.\n\n'
                    '- Pull down on the Torrents list to force a refresh if '
                    'progress looks frozen.\n\n'
                    '- For best results on Android 12+, grant the app storage '
                    'permission when prompted at first launch.'
                : '- The app keeps downloading when minimised to the system tray. '
                    'Right-click the tray icon to pause all or quit cleanly.\n\n'
                    '- If Windows shows a file as "in use" after a download '
                    'completes, wait a few seconds for the app to release the '
                    'write handle - it does this automatically on completion.\n\n'
                    '- Use the browser tab to find magnet links without leaving '
                    'the app. Detected magnets are highlighted automatically.\n\n'
                    '- For very large torrents (20 GB+), make sure your drive '
                    'has at least 10% free space beyond the download size.',
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
                        ? 'Pro tip: Seed ratio matters. Keeping a torrent '
                            'seeding after download helps other users get '
                            'the same file. A ratio of 1.0 means you\'ve '
                            'shared back as much as you downloaded.'
                        : 'Pro tip: The BitTorrent protocol is peer-to-peer - '
                            'every downloader also uploads to others. Leaving '
                            'seeding on after your download benefits the whole '
                            'community and keeps rare files alive.',
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
