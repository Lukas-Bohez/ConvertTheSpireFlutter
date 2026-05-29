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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 400;
    final wide = width > 840;
    final buttonSize = wide ? 56.0 : (compact ? 34.0 : 48.0);
    // always ensure a light toolbar on mobile unless in incognito mode; dark
    // themes make the toolbar blend with the rest of the app, which looks bad
    // inside the browser.  Desktop respects the global surface color.
    final bgColor = isIncognito
        ? const Color(0xFF1A1A2E)
        : cs.surface; // avoid hardcoded white; use theme surface
    final iconColor = isIncognito ? Colors.white : cs.onSurface;

    return Container(
      color: bgColor,
      padding: EdgeInsets.fromLTRB(4, compact ? 1 : 3, 4, compact ? 2 : 4),
      child: IconTheme(
        data: IconThemeData(color: iconColor),
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
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: canGoBack ? onBack : null,
              ),
              // Forward
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: canGoForward ? onForward : null,
              ),
              // Site info
              Expanded(
                child: Container(
                  height: wide ? 44 : (compact ? 34 : 38),
                  decoration: BoxDecoration(
                    color: isIncognito
                        ? Colors.white.withValues(alpha: 0.1)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          isSecure
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 14,
                          color: isSecure
                              ? Colors.green
                              : (isIncognito ? Colors.white54 : cs.outline),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                        Tooltip(
                          message: adBlockEnabled
                              ? 'Ad blocker active'
                              : 'Ad blocker off'
                              ,
                          child: Icon(
                            adBlockEnabled
                                ? Icons.shield_rounded
                                : Icons.shield_outlined,
                            size: 16,
                            color: adBlockEnabled
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (desktopMode) ...[
                          _buildBadge(
                            context,
                            icon: Icons.desktop_windows_rounded,
                            label: 'Desktop mode',
                            active: true,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Tabs button
              Tooltip(
                message: 'Tabs',
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.tab_rounded, size: 20),
                      onPressed: () {
                        onReleaseWebViewFocus?.call();
                        onTabs();
                      },
                    ),
                    if (tabCount > 1)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 14,
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
              ),
              // Reload
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: onReload,
              ),
              // Favourite
              IconButton(
                icon: Icon(
                  isFavourited
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 20,
                  color: isFavourited ? Colors.amber : null,
                ),
                tooltip: isFavourited
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                onPressed: onFavouriteTap,
              ),
              // Download (primary action)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: onDownload == null
                    ? const SizedBox.shrink()
                    : (isDownloading
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
                            style: IconButton.styleFrom(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          )),
              ),
              // Overflow menu (More)
              Builder(builder: (buttonContext) {
                return IconButton(
                  icon: const Icon(Icons.more_vert),
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
                      color: Theme.of(buttonContext)
                          .colorScheme
                          .surfaceContainerHigh,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                                const SizedBox(width: 12),
                                const Text('Cast to device'),
                                const Spacer(),
                                if (isCastConnected)
                                  Icon(Icons.circle,
                                      size: 8,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                              ])),
                        PopupMenuItem(
                            value: 'openExternal',
                            child: Row(children: [
                              Icon(Icons.open_in_browser,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                              const SizedBox(width: 12),
                              const Text('Open in browser'),
                            ])),
                        PopupMenuItem(
                            value: 'copyLink',
                            child: Row(children: [
                              Icon(Icons.copy,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                              const SizedBox(width: 12),
                              const Text('Copy link'),
                            ])),
                        PopupMenuItem(
                            value: 'share',
                            child: Row(children: [
                              Icon(Icons.share,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                              const SizedBox(width: 12),
                              const Text('Share'),
                            ])),
                        PopupMenuItem(
                            value: 'addCookies',
                            child: Row(children: [
                              Icon(Icons.cookie_outlined,
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                              const SizedBox(width: 12),
                              const Text('Add cookies (for downloads)'),
                            ])),
                      ],
                    );
                    if (selection != null) onMenuAction(selection);
                  },
                );
              }),
            ],
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
    if (host.isEmpty) return pageTitle.isNotEmpty ? pageTitle : 'No site';
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
