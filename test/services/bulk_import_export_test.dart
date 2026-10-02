import 'package:convert_the_spire_reborn/src/services/bulk_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = BulkImportService();

  group('trackFor', () {
    test('uses the tags when there are some', () {
      expect(
          BulkImportService.trackFor(
              artist: 'Daft Punk', title: 'One More Time', fileName: 'x'),
          (artist: 'Daft Punk', title: 'One More Time'));
    });

    test('reads a downloaded file name, without its video id', () {
      expect(
          BulkImportService.trackFor(
              fileName: 'Daft Punk - One More Time [FGBhQbmPwH8]'),
          (artist: 'Daft Punk', title: 'One More Time'));
    });

    test('does not name the artist twice', () {
      expect(
          BulkImportService.trackFor(
              artist: 'Daft Punk',
              title: 'Daft Punk - One More Time',
              fileName: ''),
          (artist: 'Daft Punk', title: 'One More Time'));
    });

    test('a title with no artist stays a title', () {
      expect(BulkImportService.trackFor(fileName: 'Lofi beats'),
          (artist: '', title: 'Lofi beats'));
    });
  });

  test('uniqueTracks drops repeats and blanks', () {
    final tracks = BulkImportService.uniqueTracks([
      (artist: 'A', title: 'Song'),
      (artist: 'a', title: 'SONG'),
      (artist: 'B', title: ''),
      (artist: 'B', title: 'Other'),
    ]);
    expect(
        tracks, [(artist: 'A', title: 'Song'), (artist: 'B', title: 'Other')]);
  });

  final tracks = <ListedTrack>[
    (artist: 'Daft Punk', title: 'One More Time'),
    (artist: 'Simon & Garfunkel', title: 'Cecilia, live'),
    (artist: '', title: 'Song "with" quotes'),
    (artist: 'Sigur Rós', title: 'Hoppípolla'),
  ];

  test('a text list reads back as the same searches', () {
    final text = BulkImportService.buildTextList(tracks);
    expect(text.split('\n').first, 'Daft Punk - One More Time');
    expect(service.parseText(text), [
      'Daft Punk One More Time',
      'Simon & Garfunkel Cecilia, live',
      'Song "with" quotes',
      'Sigur Rós Hoppípolla',
    ]);
  });

  test('a CSV list reads back as the same searches, header and all', () {
    final csv = BulkImportService.buildCsvList(tracks);
    expect(csv, startsWith('﻿Artist,Title\r\n'));
    expect(csv, contains('"Cecilia, live"'));
    expect(csv, contains('"Song ""with"" quotes"'));
    expect(service.parseCsv(csv), [
      'Daft Punk One More Time',
      'Simon & Garfunkel Cecilia, live',
      'Song "with" quotes',
      'Sigur Rós Hoppípolla',
    ]);
  });

  test('a CSV without a header keeps its first row', () {
    expect(service.parseCsv('Daft Punk,One More Time\nAir,Sexy Boy\n'),
        ['Daft Punk One More Time', 'Air Sexy Boy']);
  });
}
