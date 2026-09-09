import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:convert_the_spire_reborn/src/services/playlist_service.dart';

/// Deterministic, offline tests for the Lockup parser that fixes the Android
/// "0/800" playlist bug. A captured-style HTML fixture with real expected
/// values is used instead of hitting live YouTube (which serves consent or
/// bot-check pages to datacenter IPs, making live tests flaky).
void main() {
  group('PlaylistService - Lockup parser (offline fixtures)', () {
    test('extracts videos in document order with correct fields', () {
      // Realistic YouTube playlist page embed. The continuation token is
      // present too, as real pages have both.
      const html = '''
      <!DOCTYPE html><html><head>
      <script>
      var ytInitialData = {
        "responseContext": {
          "webResponseContextExtensionData": {
            "ytConfigData": { "visitorData": "CgIKbC0" }
          }
        },
        "contents": {
          "twoColumnBrowseResultsRenderer": {
            "tabs": [ {
              "tabRenderer": { "content": {
                "sectionListRenderer": {
                  "contents": [
                    { "playlistVideoListRenderer": {
                        "contents": [
                          {
                            "lockupViewModel": {
                              "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                              "content": {
                                "contentId": "VIDEOID1111",
                                "channelId": "CHANNEL01",
                                "metadata": {
                                  "title": { "content": "First Song" },
                                  "secondaryText": { "content": "@Artist Alpha" },
                                  "thirdText": { "content": "4:05" }
                                }
                              },
                              "primaryContent": {
                                "metadata": {
                                  "title": { "content": "First Song" }
                                }
                              }
                            }
                          },
                          {
                            "continuationItemViewModel": {
                              "continuationViewModel": {
                                "continuation": "TOKEN_ABC_123"
                              }
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              } }
            } ]
          }
        }
      };
      </script>
      </head><body></body></html>
      ''';

      final videos = PlaylistService.parsePlaylistHtmlForTesting(html);

      expect(videos.length, equals(1),
          reason: 'Should extract exactly the one video lockup');
      expect(videos.first.id.value, equals('VIDEOID1111'));
      expect(videos.first.title, equals('First Song'));
      expect(videos.first.author, equals('Artist Alpha'));
      expect(videos.first.duration, equals(Duration(seconds: 245)));
    });
  test('position independence: finds lockups under any wrapper names', () {
      // The second video sits inside an unrelated "weirdContainer" list, with
      // duration in the alternative "viewText" position and no channel name.
      const html = '''
      <script>
      var ytInitialData = {
        "contents": {
          "someWeirdRenderer": {
            "nestedList": [
              { "weirdContainer": [
                  {
                    "lockupViewModel": {
                      "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                      "content": {
                        "contentId": "VIDEOID2222",
                        "metadata": {
                          "title": { "content": "Second Song" }
                        },
                        "viewText": { "content": "1:02:03" }
                      }
                    }
                  }
                ]
              }
            ]
          }
        }
      };
      </script>
      ''';

      final videos = PlaylistService.parsePlaylistHtmlForTesting(html);

      expect(videos.length, equals(1));
      expect(videos.first.id.value, equals('VIDEOID2222'));
      expect(videos.first.title, equals('Second Song'));
      expect(videos.first.author, equals(''));
      expect(videos.first.duration, equals(Duration(seconds: 3723)));
    });

    test('consent/blocked page (no ytInitialData) yields no videos', () {
      const consentPage = '''
      <!DOCTYPE html><html><body>
      <h1>Before you continue to YouTube</h1>
      <form action="consent">...</form>
      <script>window.onGoogle = "x";</script>
      </body></html>
      ''';

      final videos = PlaylistService.parsePlaylistHtmlForTesting(consentPage);
      expect(videos, isEmpty);
    });

    test('collects continuation tokens for pagination (the 800+ fix)', () {
      const html = '''
      <script>
      var ytInitialData = {
        "contents": {
          "renderer": {
            "contents": [
              { "continuationItemViewModel": {
                  "continuationViewModel": { "continuation": "TOKEN_A" }
                } },
              { "continuationItemViewModel": {
                  "continuationViewModel": { "continuation": "TOKEN_B" }
                } }
            ]
          }
        }
      };
      </script>
      ''';

      final tokens = PlaylistService.continuationTokensForTesting(html);
      expect(tokens.length, equals(2));
      expect(tokens, contains('TOKEN_A'));
      expect(tokens, contains('TOKEN_B'));
    });

    test('skips lockups with malformed video ids instead of crashing', () {
      const html = '''
      <script>
      var ytInitialData = {
        "contents": {
          "renderer": [ {
              "lockupViewModel": {
                "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "content": { "contentId": "tooshort", "title": { "content": "Bad" } }
              }
            },
            {
              "lockupViewModel": {
                "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
                "content": {
                  "contentId": "VIDEOID3333",
                  "metadata": { "title": { "content": "Good Song" } }
                }
              }
            }
          ]
        }
      };
      </script>
      ''';

      final videos = PlaylistService.parsePlaylistHtmlForTesting(html);
      expect(videos.length, equals(1));
      expect(videos.first.id.value, equals('VIDEOID3333'));
    });

    test('parses real YouTube lockupViewModel structure (lockupMetadataViewModel + contentMetadataViewModel)', () {
      // This matches the actual YouTube page structure observed in the wild.
      // Built with StringBuffer to avoid triple-quote escaping issues with the
      // _extractYtInitialData brace-matcher.
      final sb = StringBuffer();
      sb.writeln('<script>');
      sb.writeln('var ytInitialData = {');
      sb.writeln('  "contents": {');
      sb.writeln('    "twoColumnBrowseResultsRenderer": {');
      sb.writeln('      "tabs": [ { "tabRenderer": { "content": {');
      sb.writeln('        "sectionListRenderer": {');
      sb.writeln('          "contents": [');
      sb.writeln('            { "playlistVideoListRenderer": {');
      sb.writeln('                "contents": [');
      sb.writeln('                  {');
      sb.writeln('                    "lockupViewModel": {');
      sb.writeln('                      "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",');
      sb.writeln('                      "content": {');
      sb.writeln('                        "contentId": "0VH1Lim8gL8",');
      sb.writeln('                        "metadata": {');
      sb.writeln('                          "lockupMetadataViewModel": {');
      sb.writeln('                            "title": { "content": "Deep Learning State of the Art (2020)" }');
      sb.writeln('                          },');
      sb.writeln('                          "contentMetadataViewModel": {');
      sb.writeln('                            "metadataRows": [');
      sb.writeln('                              { "metadataParts": [');
      sb.writeln('                                { "text": { "content": "Lex Fridman" } },');
      sb.writeln('                                { "text": { "content": "1:02:03" } }');
      sb.writeln('                              ] }');
      sb.writeln('                            ]');
      sb.writeln('                          }');
      sb.writeln('                        }');
      sb.writeln('                      }');
      sb.writeln('                    }');
      sb.writeln('                  }');
      sb.writeln('                ]');
      sb.writeln('              }');
      sb.writeln('            }');
      sb.writeln('          ]');
      sb.writeln('        }');
      sb.writeln('      } } } ]');
      sb.writeln('    }');
      sb.writeln('  }');
      sb.writeln('};');
      sb.writeln('</script>');
      final html = sb.toString();

      final videos = PlaylistService.parsePlaylistHtmlForTesting(html);
      expect(videos.length, equals(1),
          reason: 'Should extract the one video from the real YouTube structure');
      expect(videos.first.id.value, equals('0VH1Lim8gL8'));
      expect(videos.first.title, equals('Deep Learning State of the Art (2020)'));
      expect(videos.first.author, equals('Lex Fridman'));
    });
  });
}
