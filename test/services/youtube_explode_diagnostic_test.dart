import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

/// Diagnostic: fetch the raw playlist HTML and inspect what renderer keys
/// YouTube currently embeds, to understand why youtube_explode_dart 3.1.0's
/// parser finds no videos.
void main() {
  test('raw playlist HTML structure diagnostic', () async {
    final resp = await http.get(
      Uri.parse(
          'https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf&hl=en&persist_hl=1'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );
    expect(resp.statusCode, 200, reason: 'playlist page should be fetchable');
    final html = resp.body;
    print('DIAG html length: ${html.length}');

    // Which renderer keys are present?
    final keys = [
      'playlistVideoRenderer',
      'playlistVideoListRenderer',
      'richItemRenderer',
      'twoColumnBrowseResultsRenderer',
      'sectionListRenderer',
      'itemSectionRenderer',
      'lockupViewModel', // NEW ViewModel-style renderers YouTube is migrating to
      'videoRenderer',
      'lockupViewModelRenderer',
      'contentId',
    ];
    for (final k in keys) {
      final count = k.allMatches(html).length;
      print('DIAG "$k": $count occurrences');
    }

    // Where is ytInitialData and how big is it?
    final idx = html.indexOf('ytInitialData');
    print('DIAG ytInitialData found at: $idx');

    // Extract a sample around the first video-ish content to see the shape.
    final videoIdSample = html.indexOf('"videoId"');
    print('DIAG first "videoId" at: $videoIdSample');
    if (videoIdSample > 0) {
      final start = (videoIdSample - 400).clamp(0, html.length);
      final end = (videoIdSample + 400).clamp(0, html.length);
      print('DIAG context around first videoId:');
      print(html.substring(start, end).replaceAll('\n', ' '));
    }

    // The new format stores titles as "title":{"content":"..."} - find those.
    var titleFrom = 0;
    var titleOcc = 0;
    while (true) {
      final idx = html.indexOf('"title":{"content"', titleFrom);
      if (idx < 0) break;
      titleOcc++;
      print('DIAG === title.content #$titleOcc at $idx ===');
      final start = (idx - 300).clamp(0, html.length);
      final end = (idx + 1500).clamp(0, html.length);
      print(html.substring(start, end).replaceAll('\n', ' '));
      titleFrom = idx + 19;
      if (titleOcc >= 1) break;
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
