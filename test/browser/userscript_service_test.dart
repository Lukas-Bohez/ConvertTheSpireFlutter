import 'package:convert_the_spire_reborn/src/browser/userscripts/userscript.dart';
import 'package:convert_the_spire_reborn/src/browser/userscripts/userscript_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  UserScript script({
    required String id,
    List<String> matches = const ['https://*.example.com/*'],
    UserScriptRunAt runAt = UserScriptRunAt.documentEnd,
    bool enabled = true,
    String source = 'console.log(1);',
  }) =>
      UserScript(
        id: id,
        name: id,
        source: source,
        matches: matches,
        runAt: runAt,
        enabled: enabled,
      );

  group('choosing what to inject', () {
    late UserScriptService service;

    setUp(() => service = UserScriptService());

    test('only scripts matching the URL are returned', () {
      service.seedForTesting([
        script(id: 'a', matches: ['https://*.example.com/*']),
        script(id: 'b', matches: ['https://other.test/*']),
      ]);

      final chosen = service.scriptsFor('https://www.example.com/page',
          runAt: UserScriptRunAt.documentEnd);
      expect(chosen.map((s) => s.id), ['a']);
    });

    test('scripts are separated by when they run', () {
      service.seedForTesting([
        script(id: 'early', runAt: UserScriptRunAt.documentStart),
        script(id: 'late', runAt: UserScriptRunAt.documentEnd),
      ]);

      expect(
          service
              .scriptsFor('https://example.com/',
                  runAt: UserScriptRunAt.documentStart)
              .map((s) => s.id),
          ['early']);
      expect(
          service
              .scriptsFor('https://example.com/',
                  runAt: UserScriptRunAt.documentEnd)
              .map((s) => s.id),
          ['late']);
    });

    test('document-idle scripts run at document-end', () {
      // A webview has no separate idle hook, and such scripts expect a DOM.
      service.seedForTesting(
          [script(id: 'idle', runAt: UserScriptRunAt.documentIdle)]);

      expect(
          service.scriptsFor('https://example.com/',
              runAt: UserScriptRunAt.documentEnd),
          hasLength(1));
      expect(
          service.scriptsFor('https://example.com/',
              runAt: UserScriptRunAt.documentStart),
          isEmpty);
    });

    test('a disabled script is never injected', () {
      service.seedForTesting([script(id: 'off', enabled: false)]);
      expect(
          service.scriptsFor('https://example.com/',
              runAt: UserScriptRunAt.documentEnd),
          isEmpty);
    });

    test('the master switch suppresses everything', () {
      service.seedForTesting([script(id: 'a')], enabled: false);
      expect(
          service.scriptsFor('https://example.com/',
              runAt: UserScriptRunAt.documentEnd),
          isEmpty);
      expect(service.enabledCount, 1, reason: 'still installed, just muted');
    });
  });

  group('the injected wrapper', () {
    test('runs the script body inside a try/catch so a page cannot break', () {
      final js = UserScriptService.wrapForInjection(
          script(id: 'x', source: 'throw new Error("boom");'));

      expect(js, contains('throw new Error("boom");'));
      expect(js, contains('try {'));
      expect(js, contains('catch (e)'));
      expect(js.trimLeft(), startsWith('(function () {'));
    });

    test('provides the GM_* functions Tampermonkey scripts expect', () {
      final js = UserScriptService.wrapForInjection(script(id: 'x'));

      for (final api in [
        'GM_addStyle',
        'GM_setValue',
        'GM_getValue',
        'GM_deleteValue',
        'GM_listValues',
        'GM_log',
        'GM_info',
        'GM_openInTab',
        'GM_setClipboard',
        'GM_xmlhttpRequest',
        'unsafeWindow',
      ]) {
        expect(js, contains(api), reason: '$api missing from the shim');
      }
    });

    test('stored values are namespaced per script, so two cannot collide', () {
      final a = UserScriptService.wrapForInjection(script(id: 'alpha'));
      final b = UserScriptService.wrapForInjection(script(id: 'beta'));

      expect(a, contains('__gm_alpha_'));
      expect(b, contains('__gm_beta_'));
      expect(a, isNot(contains('__gm_beta_')));
    });

    test('a script name containing quotes cannot break out of the wrapper', () {
      final nasty = UserScript(
        id: "ev'il",
        name: 'Bad");alert(1);//',
        source: 'void 0;',
        matches: const ['<all_urls>'],
      );

      final js = UserScriptService.wrapForInjection(nasty);
      // The name is embedded as JSON, so every quote inside it is escaped
      // rather than closing the string and letting the rest run as code.
      // Assert that directly: the payload never appears with a bare quote
      // in front of it.
      const payload = ');alert(1);//';
      for (var i = js.indexOf(payload); i >= 0; i = js.indexOf(payload, i + 1)) {
        expect(i, greaterThan(1));
        expect(js.substring(i - 2, i), r'\"',
            reason: 'quote before the payload must be backslash-escaped');
      }
      expect(js, contains(r'\"'));
    });

    test('injectionsFor returns ready-to-run wrapped sources', () {
      final service = UserScriptService()
        ..seedForTesting([script(id: 'a', source: 'window.__ran = true;')]);

      final injections = service.injectionsFor('https://example.com/',
          runAt: UserScriptRunAt.documentEnd);

      expect(injections, hasLength(1));
      expect(injections.single, contains('window.__ran = true;'));
      expect(injections.single, contains('GM_addStyle'));
    });
  });

  group('installing', () {
    test('rejects text with no userscript header', () async {
      final service = UserScriptService()..seedForTesting([]);
      expect(await service.installFromSource('console.log(1)'), isNull);
      expect(service.scripts, isEmpty);
    });

    test('installs a valid script', () async {
      final service = UserScriptService()..seedForTesting([]);
      final installed = await service.installFromSource('''
// ==UserScript==
// @name Test
// @match https://example.com/*
// ==/UserScript==
console.log(1);
''');
      expect(installed, isNotNull);
      expect(service.scripts, hasLength(1));
      expect(service.scripts.single.name, 'Test');
    });

    test('reinstalling the same script updates it and keeps it switched off',
        () async {
      final service = UserScriptService()..seedForTesting([]);
      const header = '''
// ==UserScript==
// @name Test
// @namespace ns
// @version {V}
// @match https://example.com/*
// ==/UserScript==
''';
      await service.installFromSource(header.replaceFirst('{V}', '1.0'));
      await service.toggleScript(service.scripts.single.id);
      expect(service.scripts.single.enabled, isFalse);

      await service.installFromSource(header.replaceFirst('{V}', '2.0'));

      expect(service.scripts, hasLength(1), reason: 'must not duplicate');
      expect(service.scripts.single.version, '2.0');
      expect(service.scripts.single.enabled, isFalse,
          reason: 'an update must not silently re-enable a disabled script');
    });
  });

  group('@require and @noframes', () {
    test('required libraries are inlined before the script body', () {
      final withLib = UserScript(
        id: 'lib-user',
        name: 'Needs jQuery',
        source: 'jQuery(document).ready(function(){});',
        matches: const ['<all_urls>'],
        requires: const ['https://cdn.test/jquery.js'],
        requiredSources: const {
          'https://cdn.test/jquery.js': 'window.jQuery = function () {};'
        },
      );

      final js = UserScriptService.wrapForInjection(withLib);

      expect(js, contains('window.jQuery = function () {};'));
      expect(
          js.indexOf('window.jQuery = function () {};'),
          lessThan(js.indexOf('jQuery(document).ready')),
          reason: 'the library must be defined before the script uses it');
    });

    test('a library that failed to download is simply left out', () {
      final missing = UserScript(
        id: 'missing-lib',
        name: 'x',
        source: 'doThing();',
        matches: const ['<all_urls>'],
        requires: const ['https://cdn.test/gone.js'],
        requiredSources: const {},
      );

      final js = UserScriptService.wrapForInjection(missing);
      expect(js, contains('doThing();'));
      expect(js, isNot(contains('@require https://cdn.test/gone.js')));
    });

    test('@noframes adds a top-frame guard', () {
      final framed = UserScript(
        id: 'top-only',
        name: 'x',
        source: 'run();',
        matches: const ['<all_urls>'],
        noFrames: true,
      );
      final normal = UserScript(
        id: 'any-frame',
        name: 'x',
        source: 'run();',
        matches: const ['<all_urls>'],
      );

      expect(UserScriptService.wrapForInjection(framed),
          contains('window.top !== window.self'));
      expect(UserScriptService.wrapForInjection(normal),
          isNot(contains('window.top !== window.self')));
    });

    test('@require and @noframes survive a JSON round trip', () {
      final parsed = parseUserScript('''
// ==UserScript==
// @name Round trip
// @match <all_urls>
// @require https://cdn.test/a.js
// @noframes
// ==/UserScript==
run();
''')!;
      final restored = UserScript.fromJson(parsed.toJson())!;

      expect(restored.requires, ['https://cdn.test/a.js']);
      expect(restored.noFrames, isTrue);
    });
  });
}
