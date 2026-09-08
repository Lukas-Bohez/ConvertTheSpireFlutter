import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_controller.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_web.dart';

void main() {
  group('BrowserWebWebViewAdapter', () {
    test('can be instantiated on web platform', () {
      // This test validates the adapter can be created
      // On non-web platforms, the adapter class still exists but uses
      // flutter_inappwebview which requires web context
      if (kIsWeb) {
        final adapter = BrowserWebWebViewAdapter(
          hooks: BrowserWebViewHooks(),
        );
        expect(adapter, isNotNull);
        expect(adapter, isA<BrowserWebviewController>());
      }
    });

    test('has all required stream getters', () {
      if (!kIsWeb) {
        // Skip on non-web platforms
        return;
      }

      final adapter = BrowserWebWebViewAdapter(
        hooks: BrowserWebViewHooks(),
      );

      expect(adapter.pageEvents, isA<Stream<BrowserPageEvent>>());
      expect(adapter.progressEvents, isA<Stream<double>>());
      expect(adapter.jsMessages, isA<Stream<BrowserJsMessage>>());
      expect(adapter.urlEvents, isA<Stream<String>>());
      expect(adapter.consoleEvents, isA<Stream<String>>());
      expect(adapter.errorEvents, isA<Stream<BrowserErrorEvent>>());
      expect(adapter.historyEvents, isA<Stream<BrowserHistoryState>>());
      expect(adapter.scrollEvents, isA<Stream<int>>());
    });

    test('buildWidget returns a Widget', () {
      if (!kIsWeb) return;

      final adapter = BrowserWebWebViewAdapter(
        hooks: BrowserWebViewHooks(),
      );

      final widget = adapter.buildWidget();
      expect(widget, isA<Widget>());
    });

    test('dispose completes without throwing', () async {
      if (!kIsWeb) return;

      final adapter = BrowserWebWebViewAdapter(
        hooks: BrowserWebViewHooks(),
      );

      await expectLater(adapter.dispose(), completes);
    });
  });
}
