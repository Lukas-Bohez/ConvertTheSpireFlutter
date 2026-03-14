import 'package:flutter/material.dart';

/// Top toolbar for the browser with URL bar, navigation, cast button, and menu.
class BrowserToolbar extends StatelessWidget {
  final TextEditingController addressController;
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
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCastTap;
  final VoidCallback? onDownload;
  final bool isDownloading;
  final bool downloadEnabled;
  final bool isKnownDifficultSite;
  final bool isCastConnected;
  final ValueChanged<String> onMenuAction;
  final VoidCallback? onUrlBarTap;
  final VoidCallback? onReleaseWebViewFocus;
  final VoidCallback onTabs;
  final int tabCount;

  const BrowserToolbar({
    super.key,
    required this.addressController,
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
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onSubmitted,
    required this.onCastTap,
    this.onDownload,
    this.isDownloading = false,
    this.downloadEnabled = false,
    this.isKnownDifficultSite = false,
    this.isCastConnected = false,
    required this.onMenuAction,
    this.onUrlBarTap,
    this.onReleaseWebViewFocus,
    required this.onTabs,
    this.tabCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // always ensure a light toolbar on mobile unless in incognito mode; dark
    // themes make the toolbar blend with the rest of the app, which looks bad
    // inside the browser.  Desktop respects the global surface color.
    final bgColor = isIncognito
        ? const Color(0xFF1A1A2E)
        : cs.surface; // avoid hardcoded white; use theme surface
    final iconColor = isIncognito ? Colors.white : cs.onSurface;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: IconTheme(
        data: IconThemeData(color: iconColor),
        child: Row(
          children: [
            // Back
            IconButton(
              padding: const EdgeInsets.all(4),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: canGoBack ? onBack : null,
            ),
            // Forward
            IconButton(
              padding: const EdgeInsets.all(4),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_forward, size: 20),
              onPressed: canGoForward ? onForward : null,
            ),
            // URL bar
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isIncognito
                      ? Colors.white.withValues(alpha: 0.1)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    // SSL indicator
                    Icon(
                      isSecure ? Icons.lock : Icons.lock_open,
                      size: 14,
                      color: isSecure
                          ? Colors.green
                          : (isIncognito ? Colors.white54 : cs.outline),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: addressController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          color: isIncognito ? Colors.white : null,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onSubmitted: onSubmitted,
                        onTap: () {
                          // Select all text when the URL bar is tapped (standard browser UX)
                          addressController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: addressController.text.length,
                          );
                        },
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 8),
                          hintText: pageTitle.isNotEmpty
                              ? pageTitle
                              : 'Search or enter URL',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isIncognito
                                ? Colors.white54
                                : cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Tabs button
                    IconButton(
                      padding: const EdgeInsets.all(4),
                      visualDensity: VisualDensity.compact,
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.tab_rounded, size: 20),
                          if (tabCount > 1)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                constraints: const BoxConstraints(
                                    minWidth: 14, minHeight: 14),
                                child: Text(
                                  '$tabCount',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      onPressed: () {
                        onReleaseWebViewFocus?.call();
                        onTabs();
                      },
                      tooltip: 'Tabs',
                    ),

                    // Reload
                    IconButton(
                      padding: const EdgeInsets.all(4),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: onReload,
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
                                  padding: const EdgeInsets.all(4),
                                  visualDensity: VisualDensity.compact,
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

                    // Overflow menu (More) — use explicit showMenu so we can
                    // release WebView focus on Windows before the native
                    // WebView2 consumes the click. Uses onMenuAction via
                    // onSelected to remain safe for navigation.
                    Builder(builder: (buttonContext) {
                      return IconButton(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'More options',
                        onPressed: () async {
                          onReleaseWebViewFocus?.call();
                          // Ask the parent to refresh tab preview before opening menu.
                          try {
                            onMenuAction('menu_open');
                          } catch (_) {}

                          // Compute a sensible position for the menu using this
                          // button's RenderBox so the menu is anchored to it.
                          final RenderBox button =
                              buttonContext.findRenderObject() as RenderBox;
                          final Offset buttonPos = button.localToGlobal(Offset.zero);
                          final Size buttonSize = button.size;
                          final RenderBox overlay =
                              Overlay.of(buttonContext).context.findRenderObject()
                                  as RenderBox;

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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                  const SizedBox(width: 12),
                                  const Text('Open in browser'),
                                ])),
                            PopupMenuItem(
                                value: 'copyLink',
                                child: Row(children: [
                                  Icon(Icons.copy,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                  const SizedBox(width: 12),
                                  const Text('Copy link'),
                                ])),
                            PopupMenuItem(
                                value: 'share',
                                child: Row(children: [
                                  Icon(Icons.share,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
                                  const SizedBox(width: 12),
                                  const Text('Share'),
                                ])),
                            PopupMenuItem(
                                value: 'addCookies',
                                child: Row(children: [
                                  Icon(Icons.cookie_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface),
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
          ],
        ),
      ),
    );
  }
}
