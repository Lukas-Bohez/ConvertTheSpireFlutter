import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/browser/extensions/content_script_extension_host.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/web_extension_host.dart';
import 'package:convert_the_spire_reborn/src/browser/js/js_bridge.dart';
import 'package:convert_the_spire_reborn/src/browser/js/scroll_bridge.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_cef.dart';
import 'package:convert_the_spire_reborn/src/browser/platform/browser_webview_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The Linux browser (Chromium through CEF) against a local page: it loads,
/// runs JavaScript, hears from the page, scrolls with the remote's script and
/// with the mouse wheel.
///
/// Run in a Linux desktop session (also WSL with WSLg):
///   flutter test -d linux integration_test/browser_linux_test.dart
void main() {
  if (!Platform.isLinux) return;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.headers.contentType = ContentType.html;
      if (req.uri.path == '/ext') {
        req.response.write('<!doctype html><title>Ext</title><body>ext</body>');
      } else if (req.uri.path == '/panel') {
        // The content scrolls inside a box under a fixed header, the layout
        // the TV cursor could not scroll up.
        req.response.write(_panelPage);
      } else {
        req.response.write(_tallPage);
      }
      await req.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  testWidgets('loads a page, runs JS, hears the page, scrolls both ways',
      (tester) async {
    // Extension scripts are switched on later in the run.
    List<String> Function(String, {required bool atDocumentStart})? pageScripts;
    final adapter = BrowserCefWebViewAdapter(
      hooks: BrowserWebViewHooks()
        ..userScriptsFor = (url, {required atDocumentStart}) =>
            pageScripts?.call(url, atDocumentStart: atDocumentStart) ??
            const [],
    );
    final messages = <BrowserJsMessage>[];
    final loaded = <String>[];
    final subs = [
      adapter.jsMessages.listen(messages.add),
      adapter.pageEvents.listen((e) {
        if (!e.isStart) loaded.add(e.url);
      }),
    ];

    // ignore: avoid_print
    print('STEP pump');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: adapter.buildWidget())),
    ));

    Future<void> waitFor(bool Function() done, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 25));
      while (!done()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    // Every step says where it is and cannot hang the run: a native call
    // that never answers fails the test after 20 s instead.
    Future<T?> real<T>(String what, Future<T> Function() call) async {
      // ignore: avoid_print
      print('STEP $what');
      return tester.runAsync<T>(() => call().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TestFailure('"$what" never answered')));
    }

    Future<Object?> js(String code) => real<Object?>(
        'js $code', () => adapter.evaluateJsExpression(code));

    final base = 'http://127.0.0.1:${server.port}';
    await real('load tall', () => adapter.loadUrl('$base/tall'));
    await waitFor(() => loaded.any((u) => u.contains('/tall')), 'the page');

    expect(await js('document.title'), 'Tall page');

    // The page reaches Dart through the shared __bbCall bridge.
    await real<Object?>('bridge call',
        () => adapter.evaluateJs(withJsBridge("__bbCall('probe', 'hello');")));
    await waitFor(() => messages.isNotEmpty, 'the bridge message');
    expect(messages.first.handler, 'probe');
    expect(messages.first.payload, 'hello');

    // The remote's scroll script: down, then up, then not past the top.
    final scroller = WebViewScroller((s) async {
      await adapter.evaluateJs(withJsBridge(s));
    });
    Future<double> scrollY() async =>
        double.parse('${await js('window.scrollY')}');
    await real('scroll 600', () => scroller.scroll(600, const Offset(300, 300)));
    final down = await scrollY();
    expect(down, closeTo(600, 2));
    await real('scroll -250', () => scroller.scroll(-250, const Offset(300, 40)));
    expect(await scrollY(), closeTo(350, 2));
    await real('scroll -9000', () => scroller.scroll(-9000, const Offset(300, 40)));
    expect(await scrollY(), 0);

    // The mouse wheel, through Flutter's pointer events and the plugin.
    final center = tester.getCenter(find.byType(Scaffold));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(await scrollY(), greaterThan(50), reason: 'the wheel scrolled');

    // The cursor's scroll under a fixed header, inside a scrolling box.
    await real('load panel', () => adapter.loadUrl('$base/panel'));
    await waitFor(() => loaded.any((u) => u.contains('/panel')), 'the panel');
    await real('panel 500', () => scroller.scroll(500, const Offset(300, 300)));
    Future<double> panelTop() async =>
        double.parse('${await js("document.getElementById('box').scrollTop")}');
    expect(await panelTop(), closeTo(500, 2));
    // Up, with the cursor over the fixed header: the case that failed.
    await real('panel -200', () => scroller.scroll(-200, const Offset(300, 30)));
    expect(await panelTop(), closeTo(300, 2));

    // An extension's content script on real Chromium: it runs, sees its
    // chrome.* APIs and its stored value, and its storage write reaches Dart.
    final extRoot = await Directory.systemTemp.createTemp('cts_ext_it_');
    final src = Directory('${extRoot.path}/src')..createSync();
    File('${src.path}/manifest.json').writeAsStringSync(jsonEncode({
      'manifest_version': 3,
      'name': 'Probe',
      'version': '1',
      'content_scripts': [
        {
          'matches': ['http://127.0.0.1/*'],
          'js': ['main.js'],
          'run_at': 'document_idle'
        }
      ],
    }));
    File('${src.path}/main.js').writeAsStringSync('''
chrome.storage.local.get({n: 0}, (items) => {
  document.body.setAttribute('data-n', String(items.n));
  chrome.storage.local.set({n: items.n + 1});
});''');
    final host = ContentScriptExtensionHost(
        rootDirectory: () async => Directory('${extRoot.path}/root'),
        uiLanguage: 'en',
        os: 'linux');
    final ext = (await real('install extension',
        () => host.install(FileExtensionSource(src.path))))!;
    host.handleStorageMessage(jsonEncode({
      'id': ext.id,
      'area': 'local',
      'set': {'n': 41}
    }));
    pageScripts = host.injectionsFor;
    messages.clear();
    await real('load ext', () => adapter.loadUrl('$base/ext'));
    await waitFor(() => loaded.any((u) => u.contains('/ext')), 'the ext page');
    Object? marker;
    final until = DateTime.now().add(const Duration(seconds: 15));
    while (marker != '41' && DateTime.now().isBefore(until)) {
      marker = await js("document.body.getAttribute('data-n')");
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(marker, '41', reason: 'the content script ran with stored data');
    await waitFor(
        () => messages.any((m) => m.handler == 'ctsExtStorage'),
        'the storage write');
    host.handleStorageMessage(
        messages.firstWhere((m) => m.handler == 'ctsExtStorage').payload);
    expect(host.storageOf(ext.id)['local'], {'n': 42});

    for (final s in subs) {
      await s.cancel();
    }
    await real('dispose', adapter.dispose);
  });
}

const _tallPage = '''<!doctype html><html><head><title>Tall page</title>
<style>body{margin:0}div{height:6000px;background:linear-gradient(#fff,#888)}</style>
</head><body><div>tall</div></body></html>''';

const _panelPage = '''<!doctype html><html><head><title>Panel page</title>
<style>
html,body{margin:0;height:100%;overflow:hidden}
header{position:fixed;top:0;left:0;right:0;height:80px;background:#246;color:#fff}
#box{position:absolute;top:0;bottom:0;left:0;right:0;overflow:auto;scroll-behavior:smooth}
#box div{height:6000px;background:linear-gradient(#fff,#888)}
</style></head><body><header>fixed header</header>
<div id="box"><div>content</div></div></body></html>''';
