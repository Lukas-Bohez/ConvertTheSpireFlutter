import 'package:flutter/material.dart';

import '../models/search_result.dart';
import 'quick_download_card.dart';
import 'quick_links_service.dart';
import 'm3_home_grid.dart';

/// Clean home page with a grid of quick-link tiles.
class QuickLinksPage extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final Future<void> Function(SearchResult result, String format, String quality)
      onDownload;

  const QuickLinksPage({
    super.key,
    required this.onNavigate,
    required this.onDownload,
  });

  @override
  State<QuickLinksPage> createState() => _QuickLinksPageState();
}

class _QuickLinksPageState extends State<QuickLinksPage> {
  List<QuickLink> _links = [];

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final links = await QuickLinksService.load();
    if (mounted) setState(() => _links = links);
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
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 20 : 56,
          vertical: 24,
        ),
        children: [
          const SizedBox(height: 28),
          // App branding + quick download
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
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
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

          // Quick URL download input
          QuickDownloadCard(onDownload: widget.onDownload),
          const SizedBox(height: 24),

          // Quick links grid
          SizedBox(
            height: (crossAxisCount * 140).toDouble(),
            child: M3HomeGrid<QuickLink>(
              loading: _links.isEmpty,
              items: visibleLinks,
              onRetry: _loadLinks,
              itemBuilder: (ctx, link) {
                return _QuickLinkTile(
                  link: link,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    widget.onNavigate(link.route);
                  },
                );
              },
            ),
          ),
        ],
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
