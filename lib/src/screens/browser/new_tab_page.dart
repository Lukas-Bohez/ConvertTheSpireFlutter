import 'package:flutter/material.dart';

import '../../data/browser_db.dart';
import '../../utils/screenshot_helper.dart';

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
  final GlobalKey _repaintKey = GlobalKey();
  final ScrollController _favouritesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    widget.repo.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Capture a one-off screenshot of the NewTabPage for QA.
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        await ScreenshotHelper.captureToFile(
            _repaintKey, 'results/screenshots/new_tab_page.png');
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    _searchController.dispose();
    _favouritesScrollController.dispose();
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

  static const _defaultSites = [
    {
      'url': 'https://www.youtube.com',
      'title': 'YouTube',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=youtube.com'
    },
    {
      'url': 'https://www.google.com',
      'title': 'Google',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=google.com'
    },
    {
      'url': 'https://www.wikipedia.org',
      'title': 'Wikipedia',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=wikipedia.org'
    },
    {
      'url': 'https://www.reddit.com',
      'title': 'Reddit',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=reddit.com'
    },
    {
      'url': 'https://github.com',
      'title': 'GitHub',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=github.com'
    },
    {
      'url': 'https://music.youtube.com',
      'title': 'YouTube Music',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=music.youtube.com'
    },
    {
      'url': 'https://soundcloud.com',
      'title': 'SoundCloud',
      'favicon':
          'https://www.google.com/s2/favicons?sz=64&domain_url=soundcloud.com'
    },
    {
      'url': 'https://www.twitch.tv',
      'title': 'Twitch',
      'favicon': 'https://www.google.com/s2/favicons?sz=64&domain_url=twitch.tv'
    },
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final quickAccessSites =
        _recentSites.isNotEmpty ? _recentSites : _defaultSites;
    return Material(
      color: cs.surface,
      child: RepaintBoundary(
        key: _repaintKey,
        child: CustomScrollView(
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

            // ── Quick access (most visited / suggested) ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                    _recentSites.isNotEmpty
                        ? 'Quick Access'
                        : 'Suggested Sites',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount =
                      width < 500 ? 2 : (width < 900 ? 3 : 4);
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.6,
                    children: quickAccessSites.take(8).map((site) {
                      final url = site['url'] as String;
                      final title = site['title'] as String? ?? '';
                      final favicon = site['favicon'] as String?;
                      final host = Uri.tryParse(url)?.host ?? url;
                      final label = title.isNotEmpty ? title : host;
                      return _QuickAccessTile(
                        label: label,
                        faviconUrl: favicon,
                        onTap: () => widget.onNavigate(url),
                      );
                    }).toList(),
                  );
                }),
              ),
            ),

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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    // On narrow screens keep a single horizontal scroll row with a visible scrollbar.
                    if (width < 700) {
                      return SizedBox(
                        height: 56,
                        child: Scrollbar(
                          controller: _favouritesScrollController,
                          thumbVisibility: true,
                          child: ListView.separated(
                            controller: _favouritesScrollController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _favourites.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final fav = _favourites[index];
                              final url = fav['url'] as String;
                              final rawTitle = fav['title'] as String? ?? '';
                              final host = (Uri.tryParse(url)?.host ?? url)
                                  .replaceFirst('www.', '');
                              final title = (rawTitle.isNotEmpty &&
                                      rawTitle.toLowerCase() != 'new tab')
                                  ? rawTitle
                                  : host;
                              return ActionChip(
                                avatar: const Icon(Icons.star, size: 16),
                                label: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 240),
                                  child: Text(
                                    title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onPressed: () => widget.onNavigate(url),
                              );
                            },
                          ),
                        ),
                      );
                    }

                    // On wide screens allow chips to wrap into multiple rows so all favourites are visible and keyboard/mouse accessible.
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _favourites.map((fav) {
                          final url = fav['url'] as String;
                          final rawTitle = fav['title'] as String? ?? '';
                          final host = (Uri.tryParse(url)?.host ?? url)
                              .replaceFirst('www.', '');
                          final title = (rawTitle.isNotEmpty &&
                                  rawTitle.toLowerCase() != 'new tab')
                              ? rawTitle
                              : host;
                          return ActionChip(
                            avatar: const Icon(Icons.star, size: 16),
                            label: ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: width * 0.33),
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            onPressed: () => widget.onNavigate(url),
                          );
                        }).toList(),
                      ),
                    );
                  }),
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
        ),
      ),
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
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: _FaviconWidget(faviconUrl: faviconUrl, size: 18),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
          ],
        ),
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
        errorBuilder: (_, __, ___) => Icon(Icons.language, size: size),
      );
    }
    return Icon(Icons.language, size: size);
  }
}
