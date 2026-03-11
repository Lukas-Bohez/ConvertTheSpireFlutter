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
  final ValueChanged<String> onMenuAction;
  final VoidCallback? onUrlBarTap;

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
    required this.onMenuAction,
    this.onUrlBarTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // always ensure a light toolbar on mobile unless in incognito mode; dark
    // themes make the toolbar blend with the rest of the app, which looks bad
    // inside the browser.  Desktop respects the global surface color.
    final bool forceLight = !isIncognito &&
        (Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS);
    final bgColor = isIncognito
        ? const Color(0xFF1A1A2E)
        : (forceLight ? Colors.white : cs.surface);
    final iconColor = isIncognito
        ? Colors.white
        : (forceLight ? Colors.black : cs.onSurface);

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
                          : (isIncognito
                              ? Colors.white54
                              : cs.outline),
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
                        onTap: onUrlBarTap,
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            hintText: pageTitle.isNotEmpty ? pageTitle : 'Search or enter URL',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: isIncognito ? Colors.white54 : cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Reload
                      IconButton(
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: onReload,
                      ),
                      // Cast
                      IconButton(
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.cast, size: 20),
                        onPressed: onCastTap,
                      ),
                      // Menu
                      PopupMenuButton<String>(
                        onSelected: onMenuAction,
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'open_in_browser', child: Text('Open in browser')),
                          const PopupMenuItem(value: 'share', child: Text('Share')),
                        ],
                      ),
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