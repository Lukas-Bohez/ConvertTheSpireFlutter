import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_webview_controller.dart';

/// Web platform implementation backed by `flutter_inappwebview`'s web support.
///
/// On web, `flutter_inappwebview` renders content inside an `<iframe>` via
/// the `web_support.js` helper. This adapter exposes the same
/// [BrowserWebviewController] surface as the native adapters so the browser
/// screen works identically across web, Android, iOS, macOS, and Windows.
///
/// Known limitations vs the native implementations:
///  - No per-request interception: ad-block runs as an injected JS hook.
///  - No incremental load progress (0 at start, 1 on completion).
///  - No tab-preview screenshots (`takeScreenshot` always returns null).
///  - Incognito mode is a no-op (web has no profile isolation).
class BrowserWebWebViewAdapter implements BrowserWebviewController {
  BrowserWebWebViewAdapter({
    BrowserWebViewHooks? hooks,
  }) : _hooks = hooks ?? BrowserWebViewHooks();

  final BrowserWebViewHooks _hooks;

  InAppWebViewController? _controller;
  String? _lastUrl;

  final _pageEvents = StreamController<BrowserPageEvent>.broadcast();
  final _progressEvents = StreamController<double>.broadcast();
  final _jsMessages = StreamController<BrowserJsMessage>.broadcast();
  final _urlEvents = StreamController<String>.broadcast();
  final _consoleEvents = StreamController<String>.broadcast();
  final _errorEvents = StreamController<BrowserErrorEvent>.broadcast();
  final _historyEvents = StreamController<BrowserHistoryState>.broadcast();
  final _scrollEvents = StreamController<int>.broadcast();

  @override
  Stream<BrowserPageEvent> get pageEvents => _pageEvents.stream;
  @override
  Stream<double> get progressEvents => _progressEvents.stream;
  @override
  Stream<BrowserJsMessage> get jsMessages => _jsMessages.stream;
  @override
  Stream<String> get urlEvents => _urlEvents.stream;
  @override
  Stream<String> get consoleEvents => _consoleEvents.stream;
  @override
  Stream<BrowserErrorEvent> get errorEvents => _errorEvents.stream;
  @override
  Stream<BrowserHistoryState> get historyEvents => _historyEvents.stream;
  @override
  Stream<int> get scrollEvents => _scrollEvents.stream;

  @override
  Widget buildWidget() {
    return InAppWebView(
      key: const ValueKey('browser_webview_web'),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: true,
        databaseEnabled: true,
        cacheEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useWideViewPort: true,
        loadWithOverviewMode: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onLoadStart: (controller, url) {
        final urlStr = url?.toString() ?? '';
        _lastUrl = urlStr;
        _pageEvents.add(BrowserPageEvent(isStart: true, url: urlStr));
        _progressEvents.add(0);
      },
      onLoadStop: (controller, url) async {
        final urlStr = url?.toString() ?? _lastUrl ?? '';
        _pageEvents.add(BrowserPageEvent(isStart: false, url: urlStr));
        _progressEvents.add(1);
      },
      onProgressChanged: (controller, progress) {
        _progressEvents.add(progress / 100.0);
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final hook = _hooks.shouldAllowNavigation;
        if (hook != null) {
          final allowed = await hook(action.request.url?.toString() ?? '');
          if (!allowed) return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onConsoleMessage: (controller, message) {
        _consoleEvents.add(message.message);
      },
      onReceivedError: (controller, request, error) {
        _errorEvents.add(BrowserErrorEvent(
          url: request.url.toString(),
          description: error.description,
          isMainFrame: request.isForMainFrame ?? false,
        ));
      },
      onScrollChanged: (controller, x, y) {
        _scrollEvents.add(y);
      },
      onUpdateVisitedHistory: (controller, url, androidIsReload) {
        final urlStr = url?.toString() ?? '';
        if (urlStr.isEmpty || urlStr == 'about:blank') return;
        _urlEvents.add(urlStr);
      },
      onDownloadStartRequest: (controller, request) {
        _jsMessages.add(BrowserJsMessage(
            handler: 'onDownloadStart', payload: request.url.toString()));
      },
      onCreateWindow: (controller, createWindowAction) async {
        final url = createWindowAction.request.url;
        if (url != null) {
          _jsMessages.add(BrowserJsMessage(
              handler: 'onCreateWindow', payload: url.toString()));
        }
        return false;
      },
    );
  }

  @override
  Future<void> loadUrl(String url) async {
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  @override
  Future<void> reload() async => _controller?.reload();

  @override
  Future<void> stop() async => _controller?.stopLoading();

  @override
  Future<void> goBack() async => _controller?.goBack();

  @override
  Future<void> goForward() async => _controller?.goForward();

  @override
  Future<bool> canGoBack() async => await _controller?.canGoBack() ?? false;

  @override
  Future<bool> canGoForward() async =>
      await _controller?.canGoForward() ?? false;

  @override
  Future<String?> getTitle() async => await _controller?.getTitle();

  @override
  Future<Object?> evaluateJs(String js) async =>
      await _controller?.evaluateJavascript(source: js);

  @override
  Future<void> applySettings({
    required bool desktopMode,
    required bool incognito,
  }) async {
    try {
      await _controller?.setSettings(
        settings: InAppWebViewSettings(
          userAgent: desktopMode
              ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
              : null,
        ),
      );
    } catch (e) {
      debugPrint('[BROWSER_WEB] applySettings failed: $e');
    }
  }

  @override
  Future<Uint8List?> takeScreenshot() async {
    return null;
  }

  @override
  Future<int> findInPage(String query) async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.find) {
          window.find('${query.replaceAll("'", r"\'")}', false, false, true);
        }
      ''');
      return -1;
    } catch (e) {
      return -1;
    }
  }

  @override
  Future<void> findNext({bool forward = true}) async {
    try {
      await _controller?.evaluateJavascript(source: '''
        if (window.find) {
          window.find('', false, ${forward ? 'false' : 'true'}, true);
        }
      ''');
    } catch (_) {}
  }

  @override
  Future<void> clearFind() async {
    try {
      await _controller?.evaluateJavascript(source: '''
        window.getSelection().removeAllRanges();
      ''');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _controller?.stopLoading();
    } catch (_) {}
    for (final c in [
      _pageEvents,
      _progressEvents,
      _jsMessages,
      _urlEvents,
      _consoleEvents,
      _errorEvents,
      _historyEvents,
      _scrollEvents,
    ]) {
      await c.close();
    }
  }
}
