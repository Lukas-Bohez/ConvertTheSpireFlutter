import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the translation files.
///
/// A locale that silently drifts out of sync with the English template shows
/// the user a blank or English string in the middle of a translated screen,
/// which looks worse than shipping no translation at all. These tests fail
/// the build instead.
void main() {
  final dir = Directory('lib/l10n');
  final arbFiles = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  Map<String, dynamic> read(File f) =>
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

  /// Translatable keys only - the @-prefixed entries are translator metadata.
  Set<String> keysOf(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  final template = read(File('lib/l10n/app_en.arb'));
  final templateKeys = keysOf(template);

  test('the English template is not empty', () {
    expect(templateKeys, isNotEmpty);
  });

  test('every shipped locale has an .arb file', () {
    // supportedLocales is generated from the .arb files, so a mismatch means
    // a file was added or removed without regenerating.
    final fromFiles = arbFiles
        .map((f) => f.uri.pathSegments.last
            .replaceFirst('app_', '')
            .replaceFirst('.arb', ''))
        .toSet();
    final fromCode =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(fromCode, fromFiles,
        reason: 'run `flutter gen-l10n` after adding or removing an .arb file');
  });

  for (final file in arbFiles) {
    final name = file.uri.pathSegments.last;
    if (name == 'app_en.arb') continue;

    group(name, () {
      final arb = read(file);
      final keys = keysOf(arb);

      test('translates every key in the English template', () {
        expect(keys.difference(templateKeys), isEmpty,
            reason: '$name has keys that do not exist in app_en.arb');
        expect(templateKeys.difference(keys), isEmpty,
            reason: '$name is missing translations');
      });

      test('declares its own locale', () {
        final expected = name.replaceFirst('app_', '').replaceFirst('.arb', '');
        expect(arb['@@locale'], expected);
      });

      test('has no blank or untranslated-placeholder values', () {
        for (final key in keys) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$key is not a string');
          expect((value as String).trim(), isNotEmpty,
              reason: '$key is blank in $name');
          expect(value.contains('TODO'), isFalse,
              reason: '$key still has a TODO marker in $name');
        }
      });
    });
  }

  group('lookup', () {
    test('returns the translated string for a supported locale', () async {
      final es = await AppLocalizations.delegate.load(const Locale('es'));
      expect(es.tabSettings, 'Ajustes');
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.tabSettings, '設定');
    });

    test('English is the template locale', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(en.tabSettings, 'Settings');
    });

    test('ships a meaningful number of languages', () {
      expect(AppLocalizations.supportedLocales.length, greaterThanOrEqualTo(15));
    });
  });
}
