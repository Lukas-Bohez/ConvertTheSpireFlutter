import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/browser/extensions/amo_catalog.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/extension_package.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/web_extension_host.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/webview2_extension_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';

/// Does a real WebView2 run real extensions? (issue #10)
///
/// Loading without an error is not "working" (issue #10, hard rule 6), so every
/// check here looks for the extension's core effect on a page served from a
/// local fixture server: Dark Reader recolours it, uBlock Origin Lite stops an
/// ad script from loading. It also checks the app's own document-start script
/// (the userscript path) still runs with extensions on, and whether WebView2
/// lets a webview open an extension's own popup page.
///
/// Fixtures are the official release packages, passed in as a folder:
///
///   flutter test -d windows integration_test/webextension_webview2_test.dart
///     --dart-define=EXT_FIXTURES=C:\path\to\packages
///     --dart-define=EXT_PROFILE=C:\path\to\profile
///     --dart-define=EXT_PHASE=install      (then again with EXT_PHASE=persisted)
///
/// Expected files in EXT_FIXTURES: darkreader-mv3.zip, ubol-edge.zip and,
/// optionally, lofi.xpi and darkreader-firefox.xpi (Firefox builds, recorded
/// but not required to work).
const _fixtures = String.fromEnvironment('EXT_FIXTURES');
const _profile = String.fromEnvironment('EXT_PROFILE');
const _phase = String.fromEnvironment('EXT_PHASE', defaultValue: 'install');

void main() {
  if (!Platform.isWindows || _fixtures.isEmpty || _profile.isEmpty) {
    // Nothing to run without fixtures; CI does not download them.
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final results = <String, Object?>{'phase': _phase};

  late HttpServer server;
  late int port;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      req.response.headers.contentType = ContentType.html;
      if (req.uri.path == '/page') {
        req.response.write(_fixturePage);
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    // One line the findings doc can quote verbatim.
    // ignore: avoid_print
    print('EXT_RESULTS ${jsonEncode(results)}');
  });

  Future<String> unpack(String packageName) async {
    final bytes = await File(p.join(_fixtures, packageName)).readAsBytes();
    final archive = decodeExtensionPackage(Uint8List.fromList(bytes));
    final target = Directory(p.join(
        _profile, '..', 'unpacked', p.basenameWithoutExtension(packageName)));
    if (await target.exists()) await target.delete(recursive: true);
    await extractExtension(archive, target);
    return p.normalize(target.absolute.path);
  }

  Future<dynamic> js(WebviewController c, String script) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await c.executeScript(script);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return null;
  }

  Future<void> loadAndSettle(
      WidgetTester tester, WebviewController c, String url) async {
    await c.loadUrl(url);
    // Extensions inject after the page loads; give them time to act.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('WebView2 runs real extensions', (tester) async {
    await WebviewController.initializeEnvironment(userDataPath: _profile);
    final enabled = await WebviewController.areBrowserExtensionsEnabled();
    results['environmentAcceptedExtensions'] = enabled;
    expect(enabled, isTrue, reason: 'the environment must accept extensions');

    final controller = WebviewController();
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 1000, height: 700, child: Webview(controller)),
      ),
    ));
    await controller.addScriptToExecuteOnDocumentCreated(
        'window.__appDocumentScriptRan = true;');

    if (_phase == 'persisted') {
      final installed = await controller.getBrowserExtensions();
      results['persistedAfterRestart'] =
          installed.map((e) => '${e.name}:${e.enabled}').toList();
      final names = installed.map((e) => e.name).toSet();
      expect(names, containsAll(['Dark Reader', 'uBlock Origin Lite']),
          reason: 'extensions must survive an app restart');
      await loadAndSettle(tester, controller, 'http://127.0.0.1:$port/page');
      results['darkReaderActiveAfterRestart'] = await js(controller,
          "document.documentElement.hasAttribute('data-darkreader-mode')");
      results['adBlockedAfterRestart'] =
          await js(controller, 'window.__adState');
      await controller.dispose();
      return;
    }

    // Install the Chromium builds - these are expected to work.
    final darkReader = await controller
        .addBrowserExtension(await unpack('darkreader-mv3.zip'));
    final ubol =
        await controller.addBrowserExtension(await unpack('ubol-edge.zip'));
    results['darkReader'] = darkReader.toString();
    results['ubol'] = ubol.toString();

    // Firefox builds: recorded, not required. This is research data.
    for (final firefoxBuild in ['lofi.xpi', 'darkreader-firefox.xpi']) {
      if (!File(p.join(_fixtures, firefoxBuild)).existsSync()) continue;
      try {
        final added =
            await controller.addBrowserExtension(await unpack(firefoxBuild));
        results[firefoxBuild] = 'accepted: $added';
        await controller.removeBrowserExtension(added.id);
      } catch (e) {
        results[firefoxBuild] = 'rejected: $e';
      }
    }

    // What does uBOL itself think is enabled? Read from its own page, where
    // the chrome.* APIs are in scope.
    await loadAndSettle(
        tester, controller, 'chrome-extension://${ubol.id}/popup.html');
    await js(controller, '''
      window.__dnr = 'pending';
      (async () => {
        try {
          const dnr = chrome.declarativeNetRequest;
          if (!dnr) { window.__dnr = 'no declarativeNetRequest API'; return; }
          const enabled = await dnr.getEnabledRulesets();
          const dynamic = (await dnr.getDynamicRules()).length;
          const sessionRules = await dnr.getSessionRules();
          const session = sessionRules.length;
          const allowTypes = {};
          for (const r of sessionRules) {
            allowTypes[r.action.type] = (allowTypes[r.action.type] || 0) + 1;
          }
          const local = sessionRules.filter(r => JSON.stringify(r.condition)
              .match(/127[.]0[.]0[.]1|localhost|loopback/)).slice(0, 3);
          window.__dnr = JSON.stringify({enabled, dynamic, session, allowTypes, local});
        } catch (e) { window.__dnr = 'error: ' + e; }
      })();''');
    await tester.pump(const Duration(seconds: 1));
    results['ubolRulesets'] = await js(controller, 'window.__dnr');

    // Rulesets can take a while to register after install: retry the page.
    Object? adState;
    for (var attempt = 0; attempt < 6; attempt++) {
      await loadAndSettle(tester, controller, 'http://127.0.0.1:$port/page');
      adState = await js(controller, 'window.__adState');
      if (adState == 'blocked') break;
    }

    // Core effects, not just "it installed".
    final darkMode = await js(controller,
        "document.documentElement.hasAttribute('data-darkreader-mode')");
    final background =
        await js(controller, 'getComputedStyle(document.body).backgroundColor');
    final appScript = await js(controller, 'window.__appDocumentScriptRan');
    final control = await js(controller, 'window.__controlState');
    // The surrogate uBOL substitutes defines adsbygoogle as a plain object
    // with a no-op push; the real library never gets that far offline of ads.
    final adScript = await js(controller, 'window.__adScript');
    results.addAll({
      'darkReaderMarkedPage': darkMode,
      'bodyBackground': background,
      'trackingPixel': adState,
      'controlImage': control,
      'adsbygoogleScript': adScript,
      'appDocumentScriptRan': appScript,
    });
    expect(darkMode, isTrue, reason: 'Dark Reader should recolour the page');
    expect(control, 'loaded',
        reason: 'the control image must load, or the probe proves nothing');
    expect(adState, 'blocked', reason: 'uBOL should block the tracking pixel');
    expect(appScript, isTrue,
        reason: 'the app\u2019s own document-start script must still run');

    // Disabling must stop the effect without uninstalling.
    await controller.setBrowserExtensionEnabled(darkReader.id, false);
    await loadAndSettle(tester, controller, 'http://127.0.0.1:$port/page');
    final darkAfterDisable = await js(controller,
        "document.documentElement.hasAttribute('data-darkreader-mode')");
    results['darkReaderAfterDisable'] = darkAfterDisable;
    expect(darkAfterDisable, isFalse);
    await controller.setBrowserExtensionEnabled(darkReader.id, true);

    // Can a webview open the extension's own popup page? WebView2 has no
    // browser chrome, so this decides whether the app can show popups at all.
    await loadAndSettle(tester, controller,
        'chrome-extension://${darkReader.id}/ui/popup/index.html');
    final popupHref = await js(controller, 'location.href');
    final popupHasContent = await js(controller,
        'document.body != null && document.body.children.length > 0');
    results['popupHref'] = popupHref;
    results['popupRendered'] = popupHasContent;

    final installed = await controller.getBrowserExtensions();
    results['installed'] = installed.map((e) => e.toString()).toList();
    await controller.dispose();
  });

  testWidgets('the app\u2019s extension host, end to end', (tester) async {
    if (_phase != 'install') return;
    final root = Directory(p.join(_profile, '..', 'hostroot'));
    if (await root.exists()) await root.delete(recursive: true);
    final host = WebView2ExtensionHost(rootDirectory: () async => root);

    // From a file, through the same path the Extensions screen uses.
    final installed = await host
        .install(FileExtensionSource(p.join(_fixtures, 'darkreader-mv3.zip')));
    results['hostInstalled'] =
        '${installed.name} ${installed.version} popup=${installed.popupPath} '
        'icon=${installed.iconPath != null}';
    expect(installed.name, 'Dark Reader');
    expect(installed.popupPath, 'ui/popup/index.html');
    expect(installed.iconPath, isNotNull);

    // Only what the app installed is listed - never WebView2's built-ins.
    final listed = await host.list();
    expect(listed.map((e) => e.id), [installed.id]);
    final reconciled = await host.reconcile();
    expect(reconciled.map((e) => e.id), [installed.id],
        reason: 'reconcile must not surface the PDF viewer or clipboard');

    // Reinstalling lands in the same folder, so the id - and with it the
    // extension's own settings - does not change.
    final again = await host
        .install(FileExtensionSource(p.join(_fixtures, 'darkreader-mv3.zip')));
    results['idStableAcrossReinstall'] = again.id == installed.id;
    expect(again.id, installed.id);
    expect((await host.list()).length, 1);

    await host.setEnabled(installed.id, false);
    expect((await host.list()).single.enabled, isFalse);
    expect((await host.reconcile()).single.enabled, isFalse);
    await host.setEnabled(installed.id, true);

    // From addons.mozilla.org, checksum-verified.
    final addon = await AmoCatalog().details('darkreader');
    results['amoVersion'] = addon.version;
    final fromAmo = await host.install(AmoExtensionSource(
      guid: addon.guid,
      slug: addon.slug,
      fileUrl: addon.fileUrl,
      version: addon.version,
      sha256: addon.fileSha256,
    ));
    results['amoInstalled'] = '${fromAmo.name} ${fromAmo.version} '
        'origin=${fromAmo.origin.name}';
    expect(fromAmo.origin, ExtensionOrigin.amo);
    expect(fromAmo.id, isNot(installed.id),
        reason: 'the AMO copy lives in its own folder');

    // A tampered download is refused.
    Object? tamperError;
    try {
      await host.install(AmoExtensionSource(
        guid: addon.guid,
        slug: addon.slug,
        fileUrl: addon.fileUrl,
        version: addon.version,
        sha256: '0' * 64,
      ));
    } catch (e) {
      tamperError = e;
    }
    results['tamperedDownload'] = '$tamperError';
    expect(tamperError, isA<ExtensionPackageException>());

    for (final extension in await host.list()) {
      await host.remove(extension.id);
    }
    expect(await host.list(), isEmpty);
    expect(
        root
            .listSync()
            .whereType<Directory>()
            .where((d) => !p.basename(d.path).startsWith('.')),
        isEmpty,
        reason: 'removing must delete the extracted folders');
    host.close();
  });
}

/// A plain white page with two network probes.
///
/// A tracking pixel every blocker blocks outright, and a control image that
/// nothing blocks - so an error on the pixel means "blocked", not "offline".
/// Ad *scripts* make poor probes: uBlock Origin redirects adsbygoogle.js to a
/// harmless surrogate so pages do not break, and a surrogate fires onload.
const _fixturePage = '''<!doctype html>
<html><head><meta charset="utf-8"><title>extension fixture</title>
<style>body{background:#ffffff;color:#111111;font:16px sans-serif}</style>
<script>window.__adState = 'pending'; window.__controlState = 'pending';</script>
<script src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js"
  onload="window.__adScript='loaded'" onerror="window.__adScript='blocked'"></script>
</head><body><h1>Fixture</h1><p>A white page for extensions to act on.</p>
<img alt="" width="1" height="1"
  src="https://www.facebook.com/tr?id=0&amp;ev=PageView&amp;noscript=1"
  onload="window.__adState='loaded'" onerror="window.__adState='blocked'">
<img alt="" width="1" height="1" src="https://www.google.com/favicon.ico"
  onload="window.__controlState='loaded'" onerror="window.__controlState='failed'">
</body></html>''';
