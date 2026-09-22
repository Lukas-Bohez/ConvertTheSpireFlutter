import 'package:convert_the_spire_reborn/src/services/playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plain WEB innertube client stops handing out continuation tokens after
/// two pages (~200 entries) on large playlists — verified against an 863-entry
/// playlist where page 2 comes back with no continuation item at all. The app
/// falls back to the WEB_REMIX (YouTube Music) client, which pages all the way
/// but returns a third item shape: `musicResponsiveListItemRenderer`.
///
/// These fixtures mirror a real WEB_REMIX response.
String wrapHtml(String json) =>
    '<html><script>var ytInitialData = $json;</script></html>';

const _musicItem = r'''
{
  "contents": {
    "items": [
      {
        "musicResponsiveListItemRenderer": {
          "flexColumns": [
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": { "runs": [{
                  "text": "ALKALI UNDERACHIEVER",
                  "navigationEndpoint": {
                    "watchEndpoint": { "videoId": "zLmopbS97aY" }
                  }
                }] }
              }
            },
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": { "runs": [{
                  "text": "Kairiki bear",
                  "navigationEndpoint": {
                    "browseEndpoint": { "browseId": "UCVabUP125D3UyIicCGEOFQw" }
                  }
                }] }
              }
            }
          ],
          "fixedColumns": [
            {
              "musicResponsiveListItemFixedColumnRenderer": {
                "text": { "runs": [{ "text": "3:28" }] }
              }
            }
          ],
          "playlistItemData": { "videoId": "zLmopbS97aY" }
        }
      }
    ]
  }
}''';

/// A menu browseId appears *before* the artist column in document order, so a
/// bare recursive search for `browseId` would return the album id.
const _musicItemWithMenu = r'''
{
  "contents": {
    "items": [
      {
        "musicResponsiveListItemRenderer": {
          "menu": {
            "items": [
              { "browseEndpoint": { "browseId": "MPREb_WRONGALBUMIDXX" } }
            ]
          },
          "flexColumns": [
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": { "runs": [{ "text": "Some Song" }] }
              }
            },
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": { "runs": [{
                  "text": "Real Artist",
                  "navigationEndpoint": {
                    "browseEndpoint": { "browseId": "UCVabUP125D3UyIicCGEOFQw" }
                  }
                }] }
              }
            }
          ],
          "playlistItemData": { "videoId": "zLmopbS97aY" }
        }
      }
    ]
  }
}''';

const _musicItemUnusable = r'''
{
  "contents": {
    "items": [
      {
        "musicResponsiveListItemRenderer": {
          "flexColumns": [],
          "playlistItemData": { "videoId": "short" }
        }
      }
    ]
  }
}''';

/// A page that mixes the music shape with the ordinary lockup shape: the
/// fallback pass merges into the same result list, so both must parse.
const _mixedPage = r'''
{
  "contents": {
    "items": [
      {
        "lockupViewModel": {
          "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
          "contentId": "aaaaaaaaaaa",
          "metadata": {
            "lockupMetadataViewModel": { "title": { "content": "Lockup Song" } }
          }
        }
      },
      {
        "musicResponsiveListItemRenderer": {
          "flexColumns": [
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": { "runs": [{ "text": "Music Song" }] }
              }
            }
          ],
          "playlistItemData": { "videoId": "bbbbbbbbbbb" }
        }
      }
    ]
  }
}''';

void main() {
  group('WEB_REMIX musicResponsiveListItemRenderer', () {
    test('parses title, artist, duration and video id', () {
      final videos = PlaylistService.parsePlaylistHtmlForTesting(
          wrapHtml(_musicItem));

      expect(videos, hasLength(1));
      final v = videos.single;
      expect(v.id.value, 'zLmopbS97aY');
      expect(v.title, 'ALKALI UNDERACHIEVER');
      expect(v.author, 'Kairiki bear');
      expect(v.duration, const Duration(minutes: 3, seconds: 28));
    });

    test('reads the channel id from the artist column, not the menu', () {
      final v = PlaylistService.parsePlaylistHtmlForTesting(
          wrapHtml(_musicItemWithMenu));

      expect(v.single.channelId.value, 'UCVabUP125D3UyIicCGEOFQw');
    });

    test('skips an item with no usable video id', () {
      expect(
          PlaylistService.parsePlaylistHtmlForTesting(
              wrapHtml(_musicItemUnusable)),
          isEmpty);
    });

    test('an item with no duration column still parses', () {
      final v = PlaylistService.parsePlaylistHtmlForTesting(
          wrapHtml(_mixedPage));
      final music = v.firstWhere((e) => e.id.value == 'bbbbbbbbbbb');
      expect(music.title, 'Music Song');
      expect(music.duration, isNull);
    });

    test('music and lockup items on one page both parse', () {
      final videos =
          PlaylistService.parsePlaylistHtmlForTesting(wrapHtml(_mixedPage));

      expect(videos.map((e) => e.title), ['Lockup Song', 'Music Song']);
    });
  });
}
