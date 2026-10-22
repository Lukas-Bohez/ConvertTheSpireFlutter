import 'package:convert_the_spire_reborn/src/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadService.resolveDownloadTitle', () {
    test('prefers the title shown in the app over the source title', () {
      expect(
        DownloadService.resolveDownloadTitle(
          'Lagtrain',
          sourceTitle: 'ラグトレイン',
        ),
        'Lagtrain',
      );
    });

    test('falls back to the source title when the preferred title is blank',
        () {
      expect(
        DownloadService.resolveDownloadTitle(
          '   ',
          sourceTitle: 'ラグトレイン',
        ),
        'ラグトレイン',
      );
    });

    test('uses a safe placeholder when both titles are blank', () {
      expect(
        DownloadService.resolveDownloadTitle('   ', sourceTitle: '   '),
        'download',
      );
    });
  });

  group('DownloadService.resolveDownloadArtist', () {
    test('prefers the artist shown in the app over the source artist', () {
      expect(
        DownloadService.resolveDownloadArtist(
          'Ken Ashcorp',
          sourceArtist: 'Source Author',
        ),
        'Ken Ashcorp',
      );
    });

    test('falls back to the source artist when the preferred artist is blank',
        () {
      expect(
        DownloadService.resolveDownloadArtist(
          '   ',
          sourceArtist: 'Source Author',
        ),
        'Source Author',
      );
    });

    test('uses a placeholder when both artist values are blank', () {
      expect(
        DownloadService.resolveDownloadArtist('   ', sourceArtist: '   '),
        'Unknown',
      );
    });
  });

  // Issue #45, fix 9: the in-app browser queued YouTube songs as "YouTube",
  // and files came out as YouTube.mp3 without their real title or artist.
  group('site names never beat the video', () {
    test('"YouTube" as title or artist gives way to the source', () {
      expect(
        DownloadService.resolveDownloadTitle('YouTube', sourceTitle: 'Lagtrain'),
        'Lagtrain',
      );
      expect(
        DownloadService.resolveDownloadArtist('YouTube',
            sourceArtist: 'inabakumori'),
        'inabakumori',
      );
      expect(
        DownloadService.resolveDownloadTitle('YouTube Music',
            sourceTitle: 'Lagtrain'),
        'Lagtrain',
      );
    });

    test('a link or a host name is not a title', () {
      expect(
        DownloadService.resolveDownloadTitle(
            'https://www.youtube.com/watch?v=UnIhRpIT7nc',
            sourceTitle: 'Lagtrain'),
        'Lagtrain',
      );
      expect(
        DownloadService.resolveDownloadArtist('m.youtube.com',
            sourceArtist: 'inabakumori'),
        'inabakumori',
      );
    });

    test('a placeholder is still used when nothing better is known', () {
      expect(DownloadService.resolveDownloadTitle('YouTube'), 'YouTube');
      expect(DownloadService.isPlaceholderName('Lagtrain'), isFalse);
      expect(DownloadService.isPlaceholderName('Mr. Blue Sky'), isFalse);
    });
  });
}
