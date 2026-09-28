import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:convert_the_spire_reborn/src/config/app_locale.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const supported = AppLocalizations.supportedLocales;

  String resolve(List<Locale>? preferred) =>
      resolveAppLocale(preferred, supported).languageCode;

  test('a language the app ships is used', () {
    expect(resolve([const Locale('de', 'DE')]), 'de');
    expect(resolve([const Locale('pt', 'BR')]), 'pt');
    expect(resolve([const Locale('zh', 'TW')]), 'zh');
  });

  test('the first shipped language in the list wins', () {
    expect(resolve([const Locale('sv'), const Locale('nl')]), 'nl');
  });

  test('a language the app does not ship falls back to English, not Arabic',
      () {
    expect(supported.first.languageCode, 'ar');
    expect(resolve([const Locale('sv', 'SE')]), 'en');
    expect(resolve([const Locale('cs')]), 'en');
    expect(resolve(const []), 'en');
    expect(resolve(null), 'en');
  });
}
