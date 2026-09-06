import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart';

import 'browser_webview_controller.dart';

/// Windows implementation backed by `webview_windows` (WebView2).
///
/// This exists because `flutter_inappwebview`'s Windows plugin ships a
/// binary (flutter_inappwebview_windows_plugin.dll) containing BMI2
/// instructions that hard-crash older CPUs with
/// EXCEPTION_ILLEGAL_INSTRUCTION (0xC000001D) - confirmed from real crash
/// dumps on the affected machine. On Windows this app therefore never
/// touches the flutter_inappwebview plugin at all.
///
/// Known limitations vs the Android implementation:
///  - No per-request interception: ad-block runs as an injected
///    fetch/XHR hook using the block domain list.
///  - No incremental load progress (0 at start, 1 on completion).
///  - No tab-preview screenshots (`takeScreenshot` always returns null).
///  - Incognito mode is a no-op (WebView2 shares one profile).
class BrowserWindowsWebViewAdapter implements BrowserWebviewController {
  BrowserWindowsWebViewAdapter({
    required Set<String> blockedDomains,
    BrowserWebViewHooks? hooks,
  })  : _blockedDomains = blockedDomains,
        _hooks = hooks ?? BrowserWebViewHooks();

  static bool _environmentInitialized = false;

  final Set<String> _blockedDomains;
  // ignore: unused_field
  final BrowserWebViewHooks _hooks;

  final WebviewController _native = WebviewController();
  Future<void>? _readyFuture;
  bool _desktopMode = false;
  String _lastUrl = '';
  String _lastTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _lastQuery = '';

  final _pageEvents = StreamController<BrowserPageEvent>.broadcast();
  final _progressEvents = StreamController<double>.broadcast();
  final _jsMessages = StreamController<BrowserJsMessage>.broadcast();
  final _urlEvents = StreamController<String>.broadcast();
  final _consoleEvents = StreamController<String>.broadcast();
  final _errorEvents = StreamController<BrowserErrorEvent>.broadcast();
  final _historyEvents = StreamController<BrowserHistoryState>.broadcast();
  final _scrollEvents = StreamController<int>.broadcast();
  final List<StreamSubscription> _nativeSubs = [];

  /// Lazily initializes the WebView2 environment + controller. Safe to
  /// await repeatedly; every caller shares the same readiness future.
  Future<void> _ensureReady() => _readyFuture ??= _init();

  Future<void> _init() async {
    // The environment must be initialized before the first controller and
    // can only be set once per process.
    if (!_environmentInitialized) {
      try {
        // Keep the WebView2 profile in the same short-path location the app
        // has always used (avoids long-path crashes).
        final local = Platform.environment['LOCALAPPDATA'] ?? '';
        if (local.isNotEmpty) {
          await WebviewController.initializeEnvironment(
              userDataPath: '$local\\ConvertTheSpireReborn\\WebView2');
          _environmentInitialized = true;
        }
      } catch (_) {
        // Fall back to the WebView2 default profile location.
      }
    }

    _nativeSubs.addAll([
      _native.loadingState.listen((state) {
        switch (state) {
          case LoadingState.loading:
            _progressEvents.add(0);
            _pageEvents
                .add(BrowserPageEvent(isStart: true, url: _lastUrl));
          case LoadingState.navigationCompleted:
            _progressEvents.add(1);
            _pageEvents
                .add(BrowserPageEvent(isStart: false, url: _lastUrl));
          default:
            break;
        }
      }),
      _native.url.listen((url) {
        _lastUrl = url;
        if (url.isEmpty || url == 'about:blank') return;
        _urlEvents.add(url);
      }),
      _native.title.listen((title) => _lastTitle = title),
      _native.historyChanged.listen((h) {
        _canGoBack = h.canGoBack;
        _canGoForward = h.canGoForward;
        _historyEvents.add(BrowserHistoryState(
            canGoBack: h.canGoBack, canGoForward: h.canGoForward));
      }),
      _native.webMessage.listen(_handleWebMessage),
      _native.onLoadError.listen((status) {
        _errorEvents.add(BrowserErrorEvent(
            url: _lastUrl,
            description: status.toString(),
            isMainFrame: true));
      }),
    ]);

    await _native.initialize();
    await _native.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
    // Shared JS bridge + popup suppression + ad-block hook run before any
    // page script on every document.
    await _native.addScriptToExecuteOnDocumentCreated(_documentCreatedJs());
    await applySettings(desktopMode: _desktopMode, incognito: false);
  }

  /// Parses the `{handler, payload}` envelope produced by the shared JS
  /// bridge (`window.chrome.webview.postMessage`).
  void _handleWebMessage(dynamic message) {
    try {
      dynamic decoded = message;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map &&
          decoded.containsKey('handler')) {
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
    } catch (e) {
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        _consoleEvents.add('webMessage parse failed: $e');
      }
    }
  }

  String _documentCreatedJs() {
    final domainList =
        _blockedDomains.map((d) => "'${d.replaceAll("'", '')}'").join(',');
    return '''
(function() {
  if (!window.__bbCall) {
    window.__bbCall = function(name, payload) {
      try {
        window.chrome.webview.postMessage(JSON.stringify({ handler: name, payload: payload }));
      } catch (e) {}
    };
  }
  // Ad-block: WebView2 cannot intercept requests, so hook fetch/XHR.
  var blocked = [$domainList];
  function isBlocked(url) {
    try {
      var host = new URL(url, location.href).hostname.toLowerCase();
      for (var i = 0; i < blocked.length; i++) {
        var b = blocked[i];
        if (host === b || host.endsWith('.' + b)) return true;
      }
    } catch (e) {}
    return false;
  }
  if (!window.__adblockHooked) {
    window.__adblockHooked = true;
    var _open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(m, u) {
      if (isBlocked(u)) { arguments[1] = 'data:text/plain,'; }
      return _open.apply(this, arguments);
    };
    var _fetch = window.fetch;
    if (_fetch) {
      window.fetch = function(input, init) {
        var url = (typeof input === 'string') ? input : (input && input.url) || '';
        if (isBlocked(url)) { return Promise.resolve(new Response('')); }
        return _fetch.apply(this, arguments);
      };
    }
  }
})();
''';
  }

  @override
  Widget buildWidget() {
    // Kick off initialization; the widget shows a blank surface until the
    // controller reports ready.
    unawaited(_ensureReady());
    return Webview(_native);
  }

  @override
  Future<void> loadUrl(String url) async {
    await _ensureReady();
    await _native.loadUrl(url);
  }

  @override
  Future<void> reload() async {
    await _ensureReady();
    await _native.reload();
  }

  @override
  Future<void> stop() async {
    await _ensureReady();
    await _native.stop();
  }

  @override
  Future<void> goBack() async {
    await _ensureReady();
    await _native.goBack();
  }

  @override
  Future<void> goForward() async {
    await _ensureReady();
    await _native.goForward();
  }

  @override
  Future<bool> canGoBack() async {
    await _ensureReady();
    return _canGoBack;
  }

  @override
  Future<bool> canGoForward() async {
    await _ensureReady();
    return _canGoForward;
  }

  @override
  Future<String?> getTitle() async {
    await _ensureReady();
    return _lastTitle;
  }

  @override
  Future<Object?> evaluateJs(String js) async {
    await _ensureReady();
    return _native.executeScript(js);
  }

  @override
  Future<void> applySettings(
      {required bool desktopMode, required bool incognito}) async {
    _desktopMode = desktopMode;
    await _ensureReady();
    if (desktopMode) {
      await _native.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
    } else {
      // WebView2 has no "reset to default UA" API; restore a standard
      // WebView2-shaped UA (without desktop-mode flags).
      await _native.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0');
    }
    // Incognito is not supported by WebView2's shared profile; see class
    // docs.
  }

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Future<int> findInPage(String query) async {
    _lastQuery = query;
    await _ensureReady();
    if (query.isEmpty) return 0;
    final count = await _native.executeScript(
        'document.body ? (document.body.innerText.match(/'
        '${_escapeRegExp(query)}/gi) || []).length : 0');
    await _native.executeScript('window.find(${_jsString(query)}, false)');
    return count is int ? count : int.tryParse('$count') ?? -1;
  }

  @override
  Future<void> findNext({bool forward = true}) async {
    await _ensureReady();
    if (_lastQuery.isEmpty) return;
    await _native.executeScript(
        'window.find(${_jsString(_lastQuery)}, ${forward ? 'false' : 'true'})');
  }

  @override
  Future<void> clearFind() async {
    await _ensureReady();
    await _native
        .executeScript('window.getSelection().removeAllRanges(); 0');
  }

  static String _escapeRegExp(String s) =>
      s.replaceAllMapped(RegExp(r'[.*+?^\${}()|[\]\\]'), (m) => '\\${m[0]}');

  static String _jsString(String s) => "'${s.replaceAll("'", r"\'")}'";

  // Streams (unchanged bodies).
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
  // WebView2 does not expose scroll positions to the embedder.
  @override
  Stream<int> get scrollEvents => _scrollEvents.stream;

  @override
  Future<void> dispose() async {
    for (final s in _nativeSubs) {
      await s.cancel();
    }
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
    try {
      await _native.dispose();
    } catch (_) {}
  }
}