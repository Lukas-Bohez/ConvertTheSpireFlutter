import 'package:flutter/material.dart';

import 'quick_links_service.dart';

/// Firefox-style "New Tab" home page with a prominent search bar
/// and a grid of quick-link tiles.
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    final links = await QuickLinksService.load();
    if (mounted) setState(() => _links = links);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 600 ? 2 : (width < 1024 ? 3 : 4);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        const SizedBox(height: 24),
        // App branding
        Center(
          child: Column(
            children: [
              Icon(Icons.music_note, size: 48, color: cs.primary),
              const SizedBox(height: 8),
              Text(
                'Convert the Spire',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Centered search bar
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search or enter address...',
                prefixIcon: Icon(Icons.search, color: cs.primary),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) return;
                // Check if it's a known route
                if (QuickLinksService.routeToIndex.containsKey(trimmed)) {
                  widget.onNavigate(trimmed);
                } else {
                  widget.onSearch(trimmed);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 40),

        // Quick links section label
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Quick Links',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
          ),
        ),

        // Quick links grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
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
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  final QuickLink link;
  final VoidCallback onTap;

  const _QuickLinkTile({required this.link, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(link.icon, color: cs.primary, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                link.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (link.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  link.description,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
