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

  Future<void> _ensureReady() async {
    if (_controller != null) return;
    _headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      onWebViewCreated: (controller) => _controller = controller,
    );
    await _headless!.run();
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
