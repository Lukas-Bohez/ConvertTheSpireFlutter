import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pl'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('uk'),
    Locale('vi'),
    Locale('zh')
  ];

  /// Navigation tab: search for media to download
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tabSearch;

  /// Navigation tab: multi-source search
  ///
  /// In en, this message translates to:
  /// **'Search+'**
  String get tabMultiSearch;

  /// Navigation tab: built-in web browser
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get tabBrowser;

  /// Navigation tab: download queue
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get tabQueue;

  /// Navigation tab: saved playlists
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get tabPlaylists;

  /// Navigation tab: bulk import
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get tabImport;

  /// Navigation tab: statistics
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get tabStats;

  /// Navigation tab: settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// Navigation tab: support the project
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get tabSupport;

  /// Navigation tab: file conversion
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get tabConvert;

  /// Navigation tab: activity logs
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get tabLogs;

  /// Navigation tab: user guide
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get tabGuide;

  /// Navigation tab: media player
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get tabPlayer;

  /// Navigation tab: home screen
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// Navigation tab: torrent client
  ///
  /// In en, this message translates to:
  /// **'Torrents'**
  String get tabTorrents;

  /// Download finished successfully
  ///
  /// In en, this message translates to:
  /// **'Download complete'**
  String get downloadComplete;

  /// Download ended with an error
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// Download was cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get downloadCancelled;

  /// Download in progress
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloading;

  /// Waiting in the download queue
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get queued;

  /// File conversion in progress
  ///
  /// In en, this message translates to:
  /// **'Converting'**
  String get converting;

  /// Playback or download is paused
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// Button: start a download
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get actionDownload;

  /// Button: cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// Button: try again
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// Button: delete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// Button: remove an item from a list
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// Button: pause
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// Button: resume
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// Button: play
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get actionPlay;

  /// Button: save
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// Button: open
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// Button: close
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// Button: clear a list or field
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// Button: refresh/reload
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// Button: add
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// Button: confirm and finish
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// Button: share
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get actionShare;

  /// Button: copy to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// Button: select every item
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get actionSelectAll;

  /// Player filter: all media
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get playerAll;

  /// Player filter: audio files
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get playerSongs;

  /// Player filter: video files
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get playerVideos;

  /// Player filter: favourited media
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get playerFavourites;

  /// Label above the current track
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get playerNowPlaying;

  /// Player control: shuffle order
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get playerShuffle;

  /// Player control: repeat
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get playerRepeat;

  /// Empty state for favourites
  ///
  /// In en, this message translates to:
  /// **'No favourites yet'**
  String get playerNoFavourites;

  /// Send playback to a TV or speaker
  ///
  /// In en, this message translates to:
  /// **'Cast to device'**
  String get castToDevice;

  /// Looking for cast targets
  ///
  /// In en, this message translates to:
  /// **'Scanning for devices…'**
  String get castScanning;

  /// No cast targets were found
  ///
  /// In en, this message translates to:
  /// **'No devices found'**
  String get castNoDevices;

  /// Stop casting
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get castDisconnect;

  /// Generic error label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// Generic loading label
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Affirmative answer
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// Negative answer
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// Acknowledge a message
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Placeholder text in a search box
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get commonSearchHint;

  /// Generic empty-list state
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonEmpty;

  /// Settings entry: app language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Language option: follow the device language
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'en',
        'es',
        'fr',
        'hi',
        'id',
        'it',
        'ja',
        'ko',
        'nl',
        'pl',
        'pt',
        'ru',
        'tr',
        'uk',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'nl':
      return AppLocalizationsNl();
    case 'pl':
      return AppLocalizationsPl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
    case 'uk':
      return AppLocalizationsUk();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
