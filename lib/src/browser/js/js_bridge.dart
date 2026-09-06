/// Shared JS bridge injected into every page before the other feature
/// scripts run.
///
/// Feature scripts (video detection, input focus, playback listeners) call
/// `window.__bbCall(handlerName, payload)` instead of touching either
/// plugin's API directly. The shim forwards to whichever host is present:
///
///  - `webview_windows` (Windows): `window.chrome.webview.postMessage`,
///    wrapped in a JSON envelope `{handler, payload}` that the Windows
///    adapter unwraps from its `webMessage` stream.
///  - `flutter_inappwebview` (Android/iOS): `callHandler`.
///
/// Because the shim is platform-agnostic it can be prepended to every
/// injected script unconditionally, which keeps the feature scripts
/// identical across platforms.
const String jsBridgeShimJs = r'''
if (!window.__bbCall) {
  window.__bbCall = function(name, payload) {
    try {
      if (window.chrome && window.chrome.webview && typeof window.chrome.webview.postMessage === 'function') {
        window.chrome.webview.postMessage(JSON.stringify({ handler: name, payload: payload }));
      } else if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
        window.flutter_inappwebview.callHandler(name, payload);
      }
    } catch (e) {
      // swallow - the bridge must never throw inside a page
    }
  };
}
''';

/// Convenience wrapper used by Dart-side scripts that build JS strings.
String withJsBridge(String script) => '$jsBridgeShimJs\n$script';
