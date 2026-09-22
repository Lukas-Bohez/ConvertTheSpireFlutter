import 'package:convert_the_spire_reborn/src/browser/userscripts/userscript.dart';
import 'package:flutter_test/flutter_test.dart';

/// These rules decide whether someone's script runs on their bank's website,
/// so they are tested directly rather than through a webview.
void main() {
  group('match patterns', () {
    test('a plain host/path pattern matches that host', () {
      expect(matchPatternMatches('https://example.com/*',
          'https://example.com/page'), isTrue);
    });

    test('the host must match exactly unless wildcarded', () {
      expect(
          matchPatternMatches(
              'https://example.com/*', 'https://other.com/page'),
          isFalse);
      // The classic suffix trap: notexample.com is a different site.
      expect(
          matchPatternMatches(
              'https://example.com/*', 'https://notexample.com/page'),
          isFalse);
    });

    test('*.domain covers the domain itself and its subdomains', () {
      expect(
          matchPatternMatches(
              'https://*.example.com/*', 'https://example.com/'),
          isTrue);
      expect(
          matchPatternMatches(
              'https://*.example.com/*', 'https://www.example.com/x'),
          isTrue);
      expect(
          matchPatternMatches(
              'https://*.example.com/*', 'https://a.b.example.com/x'),
          isTrue);
    });

    test('*.domain does not match a lookalike domain', () {
      // "evilexample.com" ends with "example.com" as a string but is not a
      // subdomain of it. Getting this wrong leaks scripts onto attacker sites.
      expect(
          matchPatternMatches(
              'https://*.example.com/*', 'https://evilexample.com/'),
          isFalse);
      expect(
          matchPatternMatches('https://*.example.com/*',
              'https://example.com.attacker.io/'),
          isFalse);
    });

    test('a * scheme means http or https only, not file or ftp', () {
      expect(matchPatternMatches('*://example.com/*', 'http://example.com/'),
          isTrue);
      expect(matchPatternMatches('*://example.com/*', 'https://example.com/'),
          isTrue);
      expect(matchPatternMatches('*://example.com/*', 'ftp://example.com/'),
          isFalse);
      expect(matchPatternMatches('*://example.com/*', 'file://example.com/'),
          isFalse);
    });

    test('an explicit scheme is enforced', () {
      expect(matchPatternMatches('https://example.com/*', 'http://example.com/'),
          isFalse);
    });

    test('the path is matched, not just the host', () {
      expect(
          matchPatternMatches('https://example.com/watch*',
              'https://example.com/watch?v=abc'),
          isTrue);
      expect(
          matchPatternMatches(
              'https://example.com/watch*', 'https://example.com/settings'),
          isFalse);
    });

    test('<all_urls> matches anything', () {
      expect(matchPatternMatches('<all_urls>', 'https://anything.test/x'),
          isTrue);
    });

    test('a host-only pattern with no path is rejected, as Chrome does', () {
      expect(matchPatternMatches('https://example.com', 'https://example.com/'),
          isFalse);
    });

    test('malformed patterns and URLs never throw', () {
      for (final pattern in ['', 'nonsense', '://', 'https:/example.com/*']) {
        expect(() => matchPatternMatches(pattern, 'https://example.com/'),
            returnsNormally,
            reason: pattern);
      }
      expect(matchPatternMatches('<all_urls>', 'not a url'), isTrue);
      expect(matchPatternMatches('https://example.com/*', 'not a url'), isFalse);
    });
  });

  group('metadata parsing', () {
    const script = '''
// ==UserScript==
// @name         Tidy YouTube
// @namespace    https://example.com
// @version      1.4.2
// @description  Hides the things nobody wants
// @author       Someone
// @match        https://*.youtube.com/*
// @include      https://youtu.be/*
// @exclude      https://*.youtube.com/embed/*
// @grant        GM_addStyle
// @run-at       document-start
// @noframes
// ==/UserScript==

console.log('hello');
''';

    test('reads every field from the header', () {
      final parsed = parseUserScript(script);

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Tidy YouTube');
      expect(parsed.namespace, 'https://example.com');
      expect(parsed.version, '1.4.2');
      expect(parsed.description, 'Hides the things nobody wants');
      expect(parsed.author, 'Someone');
      expect(parsed.matches, ['https://*.youtube.com/*']);
      expect(parsed.includes, ['https://youtu.be/*']);
      expect(parsed.excludes, ['https://*.youtube.com/embed/*']);
      expect(parsed.grants, ['GM_addStyle']);
      expect(parsed.runAt, UserScriptRunAt.documentStart);
      expect(parsed.source, contains("console.log('hello')"));
    });

    test('text that is not a userscript is rejected, not installed', () {
      expect(parseUserScript('console.log(1)'), isNull);
      expect(parseUserScript(''), isNull);
      expect(parseUserScript('// just a comment'), isNull);
    });

    test('a header with no directives still parses with sane defaults', () {
      final parsed = parseUserScript('''
// ==UserScript==
// ==/UserScript==
alert(1);
''');
      expect(parsed, isNotNull);
      expect(parsed!.name, 'Untitled script');
      expect(parsed.runAt, UserScriptRunAt.documentEnd);
      expect(parsed.matches, isEmpty);
      expect(parsed.id, isNotEmpty);
    });

    test('run-at idle is accepted and an unknown value falls back to end', () {
      UserScript at(String value) => parseUserScript('''
// ==UserScript==
// @name x
// @run-at $value
// ==/UserScript==
''')!;
      expect(at('document-idle').runAt, UserScriptRunAt.documentIdle);
      expect(at('document-start').runAt, UserScriptRunAt.documentStart);
      expect(at('nonsense').runAt, UserScriptRunAt.documentEnd);
    });

    test('repeated directives all survive', () {
      final parsed = parseUserScript('''
// ==UserScript==
// @name multi
// @match https://a.test/*
// @match https://b.test/*
// @exclude https://a.test/private*
// ==/UserScript==
''')!;
      expect(parsed.matches, ['https://a.test/*', 'https://b.test/*']);
      expect(parsed.excludes, ['https://a.test/private*']);
    });

    test('survives a round trip through JSON', () {
      final original = parseUserScript(script)!;
      final restored = UserScript.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.name, original.name);
      expect(restored.matches, original.matches);
      expect(restored.excludes, original.excludes);
      expect(restored.runAt, original.runAt);
      expect(restored.source, original.source);
    });
  });

  group('deciding whether a script runs', () {
    UserScript build({
      List<String> matches = const [],
      List<String> includes = const [],
      List<String> excludes = const [],
    }) =>
        UserScript(
          id: 'x',
          name: 'x',
          source: '',
          matches: matches,
          includes: includes,
          excludes: excludes,
        );

    test('a match pattern lets it run', () {
      final script = build(matches: ['https://*.youtube.com/*']);
      expect(script.matchesUrl('https://www.youtube.com/watch?v=1'), isTrue);
      expect(script.matchesUrl('https://vimeo.com/1'), isFalse);
    });

    test('an exclude beats a match', () {
      final script = build(
        matches: ['https://*.youtube.com/*'],
        excludes: ['https://*.youtube.com/embed/*'],
      );
      expect(script.matchesUrl('https://www.youtube.com/watch?v=1'), isTrue);
      expect(script.matchesUrl('https://www.youtube.com/embed/1'), isFalse);
    });

    test('an exclude beats an include too', () {
      final script = build(
        includes: ['*://*.example.com/*'],
        excludes: ['*://*.example.com/admin*'],
      );
      expect(script.matchesUrl('https://x.example.com/page'), isTrue);
      expect(script.matchesUrl('https://x.example.com/admin/users'), isFalse);
    });

    test('includes accept a regular expression in slashes', () {
      final script = build(includes: [r'/^https://\w+\.test/\d+$/']);
      expect(script.matchesUrl('https://abc.test/123'), isTrue);
      expect(script.matchesUrl('https://abc.test/letters'), isFalse);
    });

    test('an invalid regular expression is ignored rather than crashing', () {
      final script = build(includes: ['/([unclosed/']);
      expect(() => script.matchesUrl('https://example.com/'), returnsNormally);
      expect(script.matchesUrl('https://example.com/'), isFalse);
    });

    test('a script with no rules at all never runs', () {
      // Safer than running everywhere: an unscoped script would otherwise be
      // injected into every page including banking sites.
      expect(build().matchesUrl('https://example.com/'), isFalse);
    });
  });
}
