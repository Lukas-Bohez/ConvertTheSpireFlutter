import 'package:flutter_test/flutter_test.dart';

import 'package:convert_the_spire_reborn/src/utils/youtube_link.dart';

void main() {
  const video = 'dQw4w9WgXcQ';
  const list = 'PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG';

  test('a video playing from a playlist carries both, so the app asks', () {
    final link = YouTubeLink.parse(
        'https://www.youtube.com/watch?v=$video&list=$list&index=4')!;
    expect(link.videoId, video);
    expect(link.playlistId, list);
    expect(link.isVideoInPlaylist, isTrue);
    expect(link.playlistUrl, 'https://www.youtube.com/playlist?list=$list');
    expect(link.videoUrl, 'https://www.youtube.com/watch?v=$video');
  });

  test('a playlist page is a playlist, not a generic web page', () {
    final link =
        YouTubeLink.parse('https://m.youtube.com/playlist?list=$list')!;
    expect(link.hasVideo, isFalse);
    expect(link.hasDownloadablePlaylist, isTrue);
  });

  test('a plain video has no playlist to offer', () {
    for (final url in [
      'https://www.youtube.com/watch?v=$video',
      'https://youtu.be/$video',
      'https://youtube.com/shorts/$video',
      'https://www.youtube-nocookie.com/embed/$video',
      'https://music.youtube.com/watch?v=$video',
    ]) {
      final link = YouTubeLink.parse(url)!;
      expect(link.videoId, video, reason: url);
      expect(link.isVideoInPlaylist, isFalse, reason: url);
    }
  });

  test('mixes, Watch Later and Liked only offer the video', () {
    for (final id in ['RD$video', 'RDMM', 'WL', 'LL']) {
      final link = YouTubeLink.parse(
          'https://www.youtube.com/watch?v=$video&list=$id')!;
      expect(link.hasDownloadablePlaylist, isFalse, reason: id);
      expect(link.isVideoInPlaylist, isFalse, reason: id);
      expect(link.hasVideo, isTrue);
    }
  });

  test('other sites and junk are not YouTube', () {
    expect(YouTubeLink.parse('https://vimeo.com/12345'), isNull);
    expect(YouTubeLink.parse('https://notyoutube.com/watch?v=$video'), isNull);
    expect(YouTubeLink.parse('not a url'), isNull);
    expect(YouTubeLink.parse(''), isNull);
  });

  test('malformed ids are ignored rather than trusted', () {
    final link =
        YouTubeLink.parse('https://www.youtube.com/watch?v=short&list=a b')!;
    expect(link.hasVideo, isFalse);
    expect(link.playlistId, isNull);
  });
}
