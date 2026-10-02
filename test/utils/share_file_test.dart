import 'package:convert_the_spire_reborn/src/utils/share_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeShareName', () {
    test('keeps an ordinary title', () {
      expect(safeShareName('Artist - Song (Live)'), 'Artist - Song (Live)');
    });

    test('replaces characters no file system takes', () {
      expect(
          safeShareName('AC/DC: Back <In> Black?'), 'AC_DC_ Back _In_ Black_');
    });

    test('drops leading and trailing dots and spaces', () {
      expect(safeShareName('  .hidden song. '), 'hidden song');
    });

    test('never comes out empty', () {
      expect(safeShareName('...'), 'media');
      expect(safeShareName(''), 'media');
    });

    test('caps very long titles', () {
      expect(safeShareName('a' * 300).length, 120);
    });
  });
}
