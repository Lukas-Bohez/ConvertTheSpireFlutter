import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import 'browser_webview_controller.dart';

/// Linux implementation, backed by CEF (Chromium) through `webview_cef`.
///
/// Linux has no system webview a Flutter app can rely on, and the ones that
/// exist put a native window on top of Flutter, which hides the app's own
/// overlays: the TV cursor, dialogs, menus. CEF draws the page into a Flutter
/// texture, so everything Flutter paints stays on top of it, and it is
/// Chromium, so pages behave as they do in Chrome.
///
/// Known limits against the other adapters (CEF's plugin does not offer them):
///  - No request interception: the ad blocker's page script runs, its network
///    rules do not ([BrowserWebViewHooks.shouldBlockResource] is unused).
///  - No navigation veto ([BrowserWebViewHooks.shouldAllowNavigation]).
///  - No load errors, load progress (0 at start, 1 at the end), scroll
///    position or tab-preview screenshots.
///  - One user agent for the whole app (set when CEF starts).
///  - Scripts "at document start" run when the load starts, a little after
///    the page's first scripts may have.
class BrowserCefWebViewAdapter implements BrowserWebviewController {
  BrowserCefWebViewAdapter({BrowserWebViewHooks? hooks})
      : _hooks = hooks ?? BrowserWebViewHooks() {
    _controller = WebviewManager().createWebView(
      loading: const Center(child: CircularProgressIndicator()),
    );
  }

  /// The page script reaches Dart through a CEF "JavaScript channel" of this
  /// name (no underscores: the plugin only accepts letters, digits and dots
  /// after the first character); js_bridge.dart's `__bbCall` looks for it.
  static const String bridgeChannel = 'bbCef';

  static const String _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';

  static Future<void>? _managerReady;

  final BrowserWebViewHooks _hooks;
  late final WebViewController _controller;
  Future<void>? _ready;
  bool _disposed = false;

  ContentBlocking? _blocking;
  String _lastUrl = '';
  String _lastQuery = '';
  bool _canGoBack = false;
  bool _canGoForward = false;

  final _pageEvents = StreamController<BrowserPageEvent>.broadcast();
  final _progressEvents = StreamController<double>.broadcast();
  final _jsMessages = StreamController<BrowserJsMessage>.broadcast();
  final _urlEvents = StreamController<String>.broadcast();
  final _consoleEvents = StreamController<String>.broadcast();
  final _titleEvents = StreamController<String>.broadcast();
  final _errorEvents = StreamController<BrowserErrorEvent>.broadcast();
  final _historyEvents = StreamController<BrowserHistoryState>.broadcast();
  final _scrollEvents = StreamController<int>.broadcast();

  /// Starts CEF (once per process) and this browser.
  Future<void> _ensureReady() => _ready ??= _init();

  Future<void> _init() async {
    _managerReady ??= WebviewManager().initialize(userAgent: _userAgent);
    await _managerReady;
    _controller.setWebviewListener(WebviewEventsListener(
      onUrlChanged: (url) {
        _lastUrl = url;
        if (!_urlEvents.isClosed) _urlEvents.add(url);
      },
      onTitleChanged: (title) {
        if (!_titleEvents.isClosed) _titleEvents.add(title);
      },
      onConsoleMessage: (level, message, source, line) {
        if (!_consoleEvents.isClosed) _consoleEvents.add('$message ($source:$line)');
      },
      onLoadStart: (_, url) => unawaited(_onLoadStart(url)),
      onLoadEnd: (_, url) => unawaited(_onLoadEnd(url)),
    ));
    await _controller.initialize('about:blank');
  }

  Future<void> _onLoadStart(String url) async {
    if (_disposed) return;
    if (!_pageEvents.isClosed) {
      _pageEvents.add(BrowserPageEvent(isStart: true, url: url));
      _progressEvents.add(0);
    }
    await _installBridge();
    try {
      final blocking = _blocking;
      if (blocking != null) {
        await _controller.executeJavaScript(blocking.documentStartScript);
      }
    } catch (e) {
      debugPrint('[BROWSER] cef start-of-load setup failed: $e');
    }
    await _injectUserScripts(url, atDocumentStart: true);
  }

  /// The channel lives in the page, so every new page needs it again. It is
  /// installed as the load starts and again when it ends (the first can reach
  /// the document being replaced), and only once the browser is ready: the
  /// plugin refuses it before.
  Future<void> _installBridge() async {
    try {
      await _controller.ready;
      await _controller.setJavaScriptChannels({
        JavascriptChannel(name: bridgeChannel, onMessageReceived: _onBridge),
      });
    } catch (e) {
      debugPrint('[BROWSER] cef bridge install failed: $e');
    }
  }

  Future<void> _onLoadEnd(String url) async {
    if (_disposed) return;
    await _installBridge();
    await _injectUserScripts(url, atDocumentStart: false);
    if (_disposed) return;
    if (!_pageEvents.isClosed) {
      _pageEvents.add(BrowserPageEvent(isStart: false, url: url));
      _progressEvents.add(1);
    }
    unawaited(_refreshHistory());
  }

  void _onBridge(JavascriptMessage message) {
    try {
      // The plugin JSON-encodes what the page sends, so the envelope arrives
      // as a JSON string holding JSON.
      Object? decoded = jsonDecode(message.message);
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map && decoded.containsKey('handler')) {
        final payload = decoded['payload'];
        _jsMessages.add(BrowserJsMessage(
          handler: decoded['handler'].toString(),
          payload: payload is String
              ? payload
              : payload == null
                  ? ''
                  : jsonEncode(payload),
        ));
      }
    } catch (_) {
      // Not ours; the page may call the channel for its own reasons.
    }
  }

  /// Runs the userscripts matching [url], each in its own call so one that
  /// throws cannot stop the rest.
  Future<void> _injectUserScripts(String url,
      {required bool atDocumentStart}) async {
    final provider = _hooks.userScriptsFor;
    if (provider == null || url.isEmpty || url == 'about:blank') return;
    final List<String> sources;
    try {
      sources = provider(url, atDocumentStart: atDocumentStart);
    } catch (e) {
      debugPrint('[BROWSER] userscript lookup failed: $e');
      return;
    }
    for (final source in sources) {
      try {
        await _controller.executeJavaScript(source);
      } catch (e) {
        debugPrint('[BROWSER] userscript injection failed: $e');
      }
    }
  }

  /// CEF's plugin does not report history, so the page is asked: Chromium's
  /// Navigation API knows whether there is an entry before and after.
  Future<void> _refreshHistory() async {
    try {
      final back = await evaluateJsExpression(
          '!!(window.navigation && navigation.canGoBack)');
      final forward = await evaluateJsExpression(
          '!!(window.navigation && navigation.canGoForward)');
      final canBack = back == true || back == 'true';
      final canForward = forward == true || forward == 'true';
      if (canBack != _canGoBack || canForward != _canGoForward) {
        _canGoBack = canBack;
        _canGoForward = canForward;
        if (!_historyEvents.isClosed) {
          _historyEvents.add(BrowserHistoryState(
              canGoBack: canBack, canGoForward: canForward));
        }
      }
    } catch (_) {}
  }

  @override
  Widget buildWidget() {
    return FutureBuilder<void>(
      future: _ensureReady(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('The browser could not start: ${snapshot.error}',
                  textAlign: TextAlign.center),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _controller.loadingWidget;
        }
        return _controller.webviewWidget;
      },
    );
  }

  @override
  Future<void> loadUrl(String url) async {
    await _ensureReady();
    await _controller.loadUrl(url);
  }

  @override
  Future<void> reload() async {
    await _ensureReady();
    await _controller.reload();
  }

  @override
  Future<void> stop() async {
    await _ensureReady();
    await _controller.executeJavaScript('window.stop()');
  }

  @override
  Future<void> goBack() async {
    await _ensureReady();
    await _controller.goBack();
    unawaited(Future<void>.delayed(
        const Duration(milliseconds: 400), _refreshHistory));
  }

  @override
  Future<void> goForward() async {
    await _ensureReady();
    await _controller.goForward();
    unawaited(Future<void>.delayed(
        const Duration(milliseconds: 400), _refreshHistory));
  }

  @override
  Future<bool> canGoBack() async => _canGoBack;

  @override
  Future<bool> canGoForward() async => _canGoForward;

  @override
  Future<String?> getTitle() async {
    await _ensureReady();
    final title = await evaluateJsExpression('document.title');
    return title?.toString();
  }

  /// CEF wraps the code it evaluates as `return <code>`, so only a single
  /// expression can run that way, and a script that has statements never gets
  /// an answer: the call waits for ever. Scripts are therefore run without
  /// waiting for one, and values are asked for as expressions, with a time
  /// limit so a page that stops answering cannot stop the app.
  @override
  Future<Object?> evaluateJs(String js) async {
    await _ensureReady();
    await _controller.executeJavaScript(js);
    return null;
  }

  @override
  Future<Object?> evaluateJsExpression(String expression) async {
    await _ensureReady();
    try {
      return await _controller
          .evaluateJavascript(expression)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> setContentBlocking(ContentBlocking? blocking) async {
    _blocking = blocking;
    if (blocking == null || _lastUrl.isEmpty || _lastUrl == 'about:blank') {
      return;
    }
    // The page already open gets the script now; later pages get it as they
    // start loading.
    try {
      await _ensureReady();
      await _controller.executeJavaScript(blocking.documentStartScript);
    } catch (_) {}
  }

  @override
  Future<void> applySettings(
      {required bool desktopMode, required bool incognito}) async {
    // CEF takes its user agent once, when it starts (a desktop Chrome one),
    // and has one profile for the app: nothing to change here.
  }

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Future<int> findInPage(String query) async {
    _lastQuery = query;
    await _ensureReady();
    if (query.isEmpty) return 0;
    final result = await evaluateJsExpression(
        '(document.body ? (document.body.innerText.split(${jsonEncode(query)}).length - 1) : 0)');
    if (result is int) return result;
    if (result is double) return result.toInt();
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  @override
  Future<void> findNext({bool forward = true}) async {
    if (_lastQuery.isEmpty) return;
    await _ensureReady();
    // window.find takes a literal string; jsonEncode makes it a safe literal.
    await _controller.executeJavaScript(
        'window.find(${jsonEncode(_lastQuery)}, false, ${!forward}, true);');
  }

  @override
  Future<void> clearFind() async {
    _lastQuery = '';
    try {
      await _controller.executeJavaScript('window.getSelection().removeAllRanges()');
    } catch (_) {}
  }

  @override
  Stream<BrowserPageEvent> get pageEvents => _pageEvents.stream;
  @override
  Stream<double> get progressEvents => _progressEvents.stream;
  @override
  Stream<BrowserJsMessage> get jsMessages => _jsMessages.stream;
  @override
  Stream<String> get urlEvents => _urlEvents.stream;
  @override
  Stream<String> get titleEvents => _titleEvents.stream;
  @override
  Stream<String> get consoleEvents => _consoleEvents.stream;
  @override
  Stream<BrowserErrorEvent> get errorEvents => _errorEvents.stream;
  @override
  Stream<BrowserHistoryState> get historyEvents => _historyEvents.stream;
  @override
  Stream<int> get scrollEvents => _scrollEvents.stream;

  @override
  Future<void> clearSession() async {
    try {
      await _ensureReady();
      await _controller.executeJavaScript('''
        (function() {
          try {
            document.cookie.split(';').forEach(function(c) {
              var name = c.split('=')[0].trim();
              if (name) {
                document.cookie = name + '=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/';
              }
            });
            localStorage.clear();
            sessionStorage.clear();
          } catch (e) {}
          location.reload();
        })();
      ''');
    } catch (e) {
      debugPrint('[BROWSER] clearSession failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (_ready != null) await _controller.dispose();
    } catch (_) {}
    for (final c in <StreamController<Object?>>[
      _pageEvents,
      _progressEvents,
      _jsMessages,
      _urlEvents,
      _consoleEvents,
      _titleEvents,
      _errorEvents,
      _historyEvents,
      _scrollEvents,
    ]) {
      unawaited(c.close());
    }
  }
}
