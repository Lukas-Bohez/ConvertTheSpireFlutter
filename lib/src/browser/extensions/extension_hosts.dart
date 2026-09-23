import 'dart:io';

import 'package:flutter/foundation.dart';

import 'web_extension_host.dart';
import 'webview2_extension_host.dart';

/// The extension host for this platform, shared by the browser toolbar and
/// the Extensions screen so both see the same state and events.
class ExtensionHosts {
  ExtensionHosts._();

  static WebExtensionHost? _current;

  static WebExtensionHost get current => _current ??= _create();

  static WebExtensionHost _create() {
    if (!kIsWeb && Platform.isWindows) return WebView2ExtensionHost();
    // Android and Android TV get extensions through GeckoView, which ships
    // in a later sideload build (issue #10). The Play build never will.
    return const UnsupportedExtensionHost(
        'Browser extensions currently work in the Windows app only.');
  }

  /// Whether to show extension entry points at all. Platforms without an
  /// engine get no menu items rather than a screen that says "no".
  static bool get available => current.isSupported;

  @visibleForTesting
  static set current(WebExtensionHost host) => _current = host;
}
