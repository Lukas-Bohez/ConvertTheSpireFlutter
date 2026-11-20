import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/browser/extensions/content_script_extension_host.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/extension_package.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/web_extension_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The extension host for Android, TV, iOS, macOS and Linux: installs a
/// Chrome/Firefox package, offers its content scripts to matching pages and
/// keeps `chrome.storage` between pages. The generated page code is run in
/// Node (when installed) against a minimal DOM, so the JavaScript itself is
/// checked, not just the Dart around it.
void main() {
  late Directory temp;
  late Directory root;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cts_ext_');
    root = Directory(p.join(temp.path, 'root'));
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  ContentScriptExtensionHost newHost() => ContentScriptExtensionHost(
        rootDirectory: () async => root,
        uiLanguage: 'nl-BE',
        os: 'android',
      );

  Future<Directory> writeExtension(Map<String, String> files) async {
    final dir = Directory(p.join(temp.path, 'src_${files.length}'));
    for (final entry in files.entries) {
      final file = File(p.join(dir.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    return dir;
  }

  final manifest = jsonEncode({
    'manifest_version': 3,
    'name': '__MSG_appName__',
    'version': '1.2.3',
    'default_locale': 'en',
    'description': '__MSG_appDesc__',
    'background': {'service_worker': 'bg.js'},
    'content_scripts': [
      {
        'matches': ['https://*.example.com/*'],
        'exclude_matches': ['https://example.com/private/*'],
        'js': ['lib.js', 'main.js'],
        'css': ['style.css'],
      },
      {
        'matches': ['<all_urls>'],
        'js': ['early.js'],
        'run_at': 'document_start',
      },
    ],
    'web_accessible_resources': [
      {
        'resources': ['img/*.png'],
        'matches': ['<all_urls>']
      }
    ],
  });

  final files = {
    'manifest.json': manifest,
    'bg.js': '// background, not run here',
    // Two files of one entry share their top-level scope, as in Chrome.
    'lib.js': 'const helper = (x) => x * 2;',
    'main.js': '''
const browser = window.browser || chrome; // redeclaring is legal in a script
document.body.setAttribute('data-ext', String(helper(21)));
document.body.setAttribute('data-name', chrome.i18n.getMessage('greet', ['Lukas']));
document.body.setAttribute('data-url', chrome.runtime.getURL('/img/dot.png').slice(0, 22));
chrome.storage.local.get({count: 0}, (items) => {
  document.body.setAttribute('data-count', String(items.count));
  chrome.storage.local.set({count: items.count + 1});
});
chrome.runtime.sendMessage({hi: 1}, () => {
  document.body.setAttribute('data-err', chrome.runtime.lastError ? 'yes' : 'no');
});
window.__runs = (window.__runs || 0) + 1;''',
    'early.js': 'window.__early = (window.__early || 0) + 1;',
    'style.css': 'body::after { content: "__MSG_appName__"; }',
    'img/dot.png': 'not really a png',
    '_locales/en/messages.json': jsonEncode({
      'appName': {'message': 'Page Painter'},
      'appDesc': {'message': 'Paints pages'},
      'greet': {
        'message': 'Hello \$who\$!',
        'placeholders': {
          'who': {'content': '\$1'}
        }
      },
    }),
    '_locales/nl/messages.json': jsonEncode({
      'greet': {
        'message': 'Hallo \$WHO\$!',
        'placeholders': {
          'who': {'content': '\$1'}
        }
      },
    }),
  };

  test('installs a package and offers its scripts to matching pages only',
      () async {
    final host = newHost();
    final src = await writeExtension(files);
    final installed = await host.install(FileExtensionSource(src.path));

    expect(installed.name, 'Page Painter');
    expect(installed.description, 'Paints pages');
    expect(installed.version, '1.2.3');
    expect(installed.id, matches(RegExp(r'^[a-p]{32}$')));
    // Popups and options need an engine; nothing points at them.
    expect(installed.popupPath, isNull);
    expect(host.pageUrl(installed, 'popup.html'), isNull);

    final onSite =
        host.injectionsFor('https://www.example.com/a', atDocumentStart: false);
    expect(onSite, hasLength(2), reason: 'both entries once loaded');
    expect(host.injectionsFor('https://www.example.com/a', atDocumentStart: true),
        hasLength(1),
        reason: 'only the document_start entry at start');
    expect(host.injectionsFor('https://other.org/', atDocumentStart: false),
        hasLength(1),
        reason: 'only the <all_urls> entry');
    expect(
        host.injectionsFor('https://example.com/private/x',
            atDocumentStart: false),
        hasLength(1),
        reason: 'exclude_matches wins');
    expect(host.injectionsFor('about:blank', atDocumentStart: false), isEmpty);

    await host.setEnabled(installed.id, false);
    expect(host.injectionsFor('https://www.example.com/a', atDocumentStart: false),
        isEmpty);
    await host.setEnabled(installed.id, true);
    expect(host.injectionsFor('https://www.example.com/a', atDocumentStart: false),
        hasLength(2));
  });

  test('storage written by a page reaches the next page and survives a restart',
      () async {
    final host = newHost();
    final installed =
        await host.install(FileExtensionSource((await writeExtension(files)).path));
    host.handleStorageMessage(jsonEncode({
      'id': installed.id,
      'area': 'local',
      'set': {'count': 7, 'theme': 'dark'},
    }));
    host.handleStorageMessage(jsonEncode({
      'id': installed.id,
      'area': 'local',
      'remove': ['theme'],
    }));
    host.handleStorageMessage(jsonEncode({
      'id': 'not-installed',
      'area': 'local',
      'set': {'x': 1},
    }));
    expect(host.storageOf(installed.id)['local'], {'count': 7});
    expect(host.storageOf('not-installed'), isEmpty);
    await host.flushStorage();

    final restarted = newHost();
    await restarted.warmUp();
    expect(restarted.storageOf(installed.id)['local'], {'count': 7});
    final script = restarted
        .injectionsFor('https://www.example.com/', atDocumentStart: false)
        .first;
    expect(script, contains('"count":7'));

    await restarted.remove(installed.id);
    expect(await restarted.list(), isEmpty);
    expect(restarted.injectionsFor('https://www.example.com/',
        atDocumentStart: false), isEmpty);
  });

  test('refuses an extension with nothing to run on pages', () async {
    final host = newHost();
    final src = await writeExtension({
      'manifest.json': jsonEncode({
        'manifest_version': 3,
        'name': 'Popup only',
        'version': '1',
        'action': {'default_popup': 'popup.html'},
      }),
    });
    await expectLater(
      host.install(FileExtensionSource(src.path)),
      throwsA(isA<ExtensionPackageException>().having(
          (e) => e.message, 'message', contains('background page'))),
    );
    expect(await host.list(), isEmpty);
  });

  test('refuses a package whose content script file is missing', () async {
    final host = newHost();
    final broken = Map.of(files)..remove('main.js');
    final src = await writeExtension(broken);
    await expectLater(
      host.install(FileExtensionSource(src.path)),
      throwsA(isA<ExtensionPackageException>()
          .having((e) => e.message, 'message', contains('main.js'))),
    );
    expect(await host.list(), isEmpty);
  });

  test('ids are stable and look like Chrome ids', () {
    expect(ContentScriptExtensionHost.extensionIdFor('uBlock0@raymondhill.net'),
        ContentScriptExtensionHost.extensionIdFor('ublock0@raymondhill.net'));
    expect(ContentScriptExtensionHost.extensionIdFor('a'),
        isNot(ContentScriptExtensionHost.extensionIdFor('b')));
  });

  test('the page code runs: shared scope, i18n, getURL, storage, messaging',
      () async {
    final node = await _node();
    if (node == null) {
      markTestSkipped('node is not installed');
      return;
    }
    final host = newHost();
    final installed =
        await host.install(FileExtensionSource((await writeExtension(files)).path));
    host.handleStorageMessage(jsonEncode(
        {'id': installed.id, 'area': 'local', 'set': {'count': 4}}));
    final scripts =
        host.injectionsFor('https://www.example.com/a', atDocumentStart: false);

    final harness = File(p.join(temp.path, 'run.js'));
    await harness.writeAsString('''
const attrs = {}, styles = [], posted = [];
const el = (tag) => ({ tag, id: '', textContent: '', setAttribute() {} });
global.window = global;
window.top = window; window.self = window;
global.document = {
  documentElement: { appendChild: (e) => styles.push(e) },
  head: { appendChild: (e) => styles.push(e) },
  body: { setAttribute: (k, v) => { attrs[k] = v; } },
  createElement: el,
  getElementById: (id) => styles.find((s) => s.id === id) || null,
  addEventListener() {},
};
window.flutter_inappwebview = { callHandler: (name, payload) => posted.push([name, payload]) };
const scripts = ${jsonEncode(scripts)};
for (const s of scripts) { (0, eval)(s); }
for (const s of scripts) { (0, eval)(s); } // offered twice: runs once
setTimeout(() => {
  console.log(JSON.stringify({ attrs, styles: styles.map((s) => s.textContent),
    posted, runs: window.__runs, early: window.__early }));
}, 20);
''');
    final result = await Process.run(node, [harness.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final out = jsonDecode((result.stdout as String).trim().split('\n').last)
        as Map<String, dynamic>;
    final attrs = out['attrs'] as Map<String, dynamic>;

    expect(attrs['data-ext'], '42', reason: 'lib.js and main.js share scope');
    expect(attrs['data-name'], 'Hallo Lukas!', reason: 'nl beats en');
    expect(attrs['data-url'], 'data:image/png;base64,');
    expect(attrs['data-count'], '4', reason: 'storage from the app');
    expect(attrs['data-err'], 'yes', reason: 'no background, like Chrome');
    expect(out['runs'], 1);
    expect(out['early'], 1);
    expect(out['styles'], ['body::after { content: "Page Painter"; }']);
    final posted = out['posted'] as List;
    expect(posted, hasLength(1));
    expect(posted.single[0], 'ctsExtStorage');
    final message = jsonDecode(posted.single[1] as String) as Map;
    expect(message['id'], installed.id);
    expect(message['set'], {'count': 5});

    // The app stores what the page posted.
    host.handleStorageMessage(posted.single[1] as String);
    expect(host.storageOf(installed.id)['local'], {'count': 5});
  });
}

Future<String?> _node() async {
  for (final name in ['node', 'nodejs']) {
    try {
      final r = await Process.run(name, ['--version']);
      if (r.exitCode == 0) return name;
    } catch (_) {}
  }
  return null;
}

