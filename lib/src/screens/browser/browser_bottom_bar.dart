import 'package:flutter/material.dart';

/// Bottom bar for the browser with tabs count, home, and favourite toggle.
class BrowserBottomBar extends StatelessWidget {
  final int tabCount;
  final bool isFavourited;
  final VoidCallback onHome;
  final VoidCallback onTabs;
  final VoidCallback onFavourite;
  final double bottomPadding;

  const BrowserBottomBar({
    super.key,
    required this.tabCount,
    required this.isFavourited,
    required this.onHome,
    required this.onTabs,
    required this.onFavourite,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SizedBox(
        height: 48,
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
            // Favourite toggle — filled when page is bookmarked
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
    );
  }
}
