import 'package:flutter/material.dart';

import 'quick_links_service.dart';

/// The persistent browser-like shell that wraps all app content.
///
/// Contains:
/// - Top AppBar with back/forward/refresh, fake URL bar, favicon, queue toggle
/// - Main content area (child pages)
/// - Queue sidebar (endDrawer on mobile/tablet, fixed panel on desktop)
///
/// This widget never rebuilds when navigating between features — it holds
/// the scaffold, URL bar state, and navigation history.
class BrowserShell extends StatefulWidget {
  /// The current page index (0–12).
  final int currentIndex;

  /// The queue widget, kept alive across navigations.
  final Widget queueWidget;

  /// Callback when a route is navigated to from the URL bar.
  final ValueChanged<String> onNavigate;

  /// Callback when back is pressed.
  final VoidCallback? onBack;

  /// Callback when forward is pressed.
  final VoidCallback? onForward;

  /// Callback when refresh is pressed.
  final VoidCallback onRefresh;

  /// Whether back navigation is possible.
  final bool canGoBack;

  /// Whether forward navigation is possible.
  final bool canGoForward;

  /// Whether the queue sidebar is on the right (true) or left (false).
  final bool queueOnRight;

  /// Total items in queue (for badge).
  final int queueCount;

  /// Child content — the active page.
  final Widget child;

  /// Global key to control the scaffold's endDrawer/drawer.
  final GlobalKey<ScaffoldState> scaffoldKey;

  const BrowserShell({
    super.key,
    required this.currentIndex,
    required this.queueWidget,
    required this.onNavigate,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
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
  late final TextEditingController _urlEditController;
  final FocusNode _urlFocusNode = FocusNode();

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

  String get _currentRoute =>
      QuickLinksService.indexToRoute[widget.currentIndex] ?? 'search.tab';

  String get _currentTitle =>
      QuickLinksService.indexToTitle[widget.currentIndex] ?? 'Search';

  IconData get _currentFavicon =>
      QuickLinksService.indexToIcon[widget.currentIndex] ?? Icons.search;

  void _startEditing() {
    _urlEditController.text = _currentRoute;
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _urlFocusNode.requestFocus();
      _urlEditController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _urlEditController.text.length,
      );
    });
  }

  void _submitUrl(String value) {
    setState(() => _isEditing = false);
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return;

    // Direct route match
    if (QuickLinksService.routeToIndex.containsKey(trimmed)) {
      widget.onNavigate(trimmed);
      return;
    }

    // Partial match (e.g. "player" → "player.tab")
    for (final entry in QuickLinksService.routeToIndex.entries) {
      if (entry.key.startsWith(trimmed) ||
          entry.key.replaceAll('.tab', '').replaceAll('.spire', '') ==
              trimmed) {
        widget.onNavigate(entry.key);
        return;
      }
    }

    // Fallback: treat as search query → navigate to search tab
    widget.onNavigate('search.tab');
  }

  void _cancelEditing() {
    setState(() => _isEditing = false);
  }

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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1024;
    final cs = Theme.of(context).colorScheme;

    final queueDrawer = SizedBox(
      width: width < 600 ? width * 0.85 : 320,
      child: Drawer(child: widget.queueWidget),
    );

    return Scaffold(
      key: widget.scaffoldKey,
      endDrawer: !isDesktop && widget.queueOnRight ? queueDrawer : null,
      drawer: !isDesktop && !widget.queueOnRight ? queueDrawer : null,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: _buildAppBar(cs, isDesktop),
      ),
      body: isDesktop
          ? Row(
              children: [
                if (!widget.queueOnRight)
                  SizedBox(
                    width: 300,
                    child: Material(
                      elevation: 1,
                      child: widget.queueWidget,
                    ),
                  ),
                Expanded(child: widget.child),
                if (widget.queueOnRight)
                  SizedBox(
                    width: 300,
                    child: Material(
                      elevation: 1,
                      child: widget.queueWidget,
                    ),
                  ),
              ],
            )
          : Stack(
              children: [
                widget.child,
                // Subtle handle on the right edge (mobile) to hint at queue drawer
                if (widget.queueOnRight)
                  Positioned(
                    right: 0,
                    top: MediaQuery.of(context).size.height * 0.35,
                    child: GestureDetector(
                      onTap: _toggleQueue,
                      onHorizontalDragEnd: (_) => _toggleQueue(),
                      child: Container(
                        width: 14,
                        height: 56,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.8),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: Icon(Icons.chevron_left,
                            size: 14, color: cs.primary),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAppBar(ColorScheme cs, bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: widget.canGoBack ? widget.onBack : null,
                tooltip: 'Back',
                visualDensity: VisualDensity.compact,
              ),
              // Forward
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: widget.canGoForward ? widget.onForward : null,
                tooltip: 'Forward',
                visualDensity: VisualDensity.compact,
              ),
              // Refresh
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: widget.onRefresh,
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),

              // URL bar
              Expanded(child: _buildUrlBar(cs)),

              const SizedBox(width: 4),

              // Queue toggle with badge
              Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      isDesktop
                          ? Icons.view_sidebar
                          : Icons.queue_music,
                      size: 20,
                    ),
                    onPressed: isDesktop ? null : _toggleQueue,
                    tooltip: isDesktop ? 'Queue sidebar' : 'Toggle queue',
                    visualDensity: VisualDensity.compact,
                  ),
                  if (widget.queueCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.queueCount > 99
                              ? '99+'
                              : '${widget.queueCount}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrlBar(ColorScheme cs) {
    if (_isEditing) {
      return Container(
        height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.primary, width: 1.5),
        ),
        child: TextField(
          controller: _urlEditController,
          focusNode: _urlFocusNode,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onSubmitted: _submitUrl,
          onTapOutside: (_) => _cancelEditing(),
        ),
      );
    }

    return GestureDetector(
      onTap: _startEditing,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(_currentFavicon, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentRoute,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '— $_currentTitle',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
