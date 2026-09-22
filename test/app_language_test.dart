import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:convert_the_spire_reborn/src/models/app_languages.dart';
import 'package:convert_the_spire_reborn/src/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Settings language picker.
///
/// The app shipped 18 translations that were unreachable: it followed the
/// device language and offered no setting (issue #7). These tests keep the
/// picker in step with the locales we actually ship, and keep the choice
/// surviving a save/load round trip.
void main() {
  group('kAppLanguages', () {
    test('offers every shipped locale, and nothing we do not ship', () {
      final offered = kAppLanguages
          .map((l) => l.code)
          .where((code) => code != 'system')
          .toSet();
      final shipped =
          AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();

      expect(offered, shipped,
          reason: 'Add the new locale to kAppLanguages, under its own name, '
              'or it is unreachable from Settings.');
    });

    test('starts with the automatic entry and has no duplicates', () {
      expect(kAppLanguages.first.code, 'system');

      final codes = kAppLanguages.map((l) => l.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('every entry has a native and an English name', () {
      for (final language in kAppLanguages) {
        expect(language.nativeName, isNotEmpty, reason: language.code);
        expect(language.englishName, isNotEmpty, reason: language.code);
      }
    });
  });

  group('appLanguageFor', () {
    test('finds a shipped language', () {
      expect(appLanguageFor('de').nativeName, 'Deutsch');
    });

    test('falls back to automatic for unknown, empty and null codes', () {
      expect(appLanguageFor('kl').code, 'system');
      expect(appLanguageFor('').code, 'system');
      expect(appLanguageFor(null).code, 'system');
    });
  });

  group('AppSettings.language', () {
    test('defaults to following the device language', () {
      expect(AppSettings.defaults(downloadDir: '/tmp/downloads').language,
          'system');
    });

    test('survives a JSON round trip', () {
      final saved = AppSettings.defaults(downloadDir: '/tmp/downloads')
          .copyWith(language: 'pt');

      expect(
          AppSettings.fromJson(saved.toJson(),
                  fallbackDownloadDir: '/tmp/downloads')
              .language,
          'pt');
    });

    test('an older settings file without the key reads as automatic', () {
      final json = AppSettings.defaults(downloadDir: '/tmp/downloads').toJson()
        ..remove('language');

      expect(
          AppSettings.fromJson(json, fallbackDownloadDir: '/tmp/downloads')
              .language,
          'system');
    });
  });
}
