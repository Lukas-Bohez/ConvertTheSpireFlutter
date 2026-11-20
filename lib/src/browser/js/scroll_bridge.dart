import 'dart:ui' show Offset;

/// Scrolls a page for a TV remote or the on-screen cursor.
///
/// The cursor sits in the top or bottom edge zone to scroll, and that is
/// exactly where most pages have a fixed header or footer. The old script
/// scrolled whatever scrollable parent the element under the cursor had, so
/// over a header it found none and fell back to `window`, which does nothing
/// on pages whose content scrolls inside their own container: scrolling down
/// (cursor over the content) worked and scrolling up (cursor over the
/// header) did not.
///
/// This one looks at every element under the cursor, then at the container
/// scrolled last, then at the page, then at the biggest scrollable container
/// on the page, and only scrolls one that can still move in that direction.
/// `behavior: 'instant'` matters: on pages with `scroll-behavior: smooth`
/// every small step restarted the animation and the page crawled or stood
/// still.
String pageScrollScript(double deltaY, Offset position) => '''
(function(dy, x, y) {
  var S = window.__ctsScroll || (window.__ctsScroll = { last: null, scanned: 0 });
  var root = document.scrollingElement || document.documentElement;
  function isRoot(el) {
    return el === root || el === document.documentElement || el === document.body;
  }
  function canScroll(el) {
    if (!el || el.nodeType !== 1) return false;
    if (!isRoot(el)) {
      var oy = getComputedStyle(el).overflowY;
      if (oy !== 'auto' && oy !== 'scroll' && oy !== 'overlay') return false;
    }
    if (el.scrollHeight <= el.clientHeight + 1) return false;
    return dy < 0
        ? el.scrollTop > 0
        : el.scrollTop + el.clientHeight < el.scrollHeight - 1;
  }
  function find() {
    var under = document.elementsFromPoint ? document.elementsFromPoint(x, y)
        : [document.elementFromPoint(x, y)];
    for (var i = 0; i < under.length; i++) {
      for (var el = under[i]; el; el = el.parentElement) {
        if (canScroll(el)) return el;
      }
    }
    if (canScroll(S.last)) return S.last;
    if (canScroll(root)) return root;
    var now = Date.now();
    if (now - S.scanned < 400) return null;
    S.scanned = now;
    var best = null, bestArea = 0, all = document.body ? document.body.querySelectorAll('*') : [];
    for (var j = 0; j < all.length; j++) {
      var c = all[j];
      if (c.clientHeight * c.clientWidth > bestArea && canScroll(c)) {
        best = c;
        bestArea = c.clientHeight * c.clientWidth;
      }
    }
    return best;
  }
  var target = find();
  if (!target) return;
  S.last = target;
  var scroller = isRoot(target) ? window : target;
  try {
    scroller.scrollBy({ top: dy, left: 0, behavior: 'instant' });
  } catch (e) {
    if (scroller === window) { window.scrollBy(0, dy); } else { target.scrollTop += dy; }
  }
})(${deltaY.toStringAsFixed(2)}, ${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)});
''';

/// Turns the cursor's tiny per-frame scroll steps (a few pixels every 16 ms)
/// into whole pixels, and never has more than one script running in the page.
///
/// Steps below one pixel were rounded away by the browser, so a slow scroll
/// up did nothing at all. They are added up here until they are worth a
/// pixel, and steps that arrive while a script runs are merged into the next.
class WebViewScroller {
  WebViewScroller(this._run);

  final Future<void> Function(String script) _run;
  double _pending = 0;
  Offset _position = Offset.zero;
  bool _running = false;

  Future<void> scroll(double deltaY, Offset position) async {
    _pending += deltaY;
    _position = position;
    if (_running) return;
    _running = true;
    try {
      while (_pending.abs() >= 1) {
        final step = _pending.truncate();
        _pending -= step;
        await _run(pageScrollScript(step.toDouble(), _position));
      }
    } finally {
      _running = false;
    }
  }
}
