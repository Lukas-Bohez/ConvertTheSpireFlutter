/// The languages the app ships, for the Settings language picker.
///
/// Each language is listed under its own name so somebody whose device is set
/// to a language they cannot read can still find theirs in the list.
class AppLanguage {
  /// Locale code stored in [AppSettings.language], or 'system'.
  final String code;

  /// The language's own name, e.g. 'Deutsch' for German.
  final String nativeName;

  /// English name, shown as a subtitle so the list stays scannable.
  final String englishName;

  const AppLanguage(this.code, this.nativeName, this.englishName);
}

/// 'system' first, then the 18 shipped locales in alphabetical order of code,
/// matching `AppLocalizations.supportedLocales`.
const List<AppLanguage> kAppLanguages = [
  AppLanguage('system', 'Automatic', 'Follow device language'),
  AppLanguage('ar', 'العربية', 'Arabic'),
  AppLanguage('de', 'Deutsch', 'German'),
  AppLanguage('en', 'English', 'English'),
  AppLanguage('es', 'Español', 'Spanish'),
  AppLanguage('fr', 'Français', 'French'),
  AppLanguage('hi', 'हिन्दी', 'Hindi'),
  AppLanguage('id', 'Bahasa Indonesia', 'Indonesian'),
  AppLanguage('it', 'Italiano', 'Italian'),
  AppLanguage('ja', '日本語', 'Japanese'),
  AppLanguage('ko', '한국어', 'Korean'),
  AppLanguage('nl', 'Nederlands', 'Dutch'),
  AppLanguage('pl', 'Polski', 'Polish'),
  AppLanguage('pt', 'Português', 'Portuguese'),
  AppLanguage('ru', 'Русский', 'Russian'),
  AppLanguage('tr', 'Türkçe', 'Turkish'),
  AppLanguage('uk', 'Українська', 'Ukrainian'),
  AppLanguage('vi', 'Tiếng Việt', 'Vietnamese'),
  AppLanguage('zh', '中文', 'Chinese'),
];

/// Looks up a stored language code, falling back to the 'system' entry for
/// anything we do not ship.
AppLanguage appLanguageFor(String? code) {
  for (final language in kAppLanguages) {
    if (language.code == code) return language;
  }
  return kAppLanguages.first;
}
