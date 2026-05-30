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
}
