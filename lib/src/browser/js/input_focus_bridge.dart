/// Raw JavaScript injected into the browser WebView so that focusing a
/// text field on a page opens the app's on-screen "type bar" overlay.
///
/// Fix (2026-08): the previous version forwarded *every* `focusin` event
/// to Flutter, including ones a page triggers on itself with no tap
/// involved at all - the most common case being a search results page
/// (Google's included) re-focusing its own search box after a search is
/// submitted, or any page that autofocuses a field on load. That made the
/// type bar pop back open right after the user had already searched and
/// moved on to reading results, with no way to tell it to stay closed.
///
/// This version only forwards a `focusin` when it happened shortly after a
/// real pointerdown / touchstart / mousedown, so the overlay now only
/// appears when the user actually taps the field - matching how the
/// overlay is supposed to behave everywhere else in the app.
///
/// See BROWSER_UX_REDESIGN.md for the full write-up, the previous
/// behaviour, and how this plugs into browser_screen.dart.
const String inputFocusBridgeJs = """
  if (!window.__cursorListenersInjected) {
    window.__cursorListenersInjected = true;

    // Timestamp of the last real, physical pointer interaction (touch,
    // mouse, or the app's own synthetic remote-control tap dispatched by
    // _injectTap). Used to tell a genuine tap on a field apart from a page
    // focusing an input on its own.
    window.__lastUserGestureAt = 0;
    var _markGesture = function() { window.__lastUserGestureAt = Date.now(); };
    document.addEventListener('pointerdown', _markGesture, true);
    document.addEventListener('touchstart', _markGesture, true);
    document.addEventListener('mousedown', _markGesture, true);

    // How recently a real gesture must have happened for a focus event to
    // count as "the user tapped this field". Generous enough to cover the
    // full synthetic tap sequence dispatched by _injectTap (five chained
    // events), tight enough to ignore a page re-focusing a field on its
    // own well after the user's last touch.
    var GESTURE_WINDOW_MS = 600;

    document.addEventListener('focusin', function(e) {
      try {
        var sinceGesture = Date.now() - window.__lastUserGestureAt;
        if (sinceGesture > GESTURE_WINDOW_MS) {
          // Not caused by a tap/click just now - most likely the page
          // focusing itself programmatically. Don't pop the type bar
          // open for this.
          return;
        }
        var tag = e.target && e.target.tagName ? e.target.tagName.toLowerCase() : '';
        var kind = 'input';
        if (tag === 'input' || tag === 'textarea' || (e.target && e.target.isContentEditable)) {
          if (tag === 'textarea') {
            kind = 'textarea';
          } else if (e.target && e.target.isContentEditable) {
            kind = 'contenteditable';
          }
          window.__flutterFocusedInput = e.target;
          window.__flutterFocusedInputKind = kind;
          var val = tag === 'textarea'
            ? (e.target.value || '')
            : (e.target.isContentEditable ? (e.target.innerText || '') : (e.target.value || ''));
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('InputFocusChannel', JSON.stringify({ value: val, kind: kind }));
          }
        }
      } catch(ex){}
    });
    document.addEventListener('focusout', function(e) {
      try {
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('InputFocusChannel', '__blur__');
        }
      } catch(ex){}
    });
    if (!window.__keyBlocker) {
      window.__keyBlocker = true;
      document.addEventListener('keydown', function(e) {
        if (['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Enter'].includes(e.key)) {
          e.preventDefault(); e.stopImmediatePropagation();
        }
      }, true);
    }
  }
""";
