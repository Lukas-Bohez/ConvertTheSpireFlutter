import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/constants/strings.dart';

void main() {
  group('Strings', () {
    test('appName is not empty', () {
      expect(Strings.appName, isNotEmpty);
    });

    test('tab names are non-empty strings', () {
      final tabNames = [
        Strings.tabSearch,
        Strings.tabMultiSearch,
        Strings.tabBrowser,
        Strings.tabQueue,
        Strings.tabPlaylists,
        Strings.tabImport,
        Strings.tabStats,
        Strings.tabSettings,
        Strings.tabSupport,
        Strings.tabConvert,
        Strings.tabLogs,
        Strings.tabGuide,
        Strings.tabPlayer,
        Strings.tabHome,
      ];
      for (final name in tabNames) {
        expect(name, isNotEmpty, reason: 'Tab name must not be empty');
      }
    });

    test('download status strings are defined', () {
      expect(Strings.downloadComplete, isNotEmpty);
      expect(Strings.downloadFailed, isNotEmpty);
      expect(Strings.downloadCancelled, isNotEmpty);
      expect(Strings.downloading, isNotEmpty);
    });

    test('error strings contain actionable guidance', () {
      expect(Strings.errorCookiesRequired, contains('cookies'));
    });
  });
}
