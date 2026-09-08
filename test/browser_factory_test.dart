import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_controller.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrowserWebviewFactory', () {
    test('returns a controller on supported platforms', () {
      final controller = BrowserWebviewFactory.create();
      if (kIsWeb) {
        // On web, the factory should return a BrowserWebWebViewAdapter
        expect(controller, isNotNull,
            reason: 'Factory should return a controller on web platform');
        expect(controller, isA<BrowserWebviewController>());
      } else if (Platform.isWindows ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS) {
        expect(controller, isNotNull,
            reason:
                'Factory should return a non-null controller on supported platform ${Platform.operatingSystem}');
        expect(controller, isA<BrowserWebviewController>());
      } else {
        // Unsupported platforms (e.g. Linux) return null
        expect(controller, isNull,
            reason:
                'Factory should return null on unsupported platform ${Platform.operatingSystem}');
      }
    });

    test('returned controller has all required streams', () {
      final controller = BrowserWebviewFactory.create();
      if (controller == null) {
        // On unsupported platforms (Linux), null is expected
        return;
      }

      // Verify all streams are available
      expect(controller.pageEvents, isNotNull);
      expect(controller.progressEvents, isNotNull);
      expect(controller.jsMessages, isNotNull);
      expect(controller.urlEvents, isNotNull);
      expect(controller.consoleEvents, isNotNull);
      expect(controller.errorEvents, isNotNull);
      expect(controller.historyEvents, isNotNull);
      expect(controller.scrollEvents, isNotNull);
    });

    test('factory accepts hooks parameter', () {
      final hooks = BrowserWebViewHooks();
      hooks.shouldAllowNavigation = (url) async => true;
      hooks.shouldBlockResource = (url) => false;

      final controller = BrowserWebviewFactory.create(hooks: hooks);
      if (controller == null) return;

      expect(controller, isA<BrowserWebviewController>());
    });

    test('factory accepts blockedDomains parameter', () {
      final blockedDomains = {'example.com', 'ads.example.com'};
      final controller =
          BrowserWebviewFactory.create(blockedDomains: blockedDomains);
      // Should not throw on any platform
      expect(controller, isA<BrowserWebviewController?>());
    });

    test('dispose does not throw', () async {
      final controller = BrowserWebviewFactory.create();
      if (controller == null) return;

      // Should not throw
      await expectLater(controller.dispose(), completes);
    });

    test('factory returns non-null on supported platforms only', () {
      // This test verifies the factory works on the current platform.
      // On Windows, it returns BrowserWindowsWebViewAdapter.
      // On web, it returns BrowserWebWebViewAdapter.
      // On Android/iOS/macOS, it returns BrowserInAppWebViewAdapter.
      // On Linux, it returns null (unsupported).
      final controller = BrowserWebviewFactory.create();
      if (kIsWeb) {
        expect(controller, isNotNull,
            reason:
                'Factory should return a non-null controller on web platform');
        expect(controller, isA<BrowserWebviewController>());
      } else if (Platform.isWindows ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS) {
        expect(controller, isNotNull,
            reason:
                'Factory should return a non-null controller on supported platforms');
        expect(controller, isA<BrowserWebviewController>());
      } else {
        // Unsupported platforms (e.g. Linux) return null
        expect(controller, isNull,
            reason:
                'Factory should return null on unsupported platforms');
      }
    });
  });
}
