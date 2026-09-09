import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/screens/browser_screen.dart';

/// Tangible, expectation-exact tests for the browser address bar.
///
/// Regression context: searching (e.g. "minecraft") previously produced a
/// blank page because the default engine targeted the JS-only
/// `duckduckgo.com/?q=` SPA, which renders nothing inside embedded
/// WebView2/iframes. These tests pin the address bar to URLs with
/// server-rendered results and cover torrent input too.
void main() {
  group('BrowserScreen.buildSearchUrl (address bar resolution)', () {
    test('plain query "minecraft" hits the DuckDuckGo HTML endpoint', () {
      // The exact repro from the bug report: type "minecraft", see results.
      expect(
        BrowserScreen.buildSearchUrl('minecraft'),
        'https://html.duckduckgo.com/html/?q=minecraft',
      );
    });

    test('multi-word queries are URL-encoded, spaces become %20', () {
      expect(
        BrowserScreen.buildSearchUrl('red alert 2 music'),
        'https://html.duckduckgo.com/html/?q=red%20alert%202%20music',
      );
    });

    test('special characters survive encoding', () {
      expect(
        BrowserScreen.buildSearchUrl('C++ & "templates"'),
        'https://html.duckduckgo.com/html/?q=C%2B%2B%20%26%20%22templates%22',
      );
    });

    test('Google/Bing/Brave engines keep their own endpoints', () {
      expect(
        BrowserScreen.buildSearchUrl('minecraft', engine: 'Google'),
        'https://www.google.com/search?q=minecraft',
      );
      expect(
        BrowserScreen.buildSearchUrl('minecraft', engine: 'Bing'),
        'https://www.bing.com/search?q=minecraft',
      );
      expect(
        BrowserScreen.buildSearchUrl('minecraft', engine: 'Brave'),
        'https://search.brave.com/search?q=minecraft',
      );
    });

    test('absolute URLs pass through untouched', () {
      expect(
        BrowserScreen.buildSearchUrl('https://example.com/video?q=1'),
        'https://example.com/video?q=1',
      );
      expect(
        BrowserScreen.buildSearchUrl('http://localhost:8080/ui'),
        'http://localhost:8080/ui',
      );
    });

    test('bare domains get an https scheme instead of a search', () {
      expect(
        BrowserScreen.buildSearchUrl('thepiratebay.org'),
        'https://thepiratebay.org',
      );
    });

    test('torrent magnet: URIs are never sent to a search engine', () {
      const magnet =
          'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=ubuntu-24.04-desktop-amd64.iso';
      expect(BrowserScreen.buildSearchUrl(magnet), magnet,
          reason: 'magnet: URIs must pass through unchanged so torrent '
              'handling can pick them up');
    });

    test('empty input resolves to nothing navigable', () {
      expect(BrowserScreen.buildSearchUrl(''), '');
      expect(BrowserScreen.buildSearchUrl('   '), '');
    });
  });
}
