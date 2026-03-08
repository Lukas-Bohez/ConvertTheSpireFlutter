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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = isIncognito
        ? const Color(0xFF1A1A2E)
        : cs.surface;
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
                        style: TextStyle(
                          fontSize: 13,
                          color: isIncognito ? Colors.white : null,
                        ),
                        onSubmitted: onSubmitted,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Search or enter URL…',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: isIncognito
                                ? Colors.white54
                                : cs.outline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Reload / Stop
            IconButton(
              padding: const EdgeInsets.all(4),
              visualDensity: VisualDensity.compact,
              icon: Icon(isLoading ? Icons.close : Icons.refresh, size: 20),
              onPressed: onReload,
            ),
            // Cast button with pulsing badge
            Stack(
              children: [
                IconButton(
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.cast, size: 20),
                  onPressed: onCastTap,
                ),
                if (hasVideos)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: AnimatedBuilder(
                      animation: castBadgeAnimation,
                      builder: (_, __) => Opacity(
                        opacity:
                            0.4 + 0.6 * castBadgeAnimation.value,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Overflow menu
            PopupMenuButton<String>(
              padding: const EdgeInsets.all(4),
              icon: Icon(Icons.more_vert, size: 20, color: iconColor),
              onSelected: onMenuAction,
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'new_tab', child: Text('New Tab')),
                const PopupMenuItem(
                    value: 'incognito',
                    child: Text('New Incognito Tab')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'add_favourite',
                    child: Text('Add to Favourites')),
                const PopupMenuItem(
                    value: 'share', child: Text('Share URL')),
                PopupMenuItem(
                  value: 'desktop_mode',
                  child: Row(
                    children: [
                      const Expanded(child: Text('Desktop Mode')),
                      if (desktopMode)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'adblock',
                  child: Row(
                    children: [
                      const Expanded(child: Text('Ad Block')),
                      if (adBlockEnabled)
                        const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
                const PopupMenuItem(
                    value: 'download',
                    child: Text('Download Current')),
                const PopupMenuItem(
                    value: 'find',
                    child: Text('Find in Page')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'external',
                    child: Text('Open in External Browser')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
