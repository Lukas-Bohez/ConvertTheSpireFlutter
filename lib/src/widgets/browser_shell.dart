import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/build_flags.dart';
import '../screens/browser_screen.dart';
import '../screens/player.dart'
    show PlayerState, PositionUiState, MediaItem, MediaType;
import '../vault/services/torrent_service.dart';
import '../widgets/quick_links_service.dart';

const _kRoutes = {
  'search': (
    index: 0,
    icon: Icons.search,
    label: 'Search',
    route: 'search.tab'
  ),
  'multisearch': (
    index: 1,
    icon: Icons.travel_explore,
    label: 'Search+',
    route: 'multisearch.tab'
  ),
  'browser': (
    index: 2,
    icon: Icons.language,
    label: 'Browser',
    route: 'browser.tab'
  ),
  'queue': (
    index: 3,
    icon: Icons.queue_music,
    label: 'Queue',
    route: 'queue.tab'
  ),
  'playlists': (
    index: 4,
    icon: Icons.playlist_play,
    label: 'Playlists',
    route: 'playlists.tab'
  ),
  'files': (
    index: 5,
    icon: Icons.folder,
    label: 'Files',
    route: 'bulkimport.tab'
  ),
  'stats': (
    index: 6,
    icon: Icons.bar_chart,
    label: 'Stats',
    route: 'stats.tab'
  ),
  'settings': (
    index: 7,
    icon: Icons.settings,
    label: 'Settings',
    route: 'settings.tab'
  ),
  'support': (
    index: 8,
    icon: Icons.volunteer_activism,
    label: 'Support',
    route: 'support.tab'
  ),
  'convert': (
    index: 9,
    icon: Icons.transform,
    label: 'Convert',
    route: 'convert.tab'
  ),
  'logs': (index: 10, icon: Icons.list_alt, label: 'Logs', route: 'logs.tab'),
  'guide': (
    index: 11,
    icon: Icons.menu_book,
    label: 'Guide',
    route: 'guide.tab'
  ),
  'player': (
    index: 12,
    icon: Icons.music_note,
    label: 'Player',
    route: 'player.tab'
  ),
  'torrents': (
    index: 14,
    icon: Icons.download,
    label: 'Torrents',
    route: 'torrents.tab'
  ),
};

/// Persistent browser-like shell that wraps all app content.
class BrowserShell extends StatefulWidget {
  static final GlobalKey<_BrowserShellState> shellKey =
      GlobalKey<_BrowserShellState>();

  static void requestAddressBarFocus() {
    shellKey.currentState?._startEditing();
  }

  final int currentIndex;
  final Widget queueWidget;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String>? onOpenUrl;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final VoidCallback onHome;
  final bool canGoBack;
  final bool canGoForward;
  final bool queueOnRight;
  final int queueCount;
  final Widget child;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final VoidCallback? onUrlEditingStart;
  final VoidCallback? onUrlEditingEnd;

  const BrowserShell({
    super.key,
    required this.currentIndex,
    required this.queueWidget,
    required this.onNavigate,
    this.onOpenUrl,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
    required this.isRefreshing,
    required this.onHome,
    required this.canGoBack,
    required this.canGoForward,
    required this.queueOnRight,
    required this.queueCount,
    required this.child,
    required this.scaffoldKey,
    this.onUrlEditingStart,
    this.onUrlEditingEnd,
  });

  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell> {
  bool _isEditing = false;
  bool _showQueueDesktop = true;
  bool _playerCollapsed = true;
  late final TextEditingController _urlEditController;
  final FocusNode _urlFocusNode = FocusNode();
  final LayerLink _urlBarLink = LayerLink();
  final GlobalKey _urlBarKey = GlobalKey();
  OverlayEntry? _suggestionOverlayEntry;

  @override
  void initState() {
    super.initState();
    _urlEditController = TextEditingController();
    _urlFocusNode.addListener(_handleUrlFocusChange);
  }

  @override
  void dispose() {
    _hideSuggestionOverlay();
    _urlFocusNode.removeListener(_handleUrlFocusChange);
    _urlEditController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  String get _currentTitle =>
      QuickLinksService.titleForIndex(widget.currentIndex);

  IconData get _currentFavicon =>
      QuickLinksService.indexToIcon[widget.currentIndex] ?? Icons.search;

  // -- URL bar editing --

  void _startEditing() {
    _urlEditController.text = '';
    _urlEditController.selection = const TextSelection.collapsed(offset: 0);
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _urlFocusNode.requestFocus();
        _showSuggestionOverlay();
        widget.onUrlEditingStart?.call();
      }
    });
  }

  void _showSuggestionOverlay() {
    if (!mounted || !_isEditing) return;
    if (_suggestionOverlayEntry != null) {
      _suggestionOverlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);

    _suggestionOverlayEntry = OverlayEntry(
      builder: (overlayContext) => CompositedTransformFollower(
        link: _urlBarLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 8),
        child: AnimatedBuilder(
          animation: _urlEditController,
          builder: (context, _) {
            final suggestions = _buildSuggestions(_urlEditController.text);
            final cs = Theme.of(context).colorScheme;
            final media = MediaQuery.sizeOf(context);
            final width = media.width;
            var maxWidth = math.min(width - 12, 680.0).toDouble();
            final targetContext = _urlBarKey.currentContext;
            final targetBox = targetContext?.findRenderObject() as RenderBox?;
            if (targetBox != null && targetBox.hasSize) {
              final targetLeft = targetBox.localToGlobal(Offset.zero).dx;
              final availableRight = width - targetLeft - 12;
              if (availableRight.isFinite && availableRight > 0) {
                maxWidth = math.min(maxWidth, availableRight);
              }
            }
            final maxHeight =
                (media.height * 0.55).clamp(180.0, 460.0).toDouble();

            return Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: maxWidth,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: suggestions
                                    .where((s) =>
                                        s.kind ==
                                        _BrowserSuggestionKind.internal)
                                    .map((suggestion) => _SuggestionButton(
                                          label: suggestion.label,
                                          icon: suggestion.icon,
                                          onSubmit: () =>
                                              _handleSubmit(suggestion.value),
                                        ))
                                    .toList(),
                              ),
                              if (suggestions.any((s) =>
                                  s.kind !=
                                  _BrowserSuggestionKind.internal)) ...[
                                const SizedBox(height: 10),
                                ...suggestions
                                    .where((s) =>
                                        s.kind !=
                                        _BrowserSuggestionKind.internal)
                                    .map((suggestion) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: _SuggestionTile(
                                            label: suggestion.label,
                                            subtitle: suggestion.subtitle,
                                            icon: suggestion.icon,
                                            onSubmit: () =>
                                                _handleSubmit(suggestion.value),
                                          ),
                                        ))
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    overlay.insert(_suggestionOverlayEntry!);
  }

  void _handleUrlFocusChange() {
    if (_urlFocusNode.hasFocus || !_isEditing) return;
    if (!mounted) return;
    setState(() => _isEditing = false);
    _hideSuggestionOverlay();
    widget.onUrlEditingEnd?.call();
  }

  void _hideSuggestionOverlay() {
    _suggestionOverlayEntry?.remove();
    _suggestionOverlayEntry = null;
  }

  Future<void> _handleSubmit(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      _finishEditing();
      return;
    }

    final decision = _resolveBrowserSubmission(trimmed);

    switch (decision.kind) {
      case BrowserSubmissionKind.internalRoute:
        _finishEditing();
        widget.onNavigate(decision.value);
        return;
      case BrowserSubmissionKind.magnet:
        _finishEditing();
        await TorrentService.instance.addTorrentFromMagnetLink(trimmed);
        widget.onNavigate('torrents.tab');
        return;
      case BrowserSubmissionKind.openUrl:
        _finishEditing();
        _loadInBrowser(decision.value);
        return;
    }
  }

  void _loadInBrowser(String url) {
    BrowserScreen.pendingUrl = url;
    BrowserScreen.navigate(url);
    widget.onNavigate('browser.tab');
  }

  void _finishEditing() {
    if (!mounted) return;
    setState(() => _isEditing = false);
    _hideSuggestionOverlay();
    widget.onUrlEditingEnd?.call();
    FocusScope.of(context).unfocus();
  }

  // -- Queue toggle --

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

  // -- Build --

  static const double _playerOverlayCollapsedHeight = 64.0;
  static const double _playerOverlayExpandedHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1024;
    final cs = Theme.of(context).colorScheme;

    // Only listen to the fields that actually affect the shell layout.
    final currentItem =
        context.select<PlayerState, MediaItem?>((state) => state.currentItem);
    final isPlaying =
        context.select<PlayerState, bool>((state) => state.isPlaying);
    final playerState = context.read<PlayerState>();
    final showPlayerOverlay = currentItem != null;

    final safeBottom = MediaQuery.of(context).padding.bottom;
    final overlayHeight = showPlayerOverlay
        ? (_playerCollapsed
                ? _playerOverlayCollapsedHeight
                : _playerOverlayExpandedHeight) +
            safeBottom
        : 0.0;

    final queueDrawer = SizedBox(
      width: width < 600 ? width * 0.85 : 320,
      child: Drawer(child: widget.queueWidget),
    );

    return Scaffold(
      key: widget.scaffoldKey,
      endDrawer: !isDesktop && widget.queueOnRight ? queueDrawer : null,
      drawer: !isDesktop && !widget.queueOnRight ? queueDrawer : null,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            FocusTraversalGroup(child: _buildNavBar(cs, isDesktop)),
            Expanded(
              child: isDesktop
                  ? Row(
                      children: [
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
      ),
      bottomNavigationBar: showPlayerOverlay
          ? _buildPlayerOverlay(
              playerState, currentItem, isPlaying, cs, overlayHeight)
          : null,
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
                widget.isRefreshing
                    ? SizedBox(
                        width: 34,
                        height: 34,
                        child: Center(
                            child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(cs.primary),
                          ),
                        )),
                      )
                    : _navButton(
                        Icons.refresh_rounded,
                        'Refresh',
                        widget.onRefresh,
                        cs,
                      ),
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
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
    ColorScheme cs, {
    bool selected = false,
  }) {
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
          foregroundColor: onPressed != null
              ? (selected ? cs.primary : cs.onSurface)
              : cs.outline,
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
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _toggleQueue,
                  borderRadius: BorderRadius.circular(8),
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
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerOverlay(PlayerState state, MediaItem? currentItem,
      bool isPlaying, ColorScheme cs, double overlayHeight) {
    final item = currentItem;
    if (item == null) return const SizedBox.shrink();

    final collapsed = _playerCollapsed;
    final title = item.title ?? item.path.split('/').last;
    final artist = item.artist ?? '';
    final Uint8List? artwork = item.thumbnailData;
    final bool isVideo = item.type == MediaType.video;

    return SizedBox(
      height: overlayHeight,
      child: SafeArea(
        bottom: true,
        top: false,
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          child: Semantics(
            enabled: !Platform.isWindows,
            child: StreamBuilder<PositionUiState>(
              stream: state.positionUiStream,
              initialData: PositionUiState(
                position: state.position,
                duration: state.duration ?? Duration.zero,
                isSeeking: false,
              ),
              builder: (context, snapshot) {
                final ui = snapshot.data ??
                    PositionUiState(
                      position: state.position,
                      duration: state.duration ?? Duration.zero,
                      isSeeking: false,
                    );
                final position = ui.position;
                final duration = ui.duration;
                final buffered = state.bufferedPosition;
                final progress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;
                final bufferedProgress = duration.inMilliseconds > 0
                    ? (buffered.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0.0;
                final width = MediaQuery.of(context).size.width;
                final compactOverlay = width < 360;
                final wideOverlay = width >= 1200;
                final suppressLiveSemantics = Platform.isWindows;

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        cs.surfaceContainerHighest,
                        cs.surfaceContainer,
                      ],
                    ),
                    border: Border(
                      top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.22)),
                    ),
                  ),
                  child: Padding(
                    padding: collapsed
                        ? const EdgeInsets.fromLTRB(10, 6, 10, 6)
                        : const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragEnd: (details) {
                            final velocity = details.primaryVelocity ?? 0;
                            if (velocity < -250) {
                              setState(() => _playerCollapsed = false);
                            } else if (velocity > 250) {
                              setState(() => _playerCollapsed = true);
                            }
                          },
                          child: Row(
                            children: [
                              _buildArtwork(
                                artwork,
                                cs,
                                isVideo,
                                size: collapsed ? 34 : 44,
                              ),
                              SizedBox(width: collapsed ? 8 : 10),
                              Expanded(
                                child: InkWell(
                                  onTap: () => widget.onNavigate('player.tab'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: collapsed
                                              ? 13
                                              : (wideOverlay ? 16 : 14),
                                          color: cs.onSurface,
                                        ),
                                      ),
                                      if (artist.isNotEmpty)
                                        Text(
                                          artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: collapsed
                                                ? 11
                                                : (wideOverlay ? 13 : 12),
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (collapsed) ...[
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 34,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        cs.primary.withValues(alpha: 0.12),
                                    foregroundColor: cs.primary,
                                  ),
                                  onPressed: state.togglePlay,
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 20,
                                  ),
                                  tooltip: isPlaying ? 'Pause' : 'Play',
                                  splashRadius: 18,
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 34,
                                      minHeight: 34,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(
                                      () =>
                                          _playerCollapsed = !_playerCollapsed,
                                    ),
                                    icon: Icon(
                                      collapsed
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 20,
                                    ),
                                    tooltip: collapsed
                                        ? 'Expand player'
                                        : 'Collapse player',
                                    splashRadius: 18,
                                  ),
                                ),
                              ] else ...[
                                _buildTransportButton(
                                  icon: isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  onPressed: state.togglePlay,
                                  tooltip: isPlaying ? 'Pause' : 'Play',
                                  cs: cs,
                                  emphasize: true,
                                ),
                                IconButton(
                                  onPressed: () => setState(
                                    () => _playerCollapsed = !_playerCollapsed,
                                  ),
                                  icon: Icon(
                                    collapsed
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    size: 24,
                                  ),
                                  tooltip: collapsed
                                      ? 'Expand player'
                                      : 'Collapse player',
                                  splashRadius: 20,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!collapsed) ...[
                          const SizedBox(height: 4),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              value: progress,
                              secondaryTrackValue: bufferedProgress > progress
                                  ? bufferedProgress
                                  : progress,
                              activeColor: cs.primary,
                              inactiveColor:
                                  cs.onSurface.withValues(alpha: 0.18),
                              onChanged: duration.inMilliseconds > 0
                                  ? (v) => state.seek(Duration(
                                      milliseconds:
                                          (v * duration.inMilliseconds)
                                              .round()))
                                  : null,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ExcludeSemantics(
                                excluding: suppressLiveSemantics,
                                child: Text(
                                  _formatDuration(position),
                                  style: TextStyle(
                                      fontSize: 10, color: cs.onSurfaceVariant),
                                ),
                              ),
                              Text(
                                isVideo ? 'VIDEO' : 'AUDIO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              ExcludeSemantics(
                                excluding: suppressLiveSemantics,
                                child: Text(
                                  _formatDuration(duration),
                                  style: TextStyle(
                                      fontSize: 10, color: cs.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // TODO(next): add sleep timer and playback-speed controls to the mini player.
                          compactOverlay
                              ? Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildTransportButton(
                                      icon: Icons.skip_previous_rounded,
                                      onPressed: () => state.previous(
                                          only: state.activeTabFilter),
                                      tooltip: 'Previous',
                                      cs: cs,
                                    ),
                                    _buildTransportButton(
                                      icon: Icons.replay_10_rounded,
                                      onPressed: duration.inMilliseconds > 0
                                          ? () {
                                              final nextMs =
                                                  position.inMilliseconds -
                                                      10000;
                                              state.seek(Duration(
                                                  milliseconds:
                                                      nextMs < 0 ? 0 : nextMs));
                                            }
                                          : null,
                                      tooltip: 'Back 10s',
                                      cs: cs,
                                    ),
                                    _buildTransportButton(
                                      icon: isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      onPressed: state.togglePlay,
                                      tooltip: isPlaying ? 'Pause' : 'Play',
                                      cs: cs,
                                      emphasize: true,
                                    ),
                                    _buildTransportButton(
                                      icon: Icons.forward_10_rounded,
                                      onPressed: duration.inMilliseconds > 0
                                          ? () {
                                              final maxMs =
                                                  duration.inMilliseconds;
                                              final nextMs =
                                                  position.inMilliseconds +
                                                      10000;
                                              state.seek(Duration(
                                                  milliseconds: nextMs > maxMs
                                                      ? maxMs
                                                      : nextMs));
                                            }
                                          : null,
                                      tooltip: 'Forward 10s',
                                      cs: cs,
                                    ),
                                    _buildTransportButton(
                                      icon: Icons.skip_next_rounded,
                                      onPressed: () => state.next(
                                          only: state.activeTabFilter),
                                      tooltip: 'Next',
                                      cs: cs,
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildTransportButton(
                                      icon: Icons.skip_previous_rounded,
                                      onPressed: () => state.previous(
                                          only: state.activeTabFilter),
                                      tooltip: 'Previous',
                                      cs: cs,
                                    ),
                                    _buildTransportButton(
                                      icon: Icons.replay_10_rounded,
                                      onPressed: duration.inMilliseconds > 0
                                          ? () {
                                              final nextMs =
                                                  position.inMilliseconds -
                                                      10000;
                                              state.seek(Duration(
                                                  milliseconds:
                                                      nextMs < 0 ? 0 : nextMs));
                                            }
                                          : null,
                                      tooltip: 'Back 10s',
                                      cs: cs,
                                    ),
                                    _buildTransportButton(
                                      icon: isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      onPressed: state.togglePlay,
                                      tooltip: isPlaying ? 'Pause' : 'Play',
                                      cs: cs,
                                      emphasize: true,
                                    ),
                                    _buildTransportButton(
                                      icon: Icons.forward_10_rounded,
                                      onPressed: duration.inMilliseconds > 0
                                          ? () {
                                              final maxMs =
                                                  duration.inMilliseconds;
                                              final nextMs =
                                                  position.inMilliseconds +
                                                      10000;
                                              state.seek(Duration(
                                                  milliseconds: nextMs > maxMs
                                                      ? maxMs
                                                      : nextMs));
                                            }
                                          : null,
                                      tooltip: 'Forward 10s',
                                      cs: cs,
                                    ),
                                    _buildTransportButton(
                                      icon: Icons.skip_next_rounded,
                                      onPressed: () => state.next(
                                          only: state.activeTabFilter),
                                      tooltip: 'Next',
                                      cs: cs,
                                    ),
                                  ],
                                ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(
    Uint8List? artwork,
    ColorScheme cs,
    bool isVideo, {
    double size = 44,
  }) {
    final fallbackIcon =
        isVideo ? Icons.movie_rounded : Icons.music_note_rounded;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: artwork != null && artwork.isNotEmpty
          ? Image.memory(
              artwork,
              cacheWidth: (size * 2).round(),
              cacheHeight: (size * 2).round(),
              filterQuality: FilterQuality.low,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                fallbackIcon,
                color: cs.primary,
                size: 20,
              ),
            )
          : Icon(
              fallbackIcon,
              color: cs.primary,
              size: 20,
            ),
    );
  }

  Widget _buildTransportButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    required ColorScheme cs,
    bool emphasize = false,
  }) {
    return IconButton(
      icon: Icon(icon, size: emphasize ? 24 : 22),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
      style: IconButton.styleFrom(
        backgroundColor: emphasize
            ? cs.primary.withValues(alpha: 0.12)
            : cs.surfaceContainerHigh,
        foregroundColor: onPressed == null
            ? cs.outline
            : (emphasize ? cs.primary : cs.onSurface),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildUrlBar(ColorScheme cs) {
    final isBrowserTab = widget.currentIndex == _kRoutes['browser']!.index;

    if (_isEditing) {
      return CompositedTransformTarget(
        key: _urlBarKey,
        link: _urlBarLink,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: _urlEditController,
              focusNode: _urlFocusNode,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: cs.onSurface),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search pages or enter web address...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                suffixIcon: IconButton(
                  tooltip: 'Open',
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: () => _handleSubmit(_urlEditController.text),
                ),
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 28, minWidth: 28),
              ),
              onSubmitted: _handleSubmit,
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<BrowserLocationState?>(
      valueListenable: BrowserScreen.currentLocation,
      builder: (context, browserLocation, _) {
        final label = isBrowserTab && browserLocation != null
            ? browserLocation.displayLabel
            : _currentTitle;
        final icon = isBrowserTab && browserLocation != null
            ? Icons.language
            : _currentFavicon;

        return CompositedTransformTarget(
          key: _urlBarKey,
          link: _urlBarLink,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _startEditing,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 15, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
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
            ),
          ),
        );
      },
    );
  }

  List<_BrowserSuggestion> _buildSuggestions(String query) {
    final trimmed = query.trim();
    final lower = trimmed.toLowerCase();

    final internal = <_BrowserSuggestion>[];
    // Regression check: when the browser tab itself is focused, empty input
    // must still show these internal chips because _startEditing() no longer
    // short-circuits on browser.tab.
    for (final destination in _browserDestinations) {
      if (lower.isEmpty ||
          destination.keyword.startsWith(lower) ||
          destination.label.toLowerCase().startsWith(lower) ||
          destination.value.toLowerCase().startsWith(lower)) {
        internal.add(destination);
      }
    }

    final external = <_BrowserSuggestion>[];
    if (lower.isNotEmpty) {
      if (_looksLikeBrowserUrl(trimmed)) {
        final normalized =
            trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
        external.add(
          _BrowserSuggestion(
            kind: _BrowserSuggestionKind.url,
            label: 'Open $normalized',
            value: normalized,
            subtitle: 'Navigate directly to the site',
            icon: Icons.language,
            keyword: normalized,
            aliases: const [],
          ),
        );
      }
      external.add(
        _BrowserSuggestion(
          kind: _BrowserSuggestionKind.search,
          label: 'Search Google for "$trimmed"',
          value:
              'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}',
          subtitle: 'Plain text falls back to search',
          icon: Icons.search,
          keyword:
              'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}',
          aliases: const [],
        ),
      );
    }

    return [...internal, ...external];
  }

  bool _looksLikeBrowserUrl(String text) {
    final lower = text.toLowerCase();
    final hasScheme =
        lower.startsWith('http://') || lower.startsWith('https://');
    if (hasScheme) return true;
    if (lower.contains(' ')) return false;
    if (!lower.contains('.')) return false;
    return RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?([/?#].*)?$',
            caseSensitive: false)
        .hasMatch(lower);
  }
}

class _SuggestionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onSubmit;

  const _SuggestionButton({
    required this.label,
    required this.icon,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onSubmit(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onSubmit;

  const _SuggestionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onSubmit(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Icon(icon, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BrowserSubmissionDecision _resolveBrowserSubmission(String input) {
  final trimmed = input.trim();
  final lower = trimmed.toLowerCase();

  for (final entry in _kRoutes.entries) {
    final route = entry.value.route;
    if (lower == entry.key ||
        lower == entry.value.label.toLowerCase() ||
        lower == route) {
      return BrowserSubmissionDecision(
        BrowserSubmissionKind.internalRoute,
        route,
      );
    }
  }

  // Legacy aliases kept for compatibility with old input habits.
  const legacyAliases = <String, String>{
    'downloads': 'torrents.tab',
    'import': 'bulkimport.tab',
    'search+': 'multisearch.tab',
  };
  final aliasedRoute = legacyAliases[lower];
  if (aliasedRoute != null) {
    return BrowserSubmissionDecision(
      BrowserSubmissionKind.internalRoute,
      aliasedRoute,
    );
  }

  if (lower.startsWith('magnet:')) {
    return BrowserSubmissionDecision(BrowserSubmissionKind.magnet, trimmed);
  }

  if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
    return BrowserSubmissionDecision(BrowserSubmissionKind.openUrl, trimmed);
  }

  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return BrowserSubmissionDecision(BrowserSubmissionKind.openUrl, trimmed);
  }

  final directUrlPattern = RegExp(
    r'^[a-z0-9-]+(\.[a-z0-9-]+)+(:\d+)?([/?#].*)?$',
  );
  if (!trimmed.contains(' ') && directUrlPattern.hasMatch(lower)) {
    return BrowserSubmissionDecision(
      BrowserSubmissionKind.openUrl,
      'https://$trimmed',
    );
  }

  return BrowserSubmissionDecision(
    BrowserSubmissionKind.openUrl,
    'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}',
  );
}

enum BrowserSubmissionKind {
  internalRoute,
  openUrl,
  magnet,
}

class BrowserSubmissionDecision {
  final BrowserSubmissionKind kind;
  final String value;

  const BrowserSubmissionDecision(this.kind, this.value);
}

enum _BrowserSuggestionKind {
  internal,
  url,
  search,
}

class _BrowserSuggestion {
  final _BrowserSuggestionKind kind;
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final String keyword;
  final List<String> aliases;

  const _BrowserSuggestion({
    required this.kind,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.keyword,
    required this.aliases,
  });
}

final List<_BrowserSuggestion> _browserDestinations = [
  for (final entry in _kRoutes.entries)
    if (isTabVisibleInCurrentBuild(entry.value.index))
      _BrowserSuggestion(
        kind: _BrowserSuggestionKind.internal,
        label: entry.value.label,
        value: entry.value.route,
        subtitle: entry.value.label,
        icon: entry.value.icon,
        keyword: entry.key,
        aliases: const [],
      ),
];
