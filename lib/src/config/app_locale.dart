import 'package:flutter/widgets.dart';

/// The app's language for the device's [preferred] languages: the first one
/// the app ships, else English.
///
/// Flutter on its own falls back to the first supported locale, which is
/// Arabic (they are listed alphabetically): a device set to a language the
/// app does not ship, Swedish or Czech say, got the app in Arabic, right to
/// left.
Locale resolveAppLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  final english = supported.firstWhere((l) => l.languageCode == 'en',
      orElse: () => supported.first);
  if (preferred == null || preferred.isEmpty) return english;
  final resolved = basicLocaleListResolution(preferred, supported);
  final wanted = preferred.any((l) => l.languageCode == resolved.languageCode);
  return wanted ? resolved : english;
}
