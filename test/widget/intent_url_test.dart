import 'package:convert_the_spire_reborn/src/screens/browser/intent_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the `intent:` URL handling.
///
/// The browser used to hand every intent: URL straight to the system, so a
/// search result could silently launch the YouTube app instead of opening the
/// page (issue #7). Anything that is really a web page must stay in the
/// browser; everything else must be offered as a choice, not launched.
void main() {
  group('resolveIntentUrl', () {
    test('a YouTube intent becomes a mobile web page', () {
      final resolution = resolveIntentUrl(
        'intent://www.youtube.com/watch?v=dQw4w9WgXcQ#Intent;'
        'scheme=https;package=com.google.android.youtube;end',
      );

      expect(resolution.canOpenInBrowser, isTrue);
      expect(resolution.webUrl, 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(resolution.package, 'com.google.android.youtube');
    });

    test('a youtu.be short link becomes a watch URL', () {
      final resolution = resolveIntentUrl(
        'intent://youtu.be/dQw4w9WgXcQ#Intent;scheme=https;end',
      );

      expect(resolution.webUrl, 'https://m.youtube.com/watch?v=dQw4w9WgXcQ');
    });

    test('an explicit browser fallback wins', () {
      final resolution = resolveIntentUrl(
        'intent://example.com/app#Intent;scheme=https;package=com.example;'
        'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fweb;end',
      );

      expect(resolution.webUrl, 'https://example.com/web');
    });

    test('a plain https intent is rebuilt as a normal URL', () {
      final resolution = resolveIntentUrl(
        'intent://example.com/page?a=1#Intent;scheme=https;end',
      );

      expect(resolution.webUrl, 'https://example.com/page?a=1');
    });

    test('an app-only intent has nothing to open in the browser', () {
      final resolution = resolveIntentUrl(
        'intent://scan/#Intent;scheme=zxing;package=com.google.zxing.client;end',
      );

      expect(resolution.canOpenInBrowser, isFalse);
      expect(resolution.package, 'com.google.zxing.client');
    });

    test('non-intent URLs are left alone', () {
      final resolution = resolveIntentUrl('https://example.com');

      expect(resolution.canOpenInBrowser, isFalse);
      expect(resolution.package, isNull);
    });

    test('a malformed intent does not throw', () {
      expect(() => resolveIntentUrl('intent:'), returnsNormally);
      expect(resolveIntentUrl('intent:').canOpenInBrowser, isFalse);
    });

    test('music.youtube.com keeps its own host', () {
      final resolution = resolveIntentUrl(
        'intent://music.youtube.com/watch?v=abc#Intent;scheme=https;end',
      );

      expect(resolution.webUrl, 'https://music.youtube.com/watch?v=abc');
    });
  });
}
