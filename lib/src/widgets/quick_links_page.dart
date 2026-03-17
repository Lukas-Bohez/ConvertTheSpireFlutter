import 'dart:io';
import 'package:flutter/material.dart';

import '../models/search_result.dart';
import 'quick_download_card.dart';
import 'quick_links_service.dart';

/// Clean home page with a grid of quick-link tiles.
class QuickLinksPage extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final Future<void> Function(
      SearchResult result, String format, String quality) onDownload;
  final Future<String?> Function() getYtDlpVersion;

  const QuickLinksPage({
    super.key,
    required this.onNavigate,
    required this.onDownload,
    required this.getYtDlpVersion,
  });

  @override
  State<QuickLinksPage> createState() => _QuickLinksPageState();
}

class _QuickLinksPageState extends State<QuickLinksPage> {
  List<QuickLink> _links = [];
  String? _ytDlpVersion;
  bool _ytDlpChecking = true;
  bool _ytDlpFailed = false;

  @override
  void initState() {
    super.initState();
    _loadLinks();
    _checkYtDlpVersion();
  }

  Future<void> _loadLinks() async {
    final links = await QuickLinksService.load();
    if (mounted) setState(() => _links = links);
  }

  Future<void> _checkYtDlpVersion() async {
    setState(() {
      _ytDlpChecking = true;
      _ytDlpFailed = false;
    });
    try {
      final v = await widget.getYtDlpVersion();
      if (mounted) {
        setState(() {
          _ytDlpVersion = v;
          _ytDlpFailed = v == null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ytDlpFailed = true);
    } finally {
      if (mounted) setState(() => _ytDlpChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 500 ? 2 : (width < 900 ? 3 : 4);

    // Filter out only the queue tile (always in sidebar).
    // Browser remains available so users can tap it directly.
    final visibleLinks = _links.where((l) => l.route != 'queue.tab').toList();

    return Container(
      color: cs.surfaceContainerLowest,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HomeHeaderDelegate(
              minExtent: 160,
              maxExtent: 380,
              persistentHeight: 160,
              expanded: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: width < 600 ? 20 : 56,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 28),
                    // App branding (fades away when collapsed)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  cs.primary.withValues(alpha: 0.15),
                                  cs.tertiary.withValues(alpha: 0.10),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(Icons.music_note_rounded,
                                size: 56, color: cs.primary),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Convert the Spire',
                            style:
                                Theme.of(context).textTheme.headlineLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: cs.onSurface,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Paste a video or playlist URL below to start downloading.',
                            style: TextStyle(
                              fontSize: 18,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              pinned: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: width < 600 ? 20 : 56,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QuickDownloadCard(onDownload: widget.onDownload),
                    const SizedBox(height: 12),
                    if (!Platform.isAndroid)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.memory,
                            size: 18,
                            color: _ytDlpFailed
                                ? Colors.redAccent
                                : (_ytDlpChecking ? Colors.amber : Colors.green),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _ytDlpChecking
                                ? 'Checking engine...'
                                : _ytDlpFailed
                                    ? 'yt-dlp not available (click Settings)'
                                    : 'yt-dlp ${_ytDlpVersion ?? 'unknown'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 12),
                          if (_ytDlpFailed)
                            TextButton(
                              onPressed: _checkYtDlpVersion,
                              child: const Text('Retry'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            sliver: _buildLinksGrid(crossAxisCount, visibleLinks),
          ),
        ],
      ),
    );
  }

  Widget _buildLinksGrid(int crossAxisCount, List<QuickLink> visibleLinks) {
    final cs = Theme.of(context).colorScheme;

    if (_links.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music, size: 64, color: cs.outline),
              const SizedBox(height: 12),
              Text('No media yet', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _loadLinks, child: const Text('Scan library')),
            ],
          ),
        ),
      );
    }

    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (ctx, i) {
          final link = visibleLinks[i];
          return _QuickLinkTile(
            link: link,
            onTap: () {
              FocusScope.of(context).unfocus();
              widget.onNavigate(link.route);
            },
          );
        },
        childCount: visibleLinks.length,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
    );
  }
}

class _QuickLinkTile extends StatefulWidget {
  final QuickLink link;
  final VoidCallback onTap;

  const _QuickLinkTile({required this.link, required this.onTap});

  @override
  State<_QuickLinkTile> createState() => _QuickLinkTileState();
}

class _QuickLinkTileState extends State<_QuickLinkTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _hovering
              ? cs.primaryContainer.withValues(alpha: 0.35)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering
                ? cs.primary.withValues(alpha: 0.3)
                : cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.link.icon, color: cs.primary, size: 36),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.link.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.link.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.link.description,
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double _minExtent;
  final double _maxExtent;
  final double _persistentHeight;
  final Widget expanded;
  final Widget pinned;

  _HomeHeaderDelegate({
    required double minExtent,
    required double maxExtent,
    required double persistentHeight,
    required this.expanded,
    required this.pinned,
  })  : _minExtent = minExtent,
        _maxExtent = maxExtent,
        _persistentHeight = persistentHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (_maxExtent - _minExtent)).clamp(0.0, 1.0);
    final height = (_maxExtent - shrinkOffset).clamp(_persistentHeight, _maxExtent);

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The expanded content shrinks smoothly by adjusting its height factor.
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1.0 - t,
              child: expanded,
            ),
          ),
          // Pin the search/card area to the bottom so it never scrolls away.
          Align(
            alignment: Alignment.bottomCenter,
            child: pinned,
          ),
        ],
      ),
    );
  }

  @override
  double get maxExtent => _maxExtent;

  @override
  double get minExtent => _minExtent;

  @override
  bool shouldRebuild(covariant _HomeHeaderDelegate oldDelegate) {
    return minExtent != oldDelegate.minExtent ||
        maxExtent != oldDelegate.maxExtent ||
        _persistentHeight != oldDelegate._persistentHeight ||
        expanded != oldDelegate.expanded ||
        pinned != oldDelegate.pinned;
  }
}
