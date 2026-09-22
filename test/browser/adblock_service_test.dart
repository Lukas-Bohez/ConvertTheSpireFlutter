import 'package:convert_the_spire_reborn/src/browser/adblock/adblock_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The blocker sits in front of every request the browser makes, so its
/// matching rules are the difference between "ads are gone" and "the web is
/// broken". It had no coverage; these pin the behaviour down.
void main() {
  late AdBlockService service;

  setUp(() {
    service = AdBlockService();
    service.seedBlocklistForTesting(const [
      'ads.example.com',
      'tracker.net',
      'doubleclick.net',
    ]);
  });

  group('blocking', () {
    test('blocks an exact domain match', () {
      expect(service.shouldBlock('https://ads.example.com/banner.js'), isTrue);
    });

    test('blocks subdomains of a blocked domain', () {
      // EasyList lists "tracker.net"; requests come from its subdomains.
      expect(service.shouldBlock('https://eu.cdn.tracker.net/p.gif'), isTrue);
      expect(service.shouldBlock('https://a.b.c.doubleclick.net/x'), isTrue);
    });

    test('matching is case-insensitive', () {
      expect(service.shouldBlock('https://ADS.EXAMPLE.COM/x.js'), isTrue);
    });

    test('ignores path, query and port', () {
      expect(service.shouldBlock('http://tracker.net:8080/a?b=c#d'), isTrue);
    });
  });

  group('not blocking', () {
    test('lets an unrelated site through', () {
      expect(service.shouldBlock('https://wikipedia.org/wiki/Ads'), isFalse);
    });

    test('never blocks a bare TLD', () {
      // If the parent-domain walk ever reached the TLD, a list containing any
      // ".net" entry would take down every .net site on the web.
      service.seedBlocklistForTesting(const ['net', 'com', 'co.uk']);
      expect(service.shouldBlock('https://github.com/'), isFalse);
      expect(service.shouldBlock('https://example.net/'), isFalse);
    });

    test('a domain that merely ends with a blocked name is not blocked', () {
      // "nottracker.net" must not match "tracker.net" by suffix.
      expect(service.shouldBlock('https://nottracker.net/'), isFalse);
      expect(service.shouldBlock('https://evil-ads.example.com.attacker.io/'),
          isFalse);
    });

    test('blocks nothing at all when switched off', () {
      service.seedBlocklistForTesting(const ['ads.example.com'],
          enabled: false);
      expect(service.shouldBlock('https://ads.example.com/banner.js'), isFalse);
    });

    test('a malformed URL is allowed rather than throwing', () {
      for (final bad in ['', 'not a url', '::::', 'javascript:alert(1)']) {
        expect(() => service.shouldBlock(bad), returnsNormally, reason: bad);
        expect(service.shouldBlock(bad), isFalse, reason: bad);
      }
    });
  });

  group('built-in popup list', () {
    test('is non-empty and used even before EasyList downloads', () {
      final fresh = AdBlockService();
      expect(fresh.hardcodedPopupDomains, isNotEmpty);
      // Seed an empty EasyList: the built-ins must still apply.
      fresh.seedBlocklistForTesting(const []);
      final builtIn = fresh.hardcodedPopupDomains.first;
      expect(fresh.shouldBlock('https://$builtIn/popup'), isTrue);
    });
  });
}
