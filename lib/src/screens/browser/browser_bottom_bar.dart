import 'package:flutter/material.dart';

/// Bottom bar for the browser with tabs count, home, and favourite toggle.
///
/// Redesigned 2026-08: the bar used to be permanently on screen, taking a
/// fixed 48px+ slice of vertical space away from the page on every single
/// site, whether the user was scrolling or not. It now animates its own
/// *height* down to zero when [visible] is false, so the WebView above it
/// actually gains that space back instead of the bar just visually
/// sliding away while still reserving room for itself. Pair this with
/// [BrowserChromeVisibility] in browser_screen.dart to drive [visible]
/// from real scroll events - see BROWSER_UX_REDESIGN.md.
///
/// [visible] defaults to true, so dropping this file in on its own
/// (before wiring up a controller) behaves exactly like the bar always
/// did.
class BrowserBottomBar extends StatelessWidget {
  static const double barHeight = 48;

  final int tabCount;
  final bool isFavourited;
  final VoidCallback onHome;
  final VoidCallback onTabs;
  final VoidCallback onFavourite;
  final double bottomPadding;
  final bool visible;

  const BrowserBottomBar({
    super.key,
    required this.tabCount,
    required this.isFavourited,
    required this.onHome,
    required this.onTabs,
    required this.onFavourite,
    required this.bottomPadding,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        heightFactor: visible ? 1.0 : 0.0,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            border: Border(
              top: BorderSide(
                  color: cs.outline.withValues(alpha: 0.4), width: 1),
            ),
          ),
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: SizedBox(
            height: barHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Tabs button with count badge
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.tab),
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$tabCount',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  onPressed: onTabs,
                ),
                // Home
                IconButton(
                  icon: const Icon(Icons.home_outlined),
                  onPressed: onHome,
                ),
                // Favourite toggle - filled when page is bookmarked
                IconButton(
                  icon: Icon(
                    isFavourited ? Icons.favorite : Icons.favorite_border,
                    color: isFavourited ? Colors.red : null,
                  ),
                  onPressed: onFavourite,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
