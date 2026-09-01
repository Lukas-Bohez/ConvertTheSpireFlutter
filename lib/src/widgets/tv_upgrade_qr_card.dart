import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart'; // NEW dependency — not in pubspec.yaml yet

/// Optional TV polish for the "get the full version from GitHub" flow.
///
/// NOT required for TV support in general. This app already drives D-pad
/// input into both native Flutter UI and WebView page content:
/// GlobalCursorOverlay (lib/src/widgets/global_cursor_overlay.dart) detects
/// Android TV via the existing `isAndroidTV` platform channel and runs a
/// virtual cursor app-wide, and BrowserScreen
/// (lib/src/screens/browser_screen.dart) already has its own D-pad-to-JS-tap
/// injection for webview content (_injectTap/_injectScroll, coordinated
/// with pauseCursor()/resumeCursor()). So pointing a TV user at the in-app
/// browser for the GitHub releases page already works today, at least
/// mechanically — this widget doesn't fix a broken capability.
///
/// What it's actually for: even with working D-pad-into-webview, driving a
/// full GitHub releases page with a cursor to find the right asset link is
/// slower and fiddlier than scanning a code with a phone that's already
/// signed into GitHub. Offer this ALONGSIDE "open in the in-app browser"
/// as a faster second option on TV — not instead of it, and not framed as
/// a fix for something that doesn't work.
///
/// Wire this into the existing UpgradeDialog
/// (masterprompt_bitplayer_fullversion_tv.md, Module 1) behind an
/// `AndroidSaf().isAndroidTV()` check — see lib/src/services/android_saf.dart,
/// the same detector GlobalCursorOverlay itself uses.
class TvUpgradeQrCard extends StatelessWidget {
  final String releaseUrl;

  const TvUpgradeQrCard({super.key, required this.releaseUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: releaseUrl,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              'Scan with your phone to open the full-version release page',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              releaseUrl,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
