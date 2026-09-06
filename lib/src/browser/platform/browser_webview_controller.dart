import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Platform-neutral abstraction over the WebView backing the in-app browser.
///
/// Two implementations exist:
///  - `BrowserInAppWebViewAdapter` (Android/iOS/macOS) wrapping
///    `flutter_inappwebview`.
///  - `BrowserWindowsWebViewAdapter` (Windows) wrapping `webview_windows`
///    (WebView2). The Windows one exists because `flutter_inappwebview`'s
///    Windows plugin ships a binary containing BMI2 instructions that crash
///    with `EXCEPTION_ILLEGAL_INSTRUCTION` on older CPUs (see
///    todo/masterprompt_bitplayer_crash_root_cause.md). On Windows the
///    plugin's Dart API is therefore never touched at all.
///
/// The implementations are chosen at runtime by `BrowserWebviewFactory`;
/// no conditional imports are needed because merely *compiling* the
/// `flutter_inappwebview` Dart code on Windows is harmless - only calling
/// into it touches the native plugin.
abstract class BrowserWebviewController {
  /// The platform widget that renders the web content.
  Widget buildWidget();

  Future<void> loadUrl(String url);
  Future<void> reload();
  Future<void> stop();
  Future<void> goBack();
  Future<void> goForward();
  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<String?> getTitle();

  /// Runs [js] in the page and returns the raw result (may be null).
  Future<Object?> evaluateJs(String js);

  /// Applies user-agent / incognito style settings.
  Future<void> applySettings({required bool desktopMode, required bool incognito});

  /// Screenshot of the current page for tab previews, or null when the
  /// platform cannot capture one (Windows).
  Future<Uint8List?> takeScreenshot();

  /// Find-in-page support. Returns the number of matches where the
  /// platform can count them, otherwise -1.
  Future<int> findInPage(String query);
  Future<void> findNext({bool forward = true});
  Future<void> clearFind();

  // -- Event streams (broadcast-style; the screen subscribes once) --

  /// Page load lifecycle: [BrowserPageEvent.isStart] distinguishes
  /// start-of-load from completion.
  Stream<BrowserPageEvent> get pageEvents;

  /// Load progress from 0.0 to 1.0. Windows reports 0 on start and 1 on
  /// completion (WebView2 exposes no incremental progress).
  Stream<double> get progressEvents;

  /// Messages sent from page JS through the shared `__bbCall` bridge
  /// (see js_bridge.dart). [BrowserJsMessage.handler] is the handler name,
  /// [BrowserJsMessage.payload] the raw JSON/string payload.
  Stream<BrowserJsMessage> get jsMessages;

  /// Current URL after every navigation / history update.
  Stream<String> get urlEvents;

  /// Console log lines (debug aid; may be empty on some platforms).
  Stream<String> get consoleEvents;

  /// Navigation errors for main-frame loads.
  Stream<BrowserErrorEvent> get errorEvents;

  /// Back/forward availability changes.
  Stream<BrowserHistoryState> get historyEvents;

  /// Scroll position updates (y in content pixels). May be empty on
  /// platforms that don't report scrolling.
  Stream<int> get scrollEvents;

  Future<void> dispose();
}

class BrowserPageEvent {
  final bool isStart;
  final String url;
  const BrowserPageEvent({required this.isStart, required this.url});
}

class BrowserJsMessage {
  final String handler;
  final String payload;
  const BrowserJsMessage({required this.handler, required this.payload});
}

class BrowserErrorEvent {
  final String url;
  final String description;
  final bool isMainFrame;
  const BrowserErrorEvent({
    required this.url,
    required this.description,
    required this.isMainFrame,
  });
}

class BrowserHistoryState {
  final bool canGoBack;
  final bool canGoForward;
  const BrowserHistoryState({required this.canGoBack, required this.canGoForward});
}

/// Optional navigation hooks. Only honoured by platforms that can
/// intercept requests (Android). Used for external-protocol handling and
/// per-request ad blocking / video sniffing.
class BrowserWebViewHooks {
  /// Return false to cancel a main-frame navigation (e.g. external
  /// `tel:`/`mailto:` schemes).
  Future<bool> Function(String url)? shouldAllowNavigation;

  /// Return true to block a resource request (ad-block, video sniffing
  /// side effects happen inside the callback).
  bool Function(String url)? shouldBlockResource;
}

// Keep `Offset` referenced so the dart:ui import stays meaningful for
// implementers that need it (cursor tap coordinates are injected via JS).
typedef BrowserOffset = Offset;
