import 'dart:async';

import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_controller.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_windows/webview_windows.dart';

/// Crash-recovery tests for [BrowserWindowsWebViewAdapter].
///
/// Context: the original Windows browser backend (flutter_inappwebview) shipped
/// a DLL with BMI2 instructions that hard-crashed older CPUs with
/// EXCEPTION_ILLEGAL_INSTRUCTION (0xC000001D). The replacement backend
/// (`webview_windows`, WebView2) has its own sharp edge: 0.4.0's
/// [WebviewController.initialize] is NOT safe to re-invoke on the same
/// instance — it throws "Bad state: Stream has already been listened to"
/// because `url`/`title`/etc. are single-listener streams.
///
/// The adapter therefore mints a FRESH controller for every attempt and
/// retries transient failures. `_initState`, `_initError` and `_readyFuture`
/// drive the retry UI. These tests inject a fake [WebviewController] via the
/// `controllerFactory` constructor parameter so they are fully deterministic
/// and run on any machine (no WebView2 runtime required).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrowserWindowsWebViewAdapter crash-recovery', () {
    test(
        'transient first-initialize failure is retried with a fresh '
        'controller and ends at _initState == true', () async {
      final gate = _InitGate(failPersistently: false);
      final factory = _FactoryCounter(gate);
      final adapter = BrowserWindowsWebViewAdapter(
        blockedDomains: {},
        controllerFactory: factory.make,
      );

      // Fresh adapter: no pending future, init not started.
      expect(adapter.debugHasPendingFuture, isFalse);
      expect(adapter.debugInitState, isNull);

      // A single _ensureReady() must internally retry and succeed.
      await adapter.debugEnsureReady();

      expect(adapter.debugInitState, isTrue,
          reason: 'Retry recovered to initialized state');
      expect(adapter.debugInitError, isNull,
          reason: 'No error cached after successful recovery');

      // Idempotency: a second _ensureReady() must short-circuit without
      // minting any new controller (the completed future stays cached).
      final createdBefore = factory.created;
      await adapter.debugEnsureReady();
      expect(factory.created, equals(createdBefore),
          reason: 'A second ensureReady must not re-initialize');
      expect(adapter.debugInitState, isTrue);

      // 1 initial + 1 first attempt + 1 retry attempt.
      expect(factory.created, equals(3),
          reason: 'A fresh controller must be minted for the retry '
              '(never re-initialize the same instance)');

      // Every spawned controller must have been initialize()d exactly once.
      for (final c in factory.controllers) {
        expect(c.initializeCalls, lessThanOrEqualTo(1),
            reason: 'A controller is never initialize()d twice on the same '
                'instance (would throw "Stream has already been listened to")');
      }

      await adapter.dispose();
      expect(adapter.debugInitState, isTrue);
    });
    test(
        'persistent failure sets state=false, clears future, and the next '
        'call retries cleanly without stream collisions', () async {
      final gate = _InitGate(failPersistently: true);
      final factory = _FactoryCounter(gate);
      final adapter = BrowserWindowsWebViewAdapter(
        blockedDomains: {},
        controllerFactory: factory.make,
      );

      Object? firstError;
      try {
        await adapter.debugEnsureReady();
      } catch (e) {
        firstError = e;
      }
      expect(firstError, isNotNull, reason: 'Persistent failure surfaces');
      expect(firstError.toString().contains('already been listened'), isFalse,
          reason: 'Failure is the injected one, NOT a stream collision');

      expect(adapter.debugInitState, isFalse);
      expect(adapter.debugInitError, isNotNull,
          reason: 'Error cached for the retry UI');
      expect(adapter.debugHasPendingFuture, isFalse,
          reason: 'Future cleared so a retry can start cleanly');

      // Second call = the UI "Retry" button. It must also fail cleanly —
      // never throw "Stream has already been listened to".
      Object? secondError;
      try {
        await adapter.debugEnsureReady();
      } catch (e) {
        secondError = e;
      }
      expect(secondError.toString().contains('already been listened'), isFalse,
          reason: 'Retry re-init produces no stream-listener collision');
      expect(adapter.debugInitState, isFalse);
      expect(adapter.debugHasPendingFuture, isFalse);

      await adapter.dispose();
    });
  });

  group('BrowserWindowsWebViewAdapter userscripts', () {
    test('runs matching userscripts at document start and end', () async {
      // The adapter used to ignore this hook, so userscripts never ran on
      // Windows at all (found while working on issue #10).
      final factory = _FactoryCounter(_InitGate(failPersistently: false));
      final hooks = BrowserWebViewHooks()
        ..userScriptsFor = (url, {required atDocumentStart}) {
          if (!url.contains('example.com')) return const [];
          return [atDocumentStart ? 'START' : 'END'];
        };
      final adapter = BrowserWindowsWebViewAdapter(
        blockedDomains: {},
        controllerFactory: factory.make,
        hooks: hooks,
      );
      await adapter.debugEnsureReady();
      final controller = factory.controllers.last;
      controller.executed.clear();

      await controller.simulateNavigation('https://example.com/page');
      await controller.simulateNavigation('https://other.org/');

      expect(controller.executed.where((s) => s == 'START' || s == 'END'),
          ['START', 'END'],
          reason: 'start before end, and only on the page they match');
    });

    test('a userscript lookup that throws does not break navigation', () async {
      final factory = _FactoryCounter(_InitGate(failPersistently: false));
      final hooks = BrowserWebViewHooks()
        ..userScriptsFor =
            (url, {required atDocumentStart}) => throw StateError('bad');
      final adapter = BrowserWindowsWebViewAdapter(
        blockedDomains: {},
        controllerFactory: factory.make,
        hooks: hooks,
      );
      await adapter.debugEnsureReady();

      await expectLater(
        factory.controllers.last.simulateNavigation('https://example.com/'),
        completes,
      );
    });
  });
}

/// Shared decision gate so the fake behaves like a real WebView2 runtime:
/// with [failPersistently] false, only the very first initialize() across
/// all minted controllers fails (mimicking a transient crash), and every
/// later retry succeeds.
class _InitGate {
  _InitGate({required this.failPersistently});

  final bool failPersistently;
  int calls = 0;

  /// Increments the attempt count and reports whether THIS call must fail.
  bool nextFails() {
    final failFirst = calls == 0;
    calls++;
    return failPersistently ? true : failFirst;
  }
}

/// Counts every controller the adapter mints, so the test can prove each
/// retry gets a brand-new instance (the core of the fix).
class _FactoryCounter {
  _FactoryCounter(this._gate);

  final _InitGate _gate;
  int created = 0;
  final List<_FakeWebviewController> controllers = [];

  WebviewController make() {
    created++;
    final c = _FakeWebviewController(_gate);
    controllers.add(c);
    return c;
  }
}

/// A [WebviewController] fake that never touches the WebView2 runtime.
///
/// The real class's `url`/`title`/etc. are single-listener streams, so
/// re-listening to a reused controller throws "Bad state: Stream has already
/// been listened to". This fake uses broadcast streams so the test isolates
/// the adapter's *fresh-controller-per-retry* guarantee rather than the
/// package's stream semantics.
class _FakeWebviewController extends WebviewController {
  _FakeWebviewController(this._gate);

  final _InitGate _gate;
  int initializeCalls = 0;

  final _loadingState = StreamController<LoadingState>.broadcast();
  final _url = StreamController<String>.broadcast();
  final _title = StreamController<String>.broadcast();
  final _history = StreamController<HistoryChanged>.broadcast();
  final _webMessage = StreamController<dynamic>.broadcast();
  final _onLoadError = StreamController<WebErrorStatus>.broadcast();

  @override
  Stream<LoadingState> get loadingState => _loadingState.stream;

  @override
  Stream<String> get url => _url.stream;

  @override
  Stream<String> get title => _title.stream;

  @override
  Stream<HistoryChanged> get historyChanged => _history.stream;

  @override
  Stream<dynamic> get webMessage => _webMessage.stream;

  @override
  Stream<WebErrorStatus> get onLoadError => _onLoadError.stream;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (_gate.nextFails()) {
      throw StateError('simulated WebView2 init failure');
    }
    value = const WebviewValue(isInitialized: true);
  }

  @override
  // ignore: must_call_super
  Future<void> dispose() async {
    // Intentionally not calling super.dispose(): the real implementation
    // awaits _creatingCompleter.future, which is never completed for a fake
    // that overrides initialize(). The adapter's own _nativeSubs teardown
    // cancels the stream subscriptions.
  }

  @override
  Future<void> setPopupWindowPolicy(
      WebviewPopupWindowPolicy popupPolicy) async {}

  @override
  Future<void> setUserAgent(String userAgent) async {}

  @override
  Future<ScriptID?> addScriptToExecuteOnDocumentCreated(String script) async =>
      null;

  /// Every script the adapter asked the page to run.
  final List<String> executed = [];

  @override
  Future<dynamic> executeScript(String script) async {
    executed.add(script);
    return null;
  }

  /// Plays the event order WebView2 produces for a navigation.
  Future<void> simulateNavigation(String url) async {
    _url.add(url);
    _loadingState.add(LoadingState.loading);
    await Future<void>.delayed(Duration.zero);
    _loadingState.add(LoadingState.navigationCompleted);
    await Future<void>.delayed(Duration.zero);
  }
}
