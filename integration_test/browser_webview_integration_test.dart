import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_controller.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end browser tests on a real Windows machine against a local
/// fixture HTTP server: a Google-style search-results page for the query
/// "minecraft", a torrent listing page with magnet links, and an ad-block
/// probe that proves blocked fetches never leave the webview while
/// allowed ones do.
///
/// Run with: flutter test -d windows integration_test/browser_webview_integration_test.dart
void main() {
  if (!Platform.isWindows) {
    // WebView2 (and this adapter) only exist on Windows; every other
    // platform uses its own adapter with its own coverage.
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('in-app browser (real WebView2) against local fixtures', () {
    late HttpServer server;
    late int port;
    final requestedPaths = <String>[];

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((req) async {
        requestedPaths.add(req.uri.path);
        switch (req.uri.path) {
          case '/allowed.js':
            req.response.headers.contentType =
                ContentType('application', 'javascript');
            req.response.write('OK-ALLOWED');
            break;
          case '/search':
            final q = req.uri.queryParameters['q'] ?? '';
            req.response.headers.contentType = ContentType.html;
            req.response.write(_searchPage(q));
            break;
          case '/torrents':
            req.response.headers.contentType = ContentType.html;
            req.response.write(_torrentPage);
            break;
          default:
            req.response.statusCode = HttpStatus.notFound;
            req.response.write('not found');
        }
        await req.response.close();
      });
    });

    tearDownAll(() async {
      await server.close(force: true);
    });

    testWidgets('search, ad-block probe, torrents and history all work',
        (tester) async {
      // Userscripts: one at document start, one at document end, only for
      // the search page. The Windows adapter used to ignore this hook, so
      // userscripts never ran on Windows at all.
      final hooks = BrowserWebViewHooks()
        ..userScriptsFor = (url, {required atDocumentStart}) {
          if (!url.contains('/search')) return const [];
          return atDocumentStart
              ? const ['window.__userscriptStart = true;']
              : const ["document.body.dataset.userscript = 'ran';"];
        };
      final adapter = BrowserWindowsWebViewAdapter(
          blockedDomains: {'ads.blocked-test.local'}, hooks: hooks);
      final jsMessages = <BrowserJsMessage>[];
      final urls = <String>[];
      final subs = <StreamSubscription>[
        adapter.jsMessages.listen(jsMessages.add),
        adapter.urlEvents.listen(urls.add),
      ];
      addTearDown(() async {
        for (final s in subs) {
          await s.cancel();
        }
        await adapter.dispose();
      });

      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: adapter.buildWidget())));

      // 1) The WebView2 surface must actually become visible. This is the
      //    regression guard for the black-rectangle bug.
      await _waitUntil(tester, () => find.byType(Texture).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 45));
      expect(find.byType(Texture), findsOneWidget,
          reason: 'WebView2 texture must render (black-screen regression)');

      final base = 'http://127.0.0.1:$port';

      // 2) A search query renders its results page.
      await adapter.loadUrl('$base/search?q=minecraft');
      await _waitUntil(tester, () => urls.contains('$base/search?q=minecraft'),
          timeout: const Duration(seconds: 30));
      expect(await adapter.getTitle(), 'minecraft - FixtureSearch');
      final searchText =
          _plain(await adapter.evaluateJs('document.body.innerText'));
      expect(searchText, contains('Minecraft Official Result'));
      expect(searchText, contains('query: minecraft'),
          reason: 'the typed query must reach the results page');

      // 2b) Userscripts ran on the page they match.
      String userscriptEnd = '';
      for (var i = 0; i < 30 && userscriptEnd != 'ran'; i++) {
        userscriptEnd = _plain(
            await adapter.evaluateJs('document.body.dataset.userscript'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(userscriptEnd, 'ran',
          reason: 'document-end userscripts must run on Windows');
      expect(
          _plain(await adapter.evaluateJs('window.__userscriptStart === true')),
          'true',
          reason: 'document-start userscripts must run on Windows');

      // 3) Ad-block: the blocked fetch is short-circuited inside the
      //    webview (empty response), the allowed fetch passes through and
      //    hits the server. The page reports both via the JS bridge.
      await _waitUntil(
          tester, () => jsMessages.any((m) => m.handler == 'adblockProbe'),
          timeout: const Duration(seconds: 30));
      final probe =
          jsMessages.firstWhere((m) => m.handler == 'adblockProbe').payload;
      expect(probe, 'blocked:|allowed:OK-ALLOWED',
          reason: 'blocked domain fetch must be neutralised, '
              'same-origin fetch must succeed');
      expect(requestedPaths, contains('/allowed.js'));
      expect(requestedPaths, isNot(contains('/ad.js')));

      // 4) Torrent listing page: entries and magnet links survive.
      await adapter.loadUrl('$base/torrents');
      await _waitUntil(tester, () => urls.contains('$base/torrents'),
          timeout: const Duration(seconds: 30));
      expect(await adapter.getTitle(), 'FixTorrents - Minecraft Pack');
      final torrentText =
          _plain(await adapter.evaluateJs('document.body.innerText'));
      expect(torrentText, contains('Minecraft Ultimate Pack 1.21'));
      expect(torrentText, contains('Redstone Contraptions Vol 3'));
      final magnets = _plain(await adapter.evaluateJs(
          "document.querySelectorAll('a[href^=\"magnet:\"]').length"));
      expect(int.tryParse(magnets), 2,
          reason: 'both magnet links must be present in the DOM');

      // 5) History navigation.
      await adapter.goBack();
      await _waitUntil(
          tester, () => urls.isNotEmpty && urls.last.contains('/search'),
          timeout: const Duration(seconds: 30));
      expect(await adapter.canGoForward(), isTrue);
      expect(await adapter.canGoBack(), isFalse);
    });
  });
}

/// Pumps frames while waiting for a real-world condition (WebView2 and
/// HTTP are real async, not fake-zone timers).
Future<void> _waitUntil(WidgetTester tester, bool Function() condition,
    {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue,
      reason: 'condition not met within ${timeout.inSeconds}s');
}

/// WebView2 returns script results JSON-encoded; unwrap plain values.
String _plain(Object? value) {
  if (value == null) return '';
  final s = '$value';
  try {
    final decoded = jsonDecode(s);
    if (decoded is String) return decoded;
    if (decoded is num) return decoded.toString();
  } catch (_) {}
  return s;
}

String _searchPage(String q) => '''
<!doctype html>
<html>
<head><title>$q - FixtureSearch</title></head>
<body style="background:#fff;color:#000">
<h1>Minecraft Official Result</h1>
<p id="q">query: $q</p>
<div class="result">Minecraft is a sandbox game by Mojang.</div>
<div class="result">Download Minecraft from minecraft.net</div>
<script>
window.addEventListener('load', function () {
  var blocked = fetch('http://ads.blocked-test.local/ad.js')
    .then(function (r) { return r.text(); })
    .then(function (t) { return 'blocked:' + t; })
    .catch(function () { return 'blocked:err'; });
  var allowed = fetch('/allowed.js')
    .then(function (r) { return r.text(); })
    .then(function (t) { return 'allowed:' + t; })
    .catch(function () { return 'allowed:err'; });
  Promise.all([blocked, allowed]).then(function (res) {
    window.__bbCall('adblockProbe', res.join('|'));
  });
});
</script>
</body>
</html>
''';

const _torrentPage = '''
<!doctype html>
<html>
<head><title>FixTorrents - Minecraft Pack</title></head>
<body style="background:#fff;color:#000">
<h1>Torrents</h1>
<ul>
<li><a href="magnet:?xt=urn:btih:aaa111">Minecraft Ultimate Pack 1.21</a> seeds 142</li>
<li><a href="magnet:?xt=urn:btih:bbb222">Redstone Contraptions Vol 3</a> seeds 87</li>
</ul>
</body>
</html>
''';
