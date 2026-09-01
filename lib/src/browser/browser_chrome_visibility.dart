import 'package:flutter/foundation.dart';

/// Decides when the browser's bottom bar should be shown or hidden.
///
/// Mirrors how Chrome/Safari's mobile bottom bar behaves: visible by
/// default, hides while the page is actively being scrolled down, and
/// comes back on any upward scroll or once the page is back near the top.
/// This replaces the previous behaviour, where the bar had no visibility
/// state at all and simply sat on screen permanently, always taking a
/// fixed slice of vertical space away from the page.
///
/// Callers feed this raw WebView scroll positions via [onScroll] (e.g.
/// from `InAppWebView.onScrollChanged`) and call [forceShow] on events
/// where the bar should never start out hidden - a fresh page load,
/// returning to the New Tab page, opening the tab switcher, and so on.
///
/// Pure Dart, no Flutter widget dependencies - safe to unit test on its
/// own. See BROWSER_UX_REDESIGN.md for the full write-up and how this
/// plugs into browser_screen.dart / browser_bottom_bar.dart.
class BrowserChromeVisibility extends ChangeNotifier {
  /// Minimum downward scroll (in content pixels) between two onScroll
  /// calls before the bar hides. Filters out tiny/accidental jitter so
  /// the bar doesn't flicker on a page that barely moves.
  final int hideThreshold;

  /// Content y-position below which the bar always stays visible, even
  /// while scrolling down - keeps it from disappearing the moment a short
  /// page starts to scroll, or right at the top of any page.
  final int topGuardZone;

  BrowserChromeVisibility({
    this.hideThreshold = 12,
    this.topGuardZone = 24,
  });

  bool _visible = true;
  int _lastY = 0;

  bool get visible => _visible;

  /// Feed this the WebView's onScrollChanged y position each time it
  /// fires. Safe to call every frame - it only notifies listeners when
  /// [visible] actually changes.
  void onScroll(int y) {
    final delta = y - _lastY;
    _lastY = y;

    if (y <= topGuardZone) {
      _setVisible(true);
      return;
    }
    if (delta > hideThreshold) {
      _setVisible(false);
    } else if (delta < -hideThreshold) {
      _setVisible(true);
    }
  }

  /// Call on any event where the bar should be guaranteed visible again -
  /// a new page starting to load, returning home, opening the tab
  /// switcher, toggling the New Tab page, etc.
  void forceShow() {
    _lastY = 0;
    _setVisible(true);
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }
}
