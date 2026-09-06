import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:youtube_explode_dart/src/reverse_engineering/challenges/ejs/base_ejs_solver.dart';

/// Headless-WebView-backed JS solver for youtube_explode_dart on Android/iOS.
///
/// Desktop uses DenoEJSSolver (Deno binary); mobile can't execute a
/// runtime-downloaded native binary because of Android 10+ W^X enforcement,
/// so this runs the same JS inside a headless WebView instead.
class WebViewEJSSolver extends BaseEJSSolver {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;

  /// Memoized so concurrent callers share one initialization instead of
  /// racing two `HeadlessInAppWebView.run()` calls (same pattern as
  /// `AppDatabase.database`). Each caller awaits the same future; if init
  /// fails, the future is cleared so a later call can retry.
  Future<void>? _readyFuture;

  Future<void> _ensureReady() =>
      _readyFuture ??= _initHeadless().whenComplete(() {
        if (_controller == null) _readyFuture = null;
      });

  Future<void> _initHeadless() async {
    if (_controller != null) return;
    final headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      onWebViewCreated: (controller) => _controller = controller,
    );
    await headless.run();
    _headless = headless;
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    await _ensureReady();
    final result = await _controller!.evaluateJavascript(source: jsCode);
    return result is String ? result : result.toString();
  }

  @override
  void dispose() {
    _headless?.dispose();
    super.dispose();
  }
}
