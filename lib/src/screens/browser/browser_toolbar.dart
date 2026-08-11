import 'package:flutter/material.dart';

import '../../config/build_flags.dart';

/// Top toolbar for the browser with URL bar, navigation, cast button, and menu.
class BrowserToolbar extends StatelessWidget {
  final bool isLoading;
  final bool isSecure;
  final bool isIncognito;
  final bool canGoBack;
  final bool canGoForward;
  final bool hasVideos;
  final AnimationController castBadgeAnimation;
  final bool desktopMode;
  final bool adBlockEnabled;
  final String pageTitle;
  final String currentUrl;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onCastTap;
  final VoidCallback? onDownload;
  final bool isFavourited;
  final VoidCallback? onFavouriteTap;
  final bool isDownloading;
  final bool downloadEnabled;
  final bool isKnownDifficultSite;
  final bool isCastConnected;
  final ValueChanged<String> onMenuAction;
  final VoidCallback? onReleaseWebViewFocus;
  final VoidCallback onTabs;
  final int tabCount;
  final VoidCallback? onAddressBarTap;

  const BrowserToolbar({
    super.key,
    required this.isLoading,
    required this.isSecure,
    required this.isIncognito,
    required this.canGoBack,
    required this.canGoForward,
    required this.hasVideos,
    required this.castBadgeAnimation,
    required this.desktopMode,
    required this.adBlockEnabled,
    required this.pageTitle,
    required this.currentUrl,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onCastTap,
    this.onDownload,
    this.isFavourited = false,
    this.onFavouriteTap,
    this.isDownloading = false,
    this.downloadEnabled = false,
    this.isKnownDifficultSite = false,
    this.isCastConnected = false,
    required this.onMenuAction,
    this.onReleaseWebViewFocus,
    required this.onTabs,
    this.tabCount = 1,
    this.onAddressBarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 400;
    final wide = width > 840;
    final buttonSize = wide ? 52.0 : (compact ? 36.0 : 44.0);

    // Incognito gets a dark purple tint; normal mode uses a slightly elevated
    // surface so the toolbar doesn't blend into the page content.
    final bgColor = isIncognito
        ? const Color(0xFF1A1A2E)
        : cs.surfaceContainerLowest;
    final iconColor = isIncognito ? Colors.white : cs.onSurface;

    return Material(
      elevation: 2,
      color: bgColor,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              compact ? 6 : 10, compact ? 4 : 6, compact ? 6 : 10, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
          ),
          child: IconTheme(
            data: IconThemeData(color: iconColor, size: compact ? 18 : 20),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: Size(buttonSize, buttonSize),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              child: Row(
                children: [
                  // Back
                  _ToolbarButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: canGoBack ? onBack : null,
                    tooltip: 'Back',
                    compact: compact,
                  ),
                  // Forward
                  _ToolbarButton(
                    icon: Icons.arrow_forward_rounded,
                    onPressed: canGoForward ? onForward : null,
                    tooltip: 'Forward',
                    compact: compact,
                  ),
                  // Address bar
                  Expanded(
                    child: GestureDetector(
                      onTap: onAddressBarTap,
                      child: Container(
                        height: wide ? 42 : (compact ? 34 : 38),
                        decoration: BoxDecoration(
                          color: isIncognito
                              ? Colors.white.withValues(alpha: 0.08)
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isIncognito
                                ? Colors.white.withValues(alpha: 0.1)
                                : cs.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              if (isLoading)
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isIncognito
                                        ? Colors.white70
                                        : cs.primary,
                                  ),
                                )
                              else
                                Icon(
                                  isSecure
                                      ? Icons.lock_rounded
                                      : Icons.lock_open_rounded,
                                  size: 14,
                                  color: isSecure
                                      ? Colors.green
                                      : (isIncognito
                                          ? Colors.white54
                                          : cs.outline),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _siteDomain(currentUrl),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isIncognito
                                            ? Colors.white
                                            : cs.onSurface,
                                      ),
                                    ),
                                    if (pageTitle.isNotEmpty &&
                                        pageTitle != _siteDomain(currentUrl))
                                      Text(
                                        pageTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isIncognito
                                              ? Colors.white54
                                              : cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (adBlockEnabled)
                                Tooltip(
                                  message: 'Ad blocker active',
                                  child: Icon(
                                    Icons.shield_rounded,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                ),
                              if (desktopMode) ...[
                                const SizedBox(width: 6),
                                _buildBadge(
                                  context,
                                  icon: Icons.desktop_windows_rounded,
                                  label: 'Desktop',
                                  active: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Tabs button
                  _TabsButton(
                    tabCount: tabCount,
                    onPressed: () {
                      onReleaseWebViewFocus?.call();
                      onTabs();
                    },
                    compact: compact,
                  ),
                  // Reload
                  _ToolbarButton(
                    icon: Icons.refresh_rounded,
                    onPressed: onReload,
                    tooltip: 'Reload',
                    compact: compact,
                  ),
                  // Favourite
                  _ToolbarButton(
                    icon: isFavourited
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    onPressed: onFavouriteTap,
                    tooltip: isFavourited
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    compact: compact,
                    iconColor: isFavourited ? Colors.amber : null,
                  ),
                  // Download
                  if (onDownload != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: isDownloading
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.download_rounded,
                                  size: 20),
                              onPressed: downloadEnabled
                                  ? () {
                                      onReleaseWebViewFocus?.call();
                                      onDownload?.call();
                                    }
                                  : null,
                              tooltip: 'Download',
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    cs.primaryContainer.withValues(alpha: 0.8),
                                foregroundColor: cs.onPrimaryContainer,
                              ),
                            ),
                  // Overflow menu
                  _OverflowMenuButton(
                    onMenuAction: onMenuAction,
                    onReleaseWebViewFocus: onReleaseWebViewFocus,
                    isCastConnected: isCastConnected,
                    compact: compact,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? cs.primary.withValues(alpha: 0.12)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: active ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _siteDomain(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.trim() ?? '';
    if (host.isEmpty) return pageTitle.isNotEmpty ? pageTitle : 'New Tab';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool compact;
  final Color? iconColor;

  const _ToolbarButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.compact = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: compact ? 18 : 20, color: iconColor),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: onPressed != null ? cs.onSurface : cs.outline,
        minimumSize: Size(compact ? 32 : 40, compact ? 32 : 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _TabsButton extends StatelessWidget {
  final int tabCount;
  final VoidCallback onPressed;
  final bool compact;

  const _TabsButton({
    required this.tabCount,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Tabs',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.tab_rounded, size: compact ? 18 : 20),
            onPressed: onPressed,
            style: IconButton.styleFrom(
              minimumSize: Size(compact ? 32 : 40, compact ? 32 : 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          if (tabCount > 1)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 14,
                ),
                child: Text(
                  '$tabCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverflowMenuButton extends StatelessWidget {
  final ValueChanged<String> onMenuAction;
  final VoidCallback? onReleaseWebViewFocus;
  final bool isCastConnected;
  final bool compact;

  const _OverflowMenuButton({
    required this.onMenuAction,
    this.onReleaseWebViewFocus,
    this.isCastConnected = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (buttonContext) {
      return IconButton(
        icon: Icon(Icons.more_vert, size: compact ? 18 : 20),
        tooltip: 'More options',
        onPressed: () async {
          onReleaseWebViewFocus?.call();
          try {
            onMenuAction('menu_open');
          } catch (_) {}

          final RenderBox button =
              buttonContext.findRenderObject() as RenderBox;
          final Offset buttonPos = button.localToGlobal(Offset.zero);
          final Size buttonSize = button.size;
          final RenderBox overlay = Overlay.of(buttonContext)
              .context
              .findRenderObject() as RenderBox;

          final selection = await showMenu<String>(
            context: buttonContext,
            color: Theme.of(buttonContext).colorScheme.surfaceContainerHigh,
            elevation: 8,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            position: RelativeRect.fromRect(
              buttonPos & buttonSize,
              Offset.zero & overlay.size,
            ),
            items: [
              if (!kPlayStoreBuild)
                PopupMenuItem(
                    value: 'cast',
                    child: Row(children: [
                      Icon(Icons.cast,
                          color: Theme.of(context).colorScheme.onSurface),
                      const SizedBox(width: 12),
                      const Text('Cast to device'),
                      const Spacer(),
                      if (isCastConnected)
                        Icon(Icons.circle,
                            size: 8,
                            color: Theme.of(context).colorScheme.primary),
                    ])),
              PopupMenuItem(
                  value: 'openExternal',
                  child: Row(children: [
                    Icon(Icons.open_in_browser,
                        color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 12),
                    const Text('Open in browser'),
                  ])),
              PopupMenuItem(
                  value: 'copyLink',
                  child: Row(children: [
                    Icon(Icons.copy,
                        color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 12),
                    const Text('Copy link'),
                  ])),
              PopupMenuItem(
                  value: 'share',
                  child: Row(children: [
                    Icon(Icons.share,
                        color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 12),
                    const Text('Share'),
                  ])),
              PopupMenuItem(
                  value: 'addCookies',
                  child: Row(children: [
                    Icon(Icons.cookie_outlined,
                        color: Theme.of(context).colorScheme.onSurface),
                    const SizedBox(width: 12),
                    const Text('Add cookies (for downloads)'),
                  ])),
            ],
          );
          if (selection != null) onMenuAction(selection);
        },
      );
    });
  }
}
