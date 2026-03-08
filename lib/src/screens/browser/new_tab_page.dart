import 'package:flutter/material.dart';

import '../../data/browser_db.dart';

/// Premium "New Tab" page with search bar, quick-access tiles,
/// favourites horizontal scroll, and recent history.
class NewTabPage extends StatefulWidget {
  final BrowserRepository repo;
  final ValueChanged<String> onNavigate;

  const NewTabPage({
    super.key,
    required this.repo,
    required this.onNavigate,
  });

  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _recentSites = [];
  List<Map<String, dynamic>> _favourites = [];
  List<Map<String, dynamic>> _recentHistory = [];

  @override
  void initState() {
    super.initState();
    _load();
    widget.repo.addListener(_load);
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    _searchController.dispose();
    super.dispose();
  }

  void _load() async {
    final sites = await widget.repo.getRecentSites();
    final favs = await widget.repo.getFavourites();
    final hist = await widget.repo.getHistory(limit: 10);
    if (mounted) {
      setState(() {
        _recentSites = sites;
        _favourites = favs;
        _recentHistory = hist;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 32)),

        // ── Search bar ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search or enter URL',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  widget.onNavigate(val.trim());
                  _searchController.clear();
                }
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),

        // ── Quick access (most visited) ──
        if (_recentSites.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Quick Access',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.count(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: _recentSites.take(8).map((site) {
                final url = site['url'] as String;
                final title = site['title'] as String? ?? '';
                final favicon = site['favicon'] as String?;
                final host = Uri.tryParse(url)?.host ?? url;
                final label =
                    title.isNotEmpty ? title : host;
                return _QuickAccessTile(
                  label: label,
                  faviconUrl: favicon,
                  onTap: () => widget.onNavigate(url),
                );
              }).toList(),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── Favourites horizontal scroll ──
        if (_favourites.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Favourites',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _favourites.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final fav = _favourites[index];
                  final url = fav['url'] as String;
                  final title = fav['title'] as String? ?? '';
                  final host = Uri.tryParse(url)?.host ?? url;
                  return ActionChip(
                    avatar: const Icon(Icons.star, size: 16),
                    label: Text(
                      title.isNotEmpty ? title : host,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => widget.onNavigate(url),
                  );
                },
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── Recent history ──
        if (_recentHistory.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Recent',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _recentHistory[index];
                final url = item['url'] as String;
                final title = item['title'] as String? ?? '';
                final favicon = item['favicon'] as String?;
                final host = Uri.tryParse(url)?.host ?? url;
                final time = DateTime.fromMillisecondsSinceEpoch(
                    item['visited_at'] as int);
                return ListTile(
                  leading: _FaviconWidget(faviconUrl: favicon),
                  title: Text(
                    title.isNotEmpty ? title : host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: Text(
                    _formatTime(time),
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => widget.onNavigate(url),
                );
              },
              childCount: _recentHistory.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Quick-access tile ──

class _QuickAccessTile extends StatelessWidget {
  final String label;
  final String? faviconUrl;
  final VoidCallback onTap;

  const _QuickAccessTile({
    required this.label,
    required this.faviconUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: _FaviconWidget(faviconUrl: faviconUrl, size: 24),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Favicon widget with fallback ──

class _FaviconWidget extends StatelessWidget {
  final String? faviconUrl;
  final double size;

  const _FaviconWidget({this.faviconUrl, this.size = 20});

  @override
  Widget build(BuildContext context) {
    if (faviconUrl != null && faviconUrl!.isNotEmpty) {
      return Image.network(
        faviconUrl!,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.language, size: size),
      );
    }
    return Icon(Icons.language, size: size);
  }
}
