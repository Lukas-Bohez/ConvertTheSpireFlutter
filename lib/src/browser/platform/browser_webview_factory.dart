import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show FindInteractionController;

import 'browser_webview_controller.dart';
import 'browser_webview_inappwebview.dart';
import 'browser_webview_windows.dart';

export 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show FindInteractionController;

/// Chooses the WebView implementation for the current platform at runtime.
///
/// Both adapters are statically compiled on every platform (Dart imports
/// are harmless), but only the selected one is ever *used*, so on Windows
/// no `flutter_inappwebview` native code is ever invoked - avoiding the
/// BMI2 illegal-instruction crash on old CPUs.
class BrowserWebviewFactory {
  BrowserWebviewFactory._();

  /// Returns null on platforms without a supported WebView (Linux, web).
  static BrowserWebviewController? create({
    FindInteractionController? findInteractionController,
    Set<String> blockedDomains = const {},
    BrowserWebViewHooks? hooks,
  }) {
    if (kIsWeb) return null;
    try {
      if (Platform.isWindows) {
        return BrowserWindowsWebViewAdapter(
            blockedDomains: blockedDomains, hooks: hooks);
      }
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        return BrowserInAppWebViewAdapter(
            findInteractionController: findInteractionController,
            hooks: hooks);
      }
    } catch (e) {
      debugPrint('[BROWSER] failed to create webview adapter: $e');
    }
    return null;
  }
}

// Re-exported for consumers of this file; see BrowserWebviewFactory.
