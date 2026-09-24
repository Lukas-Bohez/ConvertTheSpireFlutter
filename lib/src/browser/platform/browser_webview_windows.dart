import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import 'browser_webview_controller.dart';
import 'webview2_environment.dart';

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
    WebviewController Function()? controllerFactory,
  })  : _blockedDomains = blockedDomains,
        _hooks = hooks ?? BrowserWebViewHooks(),
        _controllerFactory = controllerFactory ?? WebviewController.new {
    _native = _controllerFactory();
  }

  /// Factory used to mint the [_native] controllers. Injectable from tests
  /// so the crash-recovery path can be exercised with a deterministic fake
  /// that fails the first [WebviewController.initialize] call without
  /// touching a real WebView2 runtime.
  final WebviewController Function() _controllerFactory;

  final Set<String> _blockedDomains;
  // ignore: unused_field
  final BrowserWebViewHooks _hooks;

  /// Non-final: a controller that failed [initialize] must never be reused
  /// for a second attempt — `webview_windows` 0.4.0 throws "Bad state: Stream
  /// has already been listened to" when initialize() is called twice on the
  /// same instance. Instead, [_spawnAndInitializeController] discards the
  /// failed controller and creates a fresh one for every attempt.
  late WebviewController _native;

  /// Bumped every time [_native] is replaced with a fresh controller, so
  /// [buildWidget]'s outer [ValueListenableBuilder] rebuilds and rebinds
  /// to the new instance. A [ValueListenableBuilder] already on screen
  /// stays bound to whichever controller object it was constructed with,
  /// so swapping the [_native] field alone leaves a dead, never-
  /// initializing controller on screen forever.
  final ValueNotifier<int> _generation = ValueNotifier<int>(0);
  Future<void>? _readyFuture;
  bool _initializing = false;
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

  List<StreamSubscription> _nativeSubs = [];

  /// Tracks WebView2 initialization state for the widget builder.
  /// - null = still initializing
  /// - true = initialized successfully
  /// - false = initialization failed (see [_initError])
  final ValueNotifier<bool?> _initState = ValueNotifier<bool?>(null);
  final ValueNotifier<String?> _initError = ValueNotifier<String?>(null);

  /// Lazily initializes the WebView2 environment + controller. Safe to
  /// await repeatedly; every caller shares the same readiness future.
  /// A failed attempt is discarded so the next call retries from scratch
  /// instead of poisoning the browser for the whole session.
  Future<void> _ensureReady() async {
    if (_initState.value == true) return;
    if (_initializing && _native.value.isInitialized) {
      // Re-entered from _init()'s own post-init setup (the
      // _init -> applySettings -> _ensureReady chain): the controller is
      // already initialized, and awaiting the in-flight _init() future here
      // would deadlock ("Future awaited itself"). Let the caller proceed;
      // the outer _ensureReady finalizes _initState when _init() returns.
      return;
    }
    _initState.value = null;
    _initError.value = null;
    final future = _readyFuture ??= _init();
    try {
      await future;
      _initState.value = true;
    } catch (e) {
      _initState.value = false;
      _initError.value = e.toString();
      if (identical(_readyFuture, future)) _readyFuture = null;
      rethrow;
    }
  }

  Future<void> _init() async {
    _initializing = true;
    try {
      // The environment must exist before the first controller, and there is
      // only one per process. It is shared with the extension manager, which
      // may have created it already.
      await WebView2Environment.ensure();

      try {
        await _spawnAndInitializeController();
      } catch (e) {
        // WebView2 controller creation can transiently fail (runtime busy,
        // first-run profile setup). webview_windows 0.4.0's
        // WebviewController.initialize() is NOT safe to call a second time on
        // the same instance: it throws "Bad state: Stream has already been
        // listened to" (confirmed against the package's own actively-maintained
        // fork, which lists both re-entrant initialize() and broadcast event
        // streams as fixes over this exact upstream version). Retry with a
        // brand-new controller instance instead of re-calling initialize()
        // on the failed one.
        debugPrint(
            '[BROWSER] webview initialize failed, retrying with a fresh controller: $e');
        await Future<void>.delayed(const Duration(milliseconds: 750));
        await _spawnAndInitializeController();
      }
      await _native.setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      // Present a real desktop Chrome UA. Without this, Google/Bing serve
      // consent or bot-check walls to WebView2 (blank results pages).
      try {
        await _native.setUserAgent(
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36');
      } catch (_) {
        // Older package versions may not expose setUserAgent - non-fatal.
      }
      // Shared JS bridge + popup suppression + ad-block hook run before any
      // page script on every document.
      await _native.addScriptToExecuteOnDocumentCreated(_documentCreatedJs());
      await applySettings(desktopMode: _desktopMode, incognito: false);
    } finally {
      _initializing = false;
    }
  }

  /// Runs the userscripts matching [url], each in its own call so one that
  /// throws cannot stop the rest.
  ///
  /// Mirrors the Android adapter: document-start scripts go in as the new
  /// document begins loading, the rest once navigation completes. This
  /// adapter used to ignore the hook entirely, so userscripts installed on
  /// Windows never ran at all.
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
    final native = _native;
    for (final source in sources) {
      try {
        await native.executeScript(source);
      } catch (e) {
        debugPrint('[BROWSER] userscript injection failed: $e');
      }
    }
  }

  /// Discards whatever is currently in [_native] (a no-op the first time),
  /// creates a fresh [WebviewController], wires up its event subscriptions,
  /// and calls `initialize()` on it exactly once — so every attempt, first
  /// or retry, gets a controller that has never had `initialize()` called
  /// on it before. Bumps [_generation] so [buildWidget] rebuilds against
  /// the new instance.
  Future<void> _spawnAndInitializeController() async {
    for (final s in _nativeSubs) {
      await s.cancel();
    }
    _nativeSubs = [];
    try {
      await _native.dispose();
    } catch (_) {
      // First-ever call: nothing real to dispose yet — fine either way.
    }
    _native = _controllerFactory();
    _generation.value++;
    _nativeSubs = [
      _native.loadingState.listen((state) {
        switch (state) {
          case LoadingState.loading:
            _progressEvents.add(0);
            _pageEvents.add(BrowserPageEvent(isStart: true, url: _lastUrl));
            unawaited(_injectUserScripts(_lastUrl, atDocumentStart: true));
          case LoadingState.navigationCompleted:
            _progressEvents.add(1);
            _pageEvents.add(BrowserPageEvent(isStart: false, url: _lastUrl));
            unawaited(_injectUserScripts(_lastUrl, atDocumentStart: false));
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
            url: _lastUrl, description: status.toString(), isMainFrame: true));
      }),
    ];
    await _native.initialize();
  }

  void _handleWebMessage(dynamic message) {
    try {
      dynamic decoded = message;
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
    // Kick off initialization. `webview_windows`' Webview widget only reads
    // `controller.value.isInitialized` while building and never rebuilds
    // when initialization completes afterwards, so building it too early
    // freezes its blank placeholder forever (the "black webview" bug: the
    // page loads invisibly while the user sees a black rectangle).
    //
    // We also track our own init state so we can surface a retry UI if
    // WebView2 initialization fails (e.g. runtime missing, GPU issue).
    // Without this, a init failure leaves a permanent blank SizedBox.
    //
    // ValueListenableBuilder on _generation ensures that when
    // _spawnAndInitializeController swaps in a fresh controller, the
    // Listenable.merge below is rebuilt with the new _native — otherwise
    // it stays bound to the old, dead controller and never fires.
    unawaited(_ensureReady().catchError((_) {}));
    return ValueListenableBuilder<int>(
      valueListenable: _generation,
      builder: (context, _, __) => ListenableBuilder(
        listenable: Listenable.merge([_initState, _initError, _native]),
        builder: (context, child) {
          final initState = _initState.value;
          final initError = _initError.value;
          if (initState == false && initError != null) {
            return _buildInitError(initError);
          }
          if (initState != true) {
            return const SizedBox.expand();
          }
          return Webview(_native);
        },
      ),
    );
  }

  Widget _buildInitError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Browser initialization failed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _initState.value = null;
                _initError.value = null;
                _readyFuture = null;
                unawaited(_ensureReady().catchError((_) {}));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
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
    // Desktop Firefox/Chrome UA depending on mode; mobile-ish UAs make
    // Google/Bing serve bot-check walls in the WebView2 engine.
    if (desktopMode) {
      await _native.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36');
    } else {
      await _native.setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0');
    }
  }

  @override
  Future<void> clearSession() async {
    try {
      await _native.clearCookies();
    } catch (_) {}
    try {
      await _native.clearCache();
    } catch (_) {}
    try {
      // Clear any in-memory form data the page may have stashed in the DOM.
      await _native.executeScript('''
        (function() {
          try {
            var forms = document.querySelectorAll('form');
            for (var i = 0; i < forms.length; i++) {
              var inputs = forms[i].elements;
              for (var j = 0; j < inputs.length; j++) {
                var el = inputs[j];
                if (el.type === 'text' || el.type === 'email' ||
                    el.type === 'password' || el.type === 'search' ||
                    el.type === 'number' || el.type === 'url' ||
                    el.type === 'tel') {
                  el.value = '';
                }
              }
            }
            document.cookie = '';
            document.cookie = 'expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;';
            return 'ok';
          } catch (e) {
            return 'err';
          }
        })();
      ''');
    } catch (_) {}
    try {
      // Reload so the cleared session is reflected in the displayed page
      // rather than leaving the user staring at a stale DOM.
      await _native.executeScript('window.location.reload(true)');
    } catch (_) {}
  }

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Future<int> findInPage(String query) async {
    _lastQuery = query;
    await _ensureReady();
    if (query.isEmpty) return 0;
    final result = await _native
        .executeScript('document.body ? (document.body.innerText.match(/'
            '${_escapeRegExp(query)}/gi) || []).length : 0');
    return _toInt(result);
  }

  @override
  Future<void> findNext({bool forward = true}) async {
    if (_lastQuery.isEmpty) return;
    await _ensureReady();
    // window.find() takes a literal string, not a regex, so we use
    // jsonEncode to produce a properly-escaped JS string literal.
    await _native
        .executeScript('window.find(${jsonEncode(_lastQuery)}, false, false, '
            'undefined, 0, false, $forward);');
  }

  @override
  Future<void> clearFind() async {
    _lastQuery = '';
  }

  /// Safely coerces the dynamic result of [WebviewController.executeScript]
  /// into an int. WebView2 returns numbers as JSON, which the
  /// `webview_windows` plugin delivers as `int`, `double`, or a numeric
  /// `String` depending on the Dart FFI round-trip.
  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    try {
      return int.parse(value.toString());
    } catch (_) {
      return 0;
    }
  }

  /// Escapes all RegExp metacharacters in [input] so it can be used
  /// literally inside a JavaScript `/pattern/flags` regex.
  static String _escapeRegExp(String input) {
    return input.replaceAllMapped(
      RegExp(r'[\.*+?^${}()|[\]\\]'),
      (match) => '\\${match.group(0)}',
    );
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
  Stream<String> get consoleEvents => _consoleEvents.stream;

  @override
  Stream<BrowserErrorEvent> get errorEvents => _errorEvents.stream;

  @override
  Stream<BrowserHistoryState> get historyEvents => _historyEvents.stream;

  @override
  Stream<int> get scrollEvents => _scrollEvents.stream;

  // --· visibleForTesting hooks for crash-recovery test ---------------------

  /// Exposed for testing the crash-recovery path. On success this is `true`;
  /// on failure `false`; while initializing `null`.
  @visibleForTesting
  bool? get debugInitState => _initState.value;

  /// The cached error message from the last failed init (null when none).
  @visibleForTesting
  String? get debugInitError => _initError.value;

  /// Whether a readiness future is currently in-flight. After a failure the
  /// future is cleared so a follow-up call creates a fresh attempt; after a
  /// success it is intentionally kept (cached, completed) so `_ensureReady`
  /// short-circuits via `_initState == true`.
  @visibleForTesting
  bool get debugHasPendingFuture => _readyFuture != null;

  /// Public entry point for tests to trigger initialization. Mirrors
  /// [loadUrl]'s internal await of [_ensureReady] without needing a URL.
  @visibleForTesting
  Future<void> debugEnsureReady() => _ensureReady();

  @override
  Future<void> dispose() async {
    for (final s in _nativeSubs) {
      await s.cancel();
    }
    _nativeSubs = [];
    try {
      await _native.dispose();
    } catch (_) {
      // already disposed or not initialized — safe to ignore
    }
    await _pageEvents.close();
    await _progressEvents.close();
    await _jsMessages.close();
    await _urlEvents.close();
    await _consoleEvents.close();
    await _errorEvents.close();
    await _historyEvents.close();
    await _scrollEvents.close();
    _generation.dispose();
    _initState.dispose();
    _initError.dispose();
  }
}
