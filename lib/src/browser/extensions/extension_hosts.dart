import 'dart:io';

import 'package:flutter/foundation.dart';

import 'content_script_extension_host.dart';
import 'web_extension_host.dart';
import 'webview2_extension_host.dart';

/// The extension host for this platform, shared by the browser toolbar and
/// the Extensions screen so both see the same state and events.
class ExtensionHosts {
  ExtensionHosts._();

  static WebExtensionHost? _current;

  static WebExtensionHost get current => _current ??= _create();

  static WebExtensionHost _create() {
    if (kIsWeb) {
      return const UnsupportedExtensionHost(
          'Browser extensions do not run in the web version.');
    }
    // Windows runs the whole extension in WebView2's own extension host.
    if (Platform.isWindows) return WebView2ExtensionHost();
    // Everywhere else (Android, Android TV, iOS, macOS, Linux) the web view
    // has no extension engine, so the app runs an extension's page scripts
    // and styles itself.
    return ContentScriptExtensionHost();
  }

  /// The host that injects extension page scripts, when this platform uses
  /// one; null on Windows, where the engine does it.
  static ContentScriptExtensionHost? get contentScripts {
    final host = current;
    return host is ContentScriptExtensionHost ? host : null;
  }

  /// Whether to show extension entry points at all. Platforms without an
  /// engine get no menu items rather than a screen that says "no".
  static bool get available => current.isSupported;

  @visibleForTesting
  static set current(WebExtensionHost host) => _current = host;
}
