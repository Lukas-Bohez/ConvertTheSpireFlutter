import 'package:flutter/material.dart';

import 'quick_links_service.dart';

/// Clean home page with a grid of quick-link tiles.
class QuickLinksPage extends StatefulWidget {
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onSearch;

  const QuickLinksPage({
    super.key,
    required this.onNavigate,
    required this.onSearch,
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
    final crossAxisCount = width < 500 ? 3 : (width < 900 ? 4 : 5);

    return Container(
      color: cs.surfaceContainerLowest,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 16 : 48,
          vertical: 24,
        ),
        children: [
          const SizedBox(height: 32),
          // App branding
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.tertiary.withValues(alpha: 0.10),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.music_note_rounded,
                      size: 40, color: cs.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  'Convert the Spire',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: cs.onSurface,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Use the address bar above to navigate or enter a URL',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          // Quick links grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemCount: _links.length,
            itemBuilder: (context, index) {
              final link = _links[index];
              return _QuickLinkTile(
                link: link,
                onTap: () => widget.onNavigate(link.route),
              );
            },
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
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.link.icon,
                        color: cs.primary, size: 22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.link.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  if (widget.link.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.link.description,
                      style: TextStyle(
                        fontSize: 10,
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
