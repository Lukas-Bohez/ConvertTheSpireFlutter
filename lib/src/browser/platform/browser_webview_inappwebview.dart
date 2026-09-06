import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_webview_controller.dart';

/// Android/iOS/macOS implementation backed by `flutter_inappwebview`.
class BrowserInAppWebViewAdapter implements BrowserWebviewController {
  BrowserInAppWebViewAdapter({
    FindInteractionController? findInteractionController,
    BrowserWebViewHooks? hooks,
  })  : _findInteractionController = findInteractionController,
        _hooks = hooks ?? BrowserWebViewHooks();

  final FindInteractionController? _findInteractionController;
  // ignore: unused_field
  final BrowserWebViewHooks _hooks;

  InAppWebViewController? _controller;
  bool _desktopMode = false;
  bool _incognito = false;
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
      key: const ValueKey('browser_webview'),
      initialSettings: _buildSettings(),
      findInteractionController: _findInteractionController,
      onWebViewCreated: (controller) => _controller = controller,
      onLoadStart: _handleLoadStart,
      onLoadStop: _handleLoadStop,
      onProgressChanged: (controller, progress) =>
          _progressEvents.add(progress / 100.0),
      shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
      shouldInterceptRequest: _shouldInterceptRequest,
      onConsoleMessage: (controller, message) =>
          _consoleEvents.add(message.message),
      onReceivedError: (controller, request, error) => _errorEvents.add(
        BrowserErrorEvent(
          url: request.url.toString(),
          description: error.description,
          isMainFrame: request.isForMainFrame ?? false,
        ),
      ),
      onScrollChanged: (controller, x, y) => _scrollEvents.add(y),
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
        // Open new-window requests in the same WebView (previous behaviour).
        final url = createWindowAction.request.url;
        if (url != null) {
          _jsMessages.add(BrowserJsMessage(
              handler: 'onCreateWindow', payload: url.toString()));
        }
        return false;
      },
    );
  }

  InAppWebViewSettings _buildSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useHybridComposition: true,
      transparentBackground: false,
      useShouldInterceptRequest: true,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      allowContentAccess: true,
      allowFileAccess: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      incognito: _incognito,
      userAgent: _desktopMode
          ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
          : null,
    );
  }

  void _handleLoadStart(InAppWebViewController controller, WebUri? url) {
    final urlStr = url?.toString() ?? '';
    _lastUrl = urlStr;
    _pageEvents.add(BrowserPageEvent(isStart: true, url: urlStr));
  }

  Future<void> _handleLoadStop(
      InAppWebViewController controller, WebUri? url) async {
    final urlStr = url?.toString() ?? _lastUrl ?? '';
    _pageEvents.add(BrowserPageEvent(isStart: false, url: urlStr));
  }

  Future<NavigationActionPolicy?> _shouldOverrideUrlLoading(
      InAppWebViewController controller, NavigationAction action) async {
    final hook = _hooks.shouldAllowNavigation;
    if (hook != null) {
      final allowed = await hook(action.request.url?.toString() ?? '');
      if (!allowed) return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<WebResourceResponse?> _shouldInterceptRequest(
      InAppWebViewController controller, WebResourceRequest request) async {
    final hook = _hooks.shouldBlockResource;
    if (hook != null && hook(request.url.toString())) {
      return WebResourceResponse(data: Uint8List(0));
    }
    return null;
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
  Future<void> applySettings(
      {required bool desktopMode, required bool incognito}) async {
    _desktopMode = desktopMode;
    _incognito = incognito;
    await _controller?.setSettings(settings: _buildSettings());
  }

  @override
  Future<Uint8List?> takeScreenshot() async {
    try {
      final bytes = await _controller?.takeScreenshot();
      return bytes is Uint8List && bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> findInPage(String query) async {
    final find = _findInteractionController;
    if (find == null) return -1;
    await find.findAll(find: query);
    // Match count arrives asynchronously via the FindInteractionController
    // callback owned by the screen.
    return -1;
  }

  @override
  Future<void> findNext({bool forward = true}) async =>
      _findInteractionController?.findNext(forward: forward);

  @override
  Future<void> clearFind() async =>
      _findInteractionController?.clearMatches();

  /// Exposed so the screen can keep its match-count callback wired up.
  FindInteractionController? get findInteractionController =>
      _findInteractionController;

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
