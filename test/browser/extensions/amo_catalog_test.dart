import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/browser/extensions/amo_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Guards the addons.mozilla.org catalog client (issue #10).
///
/// The fixtures under test/fixtures/amo are real v5 responses recorded on
/// 2026-09-23, trimmed to the fields the app reads. The v5 API is not
/// frozen, so these pin the shapes the client was written against.
void main() {
  final search =
      File('test/fixtures/amo/search_dark_reader.json').readAsStringSync();
  final lofi =
      File('test/fixtures/amo/addon_lofi_player.json').readAsStringSync();

  http.Response ok(String body) => http.Response.bytes(utf8.encode(body), 200,
      headers: {'content-type': 'application/json'});

  group('localised fields', () {
    test('a plain string is used as-is', () {
      expect(AmoAddon.localised('Dark Reader', 'en-US'), 'Dark Reader');
    });

    test('the requested language wins', () {
      expect(
          AmoAddon.localised({'en-US': 'Hello', 'nl': 'Hallo'}, 'nl'), 'Hallo');
    });

    test('a null in the requested language falls back to the add-on default',
        () {
      // Exactly what AMO sent for Lofi Player.
      final name = {'nl': 'Lofi Player', 'en-US': null, '_default': 'nl'};

      expect(AmoAddon.localised(name, 'en-US'), 'Lofi Player');
    });

    test('a regional request matches the base language', () {
      expect(AmoAddon.localised({'de': 'Hallo'}, 'de-AT'), 'Hallo');
    });

    test('anything at all beats nothing', () {
      expect(AmoAddon.localised({'fr': 'Bonjour'}, 'en-US'), 'Bonjour');
      expect(AmoAddon.localised({'_default': 'fr'}, 'en-US'), isNull);
      expect(AmoAddon.localised(null, 'en-US'), isNull);
    });
  });

  group('parsing recorded responses', () {
    test('search results carry what the app needs to install', () async {
      final catalog = AmoCatalog(client: MockClient((_) async => ok(search)));

      final page = await catalog.search('dark reader');
      final first = page.results.first;

      expect(page.total, greaterThan(100));
      expect(page.hasMore, isTrue);
      expect(first.guid, 'addon@darkreader.org');
      expect(first.name, 'Dark Reader');
      expect(first.fileUrl, startsWith('https://addons.mozilla.org/'));
      expect(first.fileUrl, endsWith('.xpi'));
      expect(first.fileSha256, hasLength(64));
      expect(first.androidCompatible, isTrue);
      expect(first.recommended, isTrue);
      expect(first.dailyUsers, greaterThan(0));
    });

    test('an add-on without Android support is marked so', () async {
      final catalog = AmoCatalog(client: MockClient((_) async => ok(lofi)));

      final addon = await catalog.details('lofi-player@quizthespire.com');

      expect(addon.name, 'Lofi Player');
      expect(addon.androidCompatible, isFalse);
      expect(addon.permissions, ['storage']);
      expect(addon.version, '1.0.1');
    });

    test('an entry with no installable file is dropped, not fatal', () async {
      final body = jsonEncode({
        'count': 2,
        'next': null,
        'results': [
          {'guid': 'broken@x', 'current_version': null},
          jsonDecode(lofi),
        ],
      });
      final catalog = AmoCatalog(client: MockClient((_) async => ok(body)));

      final page = await catalog.search('x');

      expect(page.results.map((a) => a.guid), ['lofi-player@quizthespire.com']);
      expect(page.hasMore, isFalse);
    });
  });

  group('requests', () {
    test('Android searches ask AMO for Android add-ons', () async {
      late Uri seen;
      final catalog = AmoCatalog(client: MockClient((request) async {
        seen = request.url;
        return ok(search);
      }));

      await catalog.search('ublock', forAndroid: true);

      expect(seen.host, 'addons.mozilla.org');
      expect(seen.path, '/api/v5/addons/search/');
      expect(seen.queryParameters['app'], 'android');
      expect(seen.queryParameters['type'], 'extension');
      expect(seen.queryParameters['q'], 'ublock');
    });

    test('an empty search lists the most used extensions', () async {
      late Uri seen;
      final catalog = AmoCatalog(client: MockClient((request) async {
        seen = request.url;
        return ok(search);
      }));

      await catalog.search('  ');

      expect(seen.queryParameters.containsKey('q'), isFalse);
      expect(seen.queryParameters['sort'], 'users');
    });

    test('responses are cached for a while', () async {
      var calls = 0;
      var now = DateTime(2026, 9, 23, 12);
      final catalog = AmoCatalog(
        client: MockClient((_) async {
          calls++;
          return ok(search);
        }),
        clock: () => now,
      );

      await catalog.search('dark');
      await catalog.search('dark');
      expect(calls, 1);

      now = now.add(const Duration(minutes: 11));
      await catalog.search('dark');
      expect(calls, 2, reason: 'the cache must expire');
    });
  });

  group('failures read as sentences', () {
    Future<AmoException> failureFor(http.Response response) async {
      final catalog = AmoCatalog(client: MockClient((_) async => response));
      try {
        await catalog.details('x');
      } on AmoException catch (e) {
        return e;
      }
      fail('expected an AmoException');
    }

    test('not found', () async {
      final e = await failureFor(http.Response('{"detail":"Not found."}', 404));
      expect(e.message, contains('not on addons.mozilla.org'));
    });

    test('rate limited', () async {
      final e = await failureFor(http.Response('', 429));
      expect(e.message, contains('rate limiting'));
    });

    test('server error', () async {
      final e = await failureFor(http.Response('', 503));
      expect(e.message, contains('503'));
    });

    test('garbage', () async {
      final e = await failureFor(ok('<html>'));
      expect(e.message, contains('could not read'));
    });

    test('offline', () async {
      final catalog = AmoCatalog(
          client: MockClient((_) async => throw const SocketException('down')));
      await expectLater(catalog.search('x'), throwsA(isA<AmoException>()));
    });
  });
}
