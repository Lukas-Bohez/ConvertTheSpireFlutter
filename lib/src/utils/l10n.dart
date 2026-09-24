import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

export '../../l10n/app_localizations.dart';

/// `context.l10n.someKey`: the app's text in the language picked in Settings
/// (or the device language).
///
/// Every string on screen goes through this. The translations lived in
/// `lib/l10n/` for months while the screens kept their English literals, so
/// choosing another language changed almost nothing.
extension L10nContext on BuildContext {
  /// Falls back to English where no [Localizations] sits above this context
  /// (the error screen can render outside MaterialApp, and widget tests pump
  /// bare MaterialApps) instead of throwing.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _english;
}

final AppLocalizations _english = lookupAppLocalizations(const Locale('en'));
