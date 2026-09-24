import 'package:convert_the_spire_reborn/src/services/media_range.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards Range parsing for the media stream.
///
/// Range support is what lets a guest or a TV seek in the host's stream
/// instead of waiting for the whole file (issue #7). The previous copy of this
/// logic did no clamping, so a range past the end of the file would have tried
/// to read past the end of the file.
void main() {
  const length = 1000;

  group('parseByteRange', () {
    test('no header means send everything', () {
      expect(parseByteRange(null, length), isNull);
    });

    test('an open-ended range runs to the last byte', () {
      final range = parseByteRange('bytes=500-', length)!;

      expect(range.start, 500);
      expect(range.end, 999);
      expect(range.length, 500);
      expect(range.contentRangeHeader, 'bytes 500-999/1000');
    });

    test('a closed range is taken as given', () {
      final range = parseByteRange('bytes=0-99', length)!;

      expect(range.start, 0);
      expect(range.end, 99);
      expect(range.length, 100);
    });

    test('a suffix range means the last N bytes', () {
      final range = parseByteRange('bytes=-200', length)!;

      expect(range.start, 800);
      expect(range.end, 999);
    });

    test('a suffix longer than the file starts at zero', () {
      final range = parseByteRange('bytes=-5000', length)!;

      expect(range.start, 0);
      expect(range.end, 999);
    });

    test('an end past the file is clamped, not trusted', () {
      final range = parseByteRange('bytes=900-99999', length)!;

      expect(range.end, 999, reason: 'must never read past the end');
      expect(range.length, 100);
    });

    test('a start past the end is unsatisfiable', () {
      expect(() => parseByteRange('bytes=5000-', length), throwsRangeError);
    });

    test('an inverted range is unsatisfiable', () {
      expect(() => parseByteRange('bytes=800-100', length), throwsRangeError);
    });

    test('a unit we do not serve is ignored', () {
      expect(parseByteRange('items=0-10', length), isNull);
      expect(parseByteRange('bytes=abc', length), isNull);
      expect(parseByteRange('bytes=-', length), isNull);
    });

    test('an offset too large for an int is unsatisfiable, not a crash', () {
      expect(() => parseByteRange('bytes=99999999999999999999999-', length),
          throwsRangeError);
      expect(() => parseByteRange('bytes=-99999999999999999999999', length),
          throwsRangeError);
    });

    test('an empty file has no ranges to serve', () {
      expect(parseByteRange('bytes=0-10', 0), isNull);
    });

    test('the whole file as an explicit range still works', () {
      final range = parseByteRange('bytes=0-999', length)!;

      expect(range.length, length);
    });
  });
}
