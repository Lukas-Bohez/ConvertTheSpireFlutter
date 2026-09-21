import 'package:convert_the_spire_reborn/src/services/playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the "playlists stop at 100 videos on Android" bug.
///
/// Android has no yt-dlp fallback, so every playlist is enumerated by the
/// in-app page parser. That parser walks pages by following a continuation
/// token. YouTube emits that token in several different shapes; the parser
/// only understood one of them, so on any playlist whose page used a different
/// shape pagination stopped after the first page - exactly 100 entries.
String _wrapHtml(String json) =>
    '<html><script>var ytInitialData = $json;</script></html>';

void main() {
  group('continuation tokens - every shape YouTube emits', () {
    test('continuationItemRenderer shape yields a token (the 100-cap bug)', () {
      // This is the shape the innertube browse API returns for playlists.
      // Before the fix it produced no token, so page 2 was never requested.
      final html = _wrapHtml('''
      {
        "contents": {
          "items": [
            {
              "continuationItemRenderer": {
                "continuationEndpoint": {
                  "continuationCommand": { "token": "RENDERER_TOKEN" }
                }
              }
            }
          ]
        }
      }''');

      expect(PlaylistService.continuationTokensForTesting(html),
          contains('RENDERER_TOKEN'));
    });

    test('bare continuationCommand shape yields a token', () {
      final html = _wrapHtml('''
      {
        "contents": {
          "items": [
            { "continuationCommand": { "token": "BARE_TOKEN" } }
          ]
        }
      }''');

      expect(PlaylistService.continuationTokensForTesting(html),
          contains('BARE_TOKEN'));
    });

    test('continuationItemViewModel shape still works', () {
      final html = _wrapHtml('''
      {
        "contents": {
          "items": [
            {
              "continuationItemViewModel": {
                "continuationViewModel": { "continuation": "VIEWMODEL_TOKEN" }
              }
            }
          ]
        }
      }''');

      expect(PlaylistService.continuationTokensForTesting(html),
          contains('VIEWMODEL_TOKEN'));
    });

    test('a page with no next page yields no token, so paging terminates', () {
      final html = _wrapHtml('{"contents": {"items": []}}');
      expect(PlaylistService.continuationTokensForTesting(html), isEmpty);
    });

    test('the same token is never reported twice', () {
      // The recursive walk visits nested containers; a token reachable by more
      // than one route must not be spent twice or paging would stall.
      final html = _wrapHtml('''
      {
        "contents": {
          "outer": {
            "continuationItemRenderer": {
              "continuationEndpoint": {
                "continuationCommand": { "token": "DUPE" }
              }
            }
          }
        }
      }''');

      final tokens = PlaylistService.continuationTokensForTesting(html);
      expect(tokens.where((t) => t == 'DUPE').length, 1);
    });
  });

  group('playlist items - classic playlistVideoRenderer shape', () {
    test('parses videos that use playlistVideoRenderer', () {
      // Continuation pages routinely fall back to this classic shape even when
      // page 1 used the newer lockupViewModel. Before the fix these pages
      // parsed to zero videos, so a playlist could page forever adding nothing.
      final html = _wrapHtml('''
      {
        "contents": {
          "items": [
            {
              "playlistVideoRenderer": {
                "videoId": "dQw4w9WgXcQ",
                "title": { "runs": [{ "text": "First Song" }] },
                "shortBylineText": {
                  "runs": [{
                    "text": "Some Channel",
                    "navigationEndpoint": {
                      "browseEndpoint": {
                        "browseId": "UCuAXFkgsw1L7xaCfnd5JJOw"
                      }
                    }
                  }]
                },
                "lengthSeconds": "212"
              }
            },
            {
              "playlistVideoRenderer": {
                "videoId": "9bZkp7q19f0",
                "title": { "simpleText": "Second Song" },
                "lengthText": { "simpleText": "4:13" }
              }
            }
          ]
        }
      }''');

      final videos = PlaylistService.parsePlaylistHtmlForTesting(html);

      expect(videos.map((v) => v.id.value), ['dQw4w9WgXcQ', '9bZkp7q19f0']);
      expect(videos[0].title, 'First Song');
      expect(videos[0].author, 'Some Channel');
      expect(videos[0].duration, const Duration(seconds: 212));
      // simpleText titles and lengthText durations are read too.
      expect(videos[1].title, 'Second Song');
      expect(videos[1].duration, const Duration(minutes: 4, seconds: 13));
    });

    test('entries without a usable video id or title are skipped', () {
      final html = _wrapHtml('''
      {
        "contents": {
          "items": [
            {
              "playlistVideoRenderer": {
                "videoId": "tooshort",
                "title": { "simpleText": "Bad Id" }
              }
            },
            {
              "playlistVideoRenderer": { "videoId": "dQw4w9WgXcQ" }
            }
          ]
        }
      }''');

      expect(PlaylistService.parsePlaylistHtmlForTesting(html), isEmpty);
    });

    test('a page mixing both item shapes returns both, in order', () {
      final html = _wrapHtml('''
      {
        "contents": {
          "items": [
            {
              "lockupViewModel": {
                "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "contentId": "aaaaaaaaaaa",
                "metadata": {
                  "lockupMetadataViewModel": {
                    "title": { "content": "Lockup Song" }
                  }
                }
              }
            },
            {
              "playlistVideoRenderer": {
                "videoId": "bbbbbbbbbbb",
                "title": { "simpleText": "Renderer Song" }
              }
            }
          ]
        }
      }''');

      final videos = PlaylistService.parsePlaylistHtmlForTesting(html);
      expect(videos.map((v) => v.title), ['Lockup Song', 'Renderer Song']);
    });
  });
}
