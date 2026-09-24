import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_windows/webview_windows.dart';

/// The one WebView2 environment this process gets.
///
/// WebView2 allows a single environment per process, and its options -
/// including whether browser extensions may run - are fixed when it is
/// created. The browser and the extension manager both need it, and either
/// may be opened first, so creation lives here rather than in either of them
/// (issue #10).
class WebView2Environment {
  WebView2Environment._();

  static Future<void>? _ready;

  /// Where the WebView2 profile lives. A short path under LOCALAPPDATA: long
  /// profile paths used to crash the runtime.
  static String? get userDataPath {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    return local.isEmpty ? null : '$local\\ConvertTheSpireReborn\\WebView2';
  }

  /// Creates the environment once. Later calls wait for the first.
  ///
  /// Never throws: if creation with our profile path fails, WebView2 falls
  /// back to its default location when the first controller initialises,
  /// exactly as the browser always behaved.
  static Future<void> ensure() => _ready ??= _create();

  static Future<void> _create() async {
    final path = userDataPath;
    if (path == null) return;
    try {
      await WebviewController.initializeEnvironment(userDataPath: path);
    } catch (e) {
      debugPrint('[WEBVIEW2] environment init failed, using default: $e');
    }
  }

  /// Whether browser extensions can run in this environment.
  static Future<bool> extensionsEnabled() async {
    await ensure();
    try {
      return await WebviewController.areBrowserExtensionsEnabled();
    } catch (_) {
      // An older plugin build without the method: no extensions.
      return false;
    }
  }

  @visibleForTesting
  static void resetForTest() => _ready = null;
}
