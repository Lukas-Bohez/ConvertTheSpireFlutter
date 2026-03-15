import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_controller.dart';

import 'quick_links_service.dart';

/// Persistent browser-like shell that wraps all app content.
class BrowserShell extends StatefulWidget {
  final int currentIndex;
  final Widget queueWidget;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String>? onOpenUrl;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onRefresh;
  final VoidCallback onHome;
  final bool canGoBack;
  final bool canGoForward;
  final bool queueOnRight;
  final int queueCount;
  final Widget child;
  final GlobalKey<ScaffoldState> scaffoldKey;

  const BrowserShell({
    super.key,
    required this.currentIndex,
    required this.queueWidget,
    required this.onNavigate,
    this.onOpenUrl,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
    required this.onHome,
    required this.canGoBack,
    required this.canGoForward,
    required this.queueOnRight,
    required this.queueCount,
    required this.child,
    required this.scaffoldKey,
  });

  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell> {
  bool _isEditing = false;
  bool _showQueueDesktop = true;
  late final TextEditingController _urlEditController;
  final FocusNode _urlFocusNode = FocusNode();
  // overlay/old suggestion machinery removed in favor of RawAutocomplete

  @override
  void initState() {
    super.initState();
    _urlEditController = TextEditingController();
  }

  @override
  void dispose() {
    _urlEditController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  String get _currentTitle =>
      QuickLinksService.indexToTitle[widget.currentIndex] ?? 'Search';

  IconData get _currentFavicon =>
      QuickLinksService.indexToIcon[widget.currentIndex] ?? Icons.search;

  // ── URL bar editing ──

  void _startEditing() {
    _urlEditController.text = '';
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _urlFocusNode.requestFocus();
    });
  }

  void _submitUrl(String value) {
    setState(() => _isEditing = false);
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final lower = trimmed.toLowerCase();

    // Prefer exact route matches first (e.g. "queue.tab") so suggestions
    // that use route strings navigate the app instead of being treated as URLs.
    if (QuickLinksService.routeToIndex.containsKey(lower)) {
      final idx = QuickLinksService.routeToIndex[lower];
      if (idx != null) {
        try {
          final app = Provider.of<AppController>(context, listen: false);
          app.switchToTab(idx);
          return;
        } catch (_) {}
      }
      widget.onNavigate(lower);
      return;
    }

    // Title exact match (case-insensitive)
    for (final entry in QuickLinksService.indexToTitle.entries) {
      if (entry.value.toLowerCase() == lower) {
        final route = QuickLinksService.indexToRoute[entry.key];
        if (route != null) {
          widget.onNavigate(route);
          return;
        }
      }
    }

    // Web URL detection — open in browser tab
    if (_looksLikeUrl(trimmed)) {
      final url = trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
      widget.onOpenUrl?.call(url);
      return;
    }

    // Partial route/name match fallback
    for (final entry in QuickLinksService.routeToIndex.entries) {
      final name = entry.key.replaceAll('.tab', '');
      if (name.startsWith(lower) || name.contains(lower)) {
        widget.onNavigate(entry.key);
        return;
      }
    }
  }

  bool _looksLikeUrl(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('www.') ||
        (lower.contains('.') &&
            !lower.contains(' ') &&
            RegExp(r'\.[a-z]{2,}$', caseSensitive: false).hasMatch(lower));
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

  // Suggestions are handled by RawAutocomplete in the URL bar.

  // ── Queue toggle ──

  void _toggleQueue() {
    final scaffold = widget.scaffoldKey.currentState;
    if (scaffold == null) return;
    if (widget.queueOnRight) {
      if (scaffold.isEndDrawerOpen) {
        Navigator.pop(scaffold.context);
      } else {
        scaffold.openEndDrawer();
      }
    } else {
      if (scaffold.isDrawerOpen) {
        Navigator.pop(scaffold.context);
      } else {
        scaffold.openDrawer();
      }
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1024;
    final isNarrow = width < 600;
    final cs = Theme.of(context).colorScheme;

    final queueDrawer = SizedBox(
      width: width < 600 ? width * 0.85 : 320,
      child: Drawer(child: widget.queueWidget),
    );

    return Scaffold(
      key: widget.scaffoldKey,
      endDrawer: !isDesktop && widget.queueOnRight ? queueDrawer : null,
      drawer: !isDesktop && !widget.queueOnRight ? queueDrawer : null,
      body: Column(
        children: [
          _buildNavBar(cs, isDesktop),
          Expanded(
            child: isDesktop
                ? Row(
                    children: [
                      // Left navigation rail for desktop
                      SafeArea(
                        child: NavigationRail(
                          selectedIndex: _primaryIndexForRail(widget.currentIndex),
                          onDestinationSelected: (i) {
                            final idx = _primaryRailIndices[i];
                            final route = QuickLinksService.indexToRoute[idx];
                            if (route != null) widget.onNavigate(route);
                          },
                          labelType: NavigationRailLabelType.all,
                          destinations: _primaryRailIndices
                              .map((i) => NavigationRailDestination(
                                  icon: Icon(QuickLinksService.indexToIcon[i]),
                                  selectedIcon: Icon(QuickLinksService.indexToIcon[i]),
                                  label: Text(QuickLinksService.indexToTitle[i] ?? '')))
                              .toList(),
                        ),
                      ),
                      if (!widget.queueOnRight && _showQueueDesktop)
                        _buildDesktopQueuePanel(cs),
                      Expanded(child: widget.child),
                      if (widget.queueOnRight && _showQueueDesktop)
                        _buildDesktopQueuePanel(cs),
                    ],
                  )
                : widget.child,
          ),
        ],
      ),
      // Bottom navigation for narrow/mobile layouts
      bottomNavigationBar:
          (!isDesktop && isNarrow) ? _buildBottomNav(cs, widget.currentIndex) : null,
    );
  }

  // Primary indices shown in NavigationRail / BottomNavigationBar.
  static const List<int> _primaryRailIndices = [13, 0, 4, 7];

  int _primaryIndexForRail(int currentIndex) {
    final pos = _primaryRailIndices.indexOf(currentIndex);
    return pos < 0 ? 0 : pos;
  }

  Widget _buildBottomNav(ColorScheme cs, int currentIndex) {
    final items = _primaryRailIndices
        .map((i) => BottomNavigationBarItem(
            icon: Icon(QuickLinksService.indexToIcon[i]),
            label: QuickLinksService.indexToTitle[i]))
        .toList();
    final selected = _primaryRailIndices.indexOf(currentIndex);
    return BottomNavigationBar(
      currentIndex: selected < 0 ? 0 : selected,
      items: items,
      type: BottomNavigationBarType.fixed,
      onTap: (i) {
        final idx = _primaryRailIndices[i];
        final route = QuickLinksService.indexToRoute[idx];
        if (route != null) widget.onNavigate(route);
      },
      selectedItemColor: cs.primary,
      unselectedItemColor: cs.onSurface.withValues(alpha: 0.7),
    );
  }

  Widget _buildDesktopQueuePanel(ColorScheme cs) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(
          left: widget.queueOnRight
              ? BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))
              : BorderSide.none,
          right: !widget.queueOnRight
              ? BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))
              : BorderSide.none,
        ),
      ),
      child: widget.queueWidget,
    );
  }

  Widget _buildNavBar(ColorScheme cs, bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                _navButton(Icons.arrow_back_ios_new_rounded, 'Back',
                    widget.canGoBack ? widget.onBack : null, cs),
                _navButton(Icons.arrow_forward_ios_rounded, 'Forward',
                    widget.canGoForward ? widget.onForward : null, cs),
                _navButton(
                    Icons.refresh_rounded, 'Refresh', widget.onRefresh, cs),
                _navButton(Icons.home_rounded, 'Home', widget.onHome, cs),
                const SizedBox(width: 6),
                Expanded(child: _buildUrlBar(cs)),
                const SizedBox(width: 6),
                _buildQueueButton(cs, isDesktop),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(
      IconData icon, String tooltip, VoidCallback? onPressed, ColorScheme cs) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        icon: Icon(icon, size: 17),
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          foregroundColor: onPressed != null ? cs.onSurface : cs.outline,
        ),
      ),
    );
  }

  Widget _buildQueueButton(ColorScheme cs, bool isDesktop) {
    return SizedBox(
      width: 38,
      height: 34,
      child: Stack(
        children: [
          Center(
            child: IconButton(
              icon: Icon(
                isDesktop
                    ? Icons.view_sidebar_rounded
                    : Icons.queue_music_rounded,
                size: 18,
              ),
              onPressed: isDesktop
                  ? () => setState(() => _showQueueDesktop = !_showQueueDesktop)
                  : _toggleQueue,
              tooltip: isDesktop ? 'Toggle queue panel' : 'Open queue',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                foregroundColor:
                    isDesktop && _showQueueDesktop ? cs.primary : cs.onSurface,
              ),
            ),
          ),
          if (widget.queueCount > 0)
            Positioned(
              right: 0,
              top: 2,
              child: GestureDetector(
                onTap: _toggleQueue,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.queueCount > 99 ? '99+' : '${widget.queueCount}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUrlBar(ColorScheme cs) {
    if (!_isEditing) {
      return GestureDetector(
        onTap: _startEditing,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(_currentFavicon, size: 15, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentTitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Build suggestion list from QuickLinksService
    final allPages = <_PageSuggestion>[];
    for (final entry in QuickLinksService.indexToTitle.entries) {
      final route = QuickLinksService.indexToRoute[entry.key];
      if (route == null) continue;
      final icon = QuickLinksService.indexToIcon[entry.key] ?? Icons.link;
      allPages
          .add(_PageSuggestion(title: entry.value, route: route, icon: icon));
    }

    return RawAutocomplete<_PageSuggestion>(
      textEditingController: _urlEditController,
      focusNode: _urlFocusNode,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return allPages;
        return allPages.where((p) =>
            p.title.toLowerCase().contains(q) ||
            p.route.toLowerCase().contains(q));
      },
      onSelected: (suggestion) {
        setState(() => _isEditing = false);
        _submitUrl(suggestion.route);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return Container(
          height: 34,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: cs.primary.withValues(alpha: 0.6), width: 1.5),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: TextStyle(fontSize: 13, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Search pages or enter web address...',
              hintStyle: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onSubmitted: (v) {
              setState(() => _isEditing = false);
              _submitUrl(v);
            },
            onTapOutside: (_) => _cancelEditing(),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final cs = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: cs.surfaceContainerHigh,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: options.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  indent: 44,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                itemBuilder: (context, index) {
                  final p = options.elementAt(index);
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onSelected(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(p.icon,
                                size: 16, color: cs.onPrimaryContainer),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            p.route.replaceAll('.tab', ''),
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageSuggestion {
  final String title;
  final String route;
  final IconData icon;
  const _PageSuggestion({
    required this.title,
    required this.route,
    required this.icon,
  });
}
