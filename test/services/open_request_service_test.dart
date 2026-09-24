import 'package:convert_the_spire_reborn/src/services/open_request_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OpenRequest? classify(String raw, {String? name, String? mimeType}) =>
      OpenRequestService.classify(raw, name: name, mimeType: mimeType);

  group('OpenRequestService.classify', () {
    test('a magnet link from a browser', () {
      const magnet =
          'magnet:?xt=urn:btih:2d1bcb4930b86476406ea018137c0a464ee70e15'
          '&dn=Episode%2084';
      expect(classify(magnet),
          const OpenRequest(OpenRequestKind.magnet, magnet, name: ''));
      expect(classify('MAGNET:?xt=urn:btih:abc')?.kind, OpenRequestKind.magnet);
    });

    test('a video double-clicked in Explorer', () {
      final request = classify(r'C:\Users\me\Videos\Film (2024).mkv');
      expect(request?.kind, OpenRequestKind.media);
      expect(request?.target, r'C:\Users\me\Videos\Film (2024).mkv');
      expect(request?.isVideo, isTrue);
    });

    test('a song opened in Finder', () {
      final request = classify('/Users/me/Music/Café – Live.flac');
      expect(request?.kind, OpenRequestKind.media);
      expect(request?.name, 'Café – Live.flac');
      expect(request?.isVideo, isFalse);
    });

    test('a file:// address becomes a path', () {
      const url = 'file:///home/me/Downloads/show.torrent';
      final request = classify(url);
      expect(request?.kind, OpenRequestKind.torrentFile);
      // The platform's own path form (backslashes on Windows).
      expect(request?.target, Uri.parse(url).toFilePath());
      expect(request?.name, 'show.torrent');
    });

    test('an Android content address with its name and type', () {
      const uri =
          'content://com.android.providers.media.documents/document/video%3A42';
      final video = classify(uri, name: 'clip.mp4', mimeType: 'video/mp4');
      expect(video?.kind, OpenRequestKind.media);
      expect(video?.target, uri);
      expect(video?.name, 'clip.mp4');
      expect(video?.isVideo, isTrue);

      final torrent = classify(
          'content://com.android.providers.downloads.documents/document/12',
          name: 'release.torrent',
          mimeType: 'application/octet-stream');
      expect(torrent?.kind, OpenRequestKind.torrentFile);
    });

    test('the type decides when the name does not', () {
      expect(
          classify('content://media/external/audio/media/7',
                  mimeType: 'audio/mpeg')
              ?.isVideo,
          isFalse);
      final video = classify('content://media/external/video/media/9',
          name: 'VID_0001', mimeType: 'video/3gpp');
      expect(video?.kind, OpenRequestKind.media);
      expect(video?.isVideo, isTrue);
      expect(
          classify('content://downloads/1',
                  mimeType: 'application/x-bittorrent')
              ?.kind,
          OpenRequestKind.torrentFile);
    });

    test('quotes around a command-line argument are dropped', () {
      expect(classify(r'"D:\Music\song.mp3"')?.target, r'D:\Music\song.mp3');
    });

    test('flags and files the app does not open are ignored', () {
      expect(classify('--start-minimized'), isNull);
      expect(classify(''), isNull);
      expect(classify(r'C:\Users\me\notes.txt'), isNull);
      expect(classify('content://x/document/3', mimeType: 'application/pdf'),
          isNull);
    });

    test('every extension the player plays is offered', () {
      for (final extension in OpenRequestService.mediaExtensions) {
        expect(classify('/media/file$extension')?.kind, OpenRequestKind.media,
            reason: extension);
      }
    });
  });
}
