import 'package:convert_the_spire_reborn/src/browser/adblock/adblock_scripts.dart';
import 'package:convert_the_spire_reborn/src/browser/adblock/filter_list.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ad blocker's filter lists (issue #41: the built-in blocker let ads
/// through where uBlock Origin did not). Lines are in the EasyList syntax;
/// most are taken from EasyList and EasyPrivacy as they are.
void main() {
  FilterSet parse(String list) => FilterSet.parse(list.split('\n'));

  group('requests', () {
    test('a host rule blocks the host and its subdomains', () {
      final f = parse('||adnxs.com^\n||ads.example.org^\$third-party');
      expect(f.blocks('https://adnxs.com/x.js'), isTrue);
      expect(f.blocks('https://ib.adnxs.com/ut/v3'), isTrue);
      expect(f.blocks('https://ads.example.org/b.gif'), isTrue);
      expect(f.blocks('https://example.org/'), isFalse);
      expect(f.blocks('https://notadnxs.com/'), isFalse);
    });

    test('a rule with a path blocks that path, not the whole host', () {
      // These cut down to the host blocked all of cloudfront.net, and every
      // site that serves its files from there.
      final f = parse('||cloudfront.net/ads/\n||anrdoezrs.net/image-');
      expect(f.blocks('https://d1.cloudfront.net/ads/banner.js'), isTrue);
      expect(f.blocks('https://d1.cloudfront.net/app/main.js'), isFalse);
      expect(f.blocks('https://www.anrdoezrs.net/image-123'), isTrue);
      expect(f.blocks('https://www.anrdoezrs.net/click-123'), isFalse);
    });

    test('wildcards, separators and the end anchor', () {
      final f = parse('||opera.com^*utm_source=oft\n'
          '||example.com/ad.js|\n'
          '||example.net/*/banner^');
      expect(f.blocks('https://net.geo.opera.com/x?utm_source=OFT'), isTrue);
      expect(f.blocks('https://opera.com/download'), isFalse);
      expect(f.blocks('https://example.com/ad.js'), isTrue);
      expect(f.blocks('https://example.com/ad.json'), isFalse);
      expect(f.blocks('https://example.net/a/b/banner'), isTrue);
      expect(f.blocks('https://example.net/a/banner?x'), isTrue);
      expect(f.blocks('https://example.net/a/bannerx'), isFalse);
    });

    test('exceptions win over blocks', () {
      final f = parse('||tracker.com^\n@@||cdn.tracker.com^\n'
          '||widgets.com^\n@@||widgets.com/player/');
      expect(f.blocks('https://tracker.com/t.js'), isTrue);
      expect(f.blocks('https://cdn.tracker.com/lib.js'), isFalse);
      expect(f.blocks('https://widgets.com/ad.js'), isTrue);
      expect(f.blocks('https://widgets.com/player/embed.js'), isFalse);
    });

    test('rules limited to some pages apply on those pages only', () {
      final f = parse('||adserver.com^\$domain=news.com|~sport.news.com\n'
          '||googletagmanager.com^\n'
          '@@||googletagmanager.com/gtm.js\$domain=shop.com');
      const ad = 'https://adserver.com/a.js';
      expect(f.blocks(ad, pageUrl: 'https://www.news.com/a'), isTrue);
      expect(f.blocks(ad, pageUrl: 'https://sport.news.com/a'), isFalse);
      expect(f.blocks(ad, pageUrl: 'https://blog.com/'), isFalse);
      const gtm = 'https://www.googletagmanager.com/gtm.js?id=1';
      expect(f.blocks(gtm, pageUrl: 'https://shop.com/'), isFalse);
      expect(f.blocks(gtm, pageUrl: 'https://other.com/'), isTrue);
    });

    test('nothing is blocked on a page the lists allow', () {
      final f = parse('||ads.com^\n@@||bank.com^\$document');
      expect(f.blocks('https://ads.com/x', pageUrl: 'https://bank.com/'),
          isFalse);
      expect(f.blocks('https://ads.com/x', pageUrl: 'https://shop.com/'),
          isTrue);
    });

    test("YouTube's and Google's pages keep their requests", () {
      final f = parse('||doubleclick.net^');
      const ad = 'https://googleads.g.doubleclick.net/pagead/id';
      expect(f.blocks(ad, pageUrl: 'https://www.youtube.com/watch?v=x'),
          isFalse);
      expect(f.blocks(ad, pageUrl: 'https://www.google.co.uk/search?q=x'),
          isFalse);
      expect(f.blocks(ad, pageUrl: 'https://news.example.com/'), isTrue);
    });

    test('rules it cannot apply as written are left out', () {
      final f = parse([
        '||bet365.com/*?affiliate=\$document', // navigation only
        '||popads.example^\$popup', // popups only
        '||first.com^\$~third-party', // first-party only
        '||142.91.159.', // an address prefix
        '||cacheserve.*/promodisplay/', // any domain
        '/ads/banner*', // not anchored to a host
        '||redirected.com^\$script,redirect=noopjs',
      ].join('\n'));
      expect(f.blocks('https://bet365.com/x?affiliate=1'), isFalse);
      expect(f.blocks('https://first.com/x'), isFalse);
      expect(f.blocks('https://142.91.159.1/x'), isFalse);
      expect(f.blocks('https://site.com/ads/banner1.png'), isFalse);
      expect(f.blocks('https://redirected.com/x.js'), isFalse);
      expect(f.ruleCount, 0);
    });

    test('only web URLs are matched', () {
      final f = parse('||ads.com^');
      for (final url in [
        '',
        'not a url',
        'data:text/html,ads.com',
        'blob:https://ads.com/1',
        'javascript:alert(1)',
      ]) {
        expect(f.blocks(url), isFalse, reason: url);
      }
      expect(f.blocks('wss://ads.com/socket'), isTrue);
      expect(f.blocks('https://user@ads.com:8443/x'), isTrue);
      // A path rule applies whatever the port.
      expect(parse('||cdn.com/ad.js').blocks('http://cdn.com:8080/ad.js'),
          isTrue);
    });
  });

  group('hiding', () {
    test('generic, per site and exceptions', () {
      final f = parse('##.ad-banner\n##div[id^="ad_"]\n'
          'example.com,news.org##.sidebar-promo\n'
          'example.com#@#.ad-banner\n'
          '~shop.com##.sponsored\n'
          '#@#div[id^="ad_"]');
      expect(f.genericHide, ['.ad-banner', '.sponsored']);
      expect(f.selectorsFor('www.example.com'), ['.sidebar-promo']);
      expect(f.exceptionsFor('www.example.com'), ['.ad-banner']);
      expect(f.exceptionsFor('shop.com'), ['.sponsored']);
      expect(f.selectorsFor('other.com'), isEmpty);
    });

    test('extended and malformed selectors are left out', () {
      final f = parse([
        'example.com##.ad:has-text(Sponsored)',
        'example.com##+js(set, x, 1)',
        'example.com#?#.ad:-abp-contains(Ad)',
        'example.com##div:upward(2)',
        '##[data-ad="x"',
        '##.a{color:red}',
        '##.ok:has(> .sponsored)',
      ].join('\n'));
      expect(f.selectorsFor('example.com'), isEmpty);
      expect(f.genericHide, ['.ok:has(> .sponsored)']);
    });

    test('\$generichide and \$elemhide exceptions', () {
      final f = parse('@@||forum.com^\$generichide\n@@||game.com^\$elemhide\n'
          'game.com##.x');
      expect(f.noGenericHide, {'forum.com'});
      expect(f.noHide, {'game.com'});
      expect(f.selectorsFor('game.com'), isEmpty);
    });

    test('the page scripts carry the rules', () {
      final f = parse('##.ad-banner\nexample.com##.promo');
      final start = documentStartScript(f, skipYouTubeAds: true);
      expect(start, contains('.ad-banner'));
      expect(start, contains('ytp-ad-skip-button'));
      expect(documentStartScript(f, skipYouTubeAds: false),
          isNot(contains('ytp-ad-skip-button')));
      expect(siteHideScriptFor(f, 'https://example.com/a'), contains('.promo'));
      expect(siteHideScriptFor(f, 'https://other.com/'), isNull);
    });
  });

  test('survives a round trip through its cache', () {
    final f = parse('||ads.com^\n@@||ok.ads.com^\n||cdn.com/ad/\$domain=a.com\n'
        '##.ad\nx.com##.y\nx.com#@#.ad\n@@||z.com^\$generichide');
    final back = FilterSet.fromJson(f.toJson())!;
    expect(back.blocks('https://ads.com/'), isTrue);
    expect(back.blocks('https://ok.ads.com/'), isFalse);
    expect(back.blocks('https://cdn.com/ad/1', pageUrl: 'https://a.com/'),
        isTrue);
    expect(back.blocks('https://cdn.com/ad/1', pageUrl: 'https://b.com/'),
        isFalse);
    expect(back.genericHide, ['.ad']);
    expect(back.selectorsFor('x.com'), ['.y']);
    expect(back.noGenericHide, {'z.com'});
    expect(FilterSet.fromJson({'v': 0}), isNull);
  });
}
