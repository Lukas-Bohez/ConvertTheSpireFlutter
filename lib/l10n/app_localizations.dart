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

  /// No description provided for @tabFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get tabFiles;

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

  /// No description provided for @colourPullSession.
  ///
  /// In en, this message translates to:
  /// **'Colour pull session'**
  String get colourPullSession;

  /// No description provided for @oneYoursPressNextContinue.
  ///
  /// In en, this message translates to:
  /// **'That one is yours. Press Next to continue.'**
  String get oneYoursPressNextContinue;

  /// No description provided for @pressNextStepThroughNear.
  ///
  /// In en, this message translates to:
  /// **'Press Next to step through the near-miss pull.'**
  String get pressNextStepThroughNear;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @allColoursPulled.
  ///
  /// In en, this message translates to:
  /// **'All colours pulled'**
  String get allColoursPulled;

  /// No description provided for @everythingDroppedTimePoppingOne.
  ///
  /// In en, this message translates to:
  /// **'Everything that dropped this time, popping in one by one.'**
  String get everythingDroppedTimePoppingOne;

  /// No description provided for @claim.
  ///
  /// In en, this message translates to:
  /// **'Claim'**
  String get claim;

  /// No description provided for @watchAdUnlockColour.
  ///
  /// In en, this message translates to:
  /// **'Watch an ad → unlock a colour'**
  String get watchAdUnlockColour;

  /// No description provided for @myCollection.
  ///
  /// In en, this message translates to:
  /// **'My collection'**
  String get myCollection;

  /// No description provided for @mythic.
  ///
  /// In en, this message translates to:
  /// **'Mythic'**
  String get mythic;

  /// No description provided for @legendary.
  ///
  /// In en, this message translates to:
  /// **'Legendary'**
  String get legendary;

  /// No description provided for @epic.
  ///
  /// In en, this message translates to:
  /// **'Epic'**
  String get epic;

  /// No description provided for @rare.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get rare;

  /// No description provided for @uncommon.
  ///
  /// In en, this message translates to:
  /// **'Uncommon'**
  String get uncommon;

  /// No description provided for @common.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get common;

  /// No description provided for @allColoursUnlocked.
  ///
  /// In en, this message translates to:
  /// **'All colours unlocked!'**
  String get allColoursUnlocked;

  /// No description provided for @unlockAll28Colours.
  ///
  /// In en, this message translates to:
  /// **'Unlock All 28 Colours'**
  String get unlockAll28Colours;

  /// No description provided for @oneTimePurchaseNoAds.
  ///
  /// In en, this message translates to:
  /// **'One-time purchase · No ads needed'**
  String get oneTimePurchaseNoAds;

  /// No description provided for @seePriceStore.
  ///
  /// In en, this message translates to:
  /// **'See price in store'**
  String get seePriceStore;

  /// No description provided for @spinColour.
  ///
  /// In en, this message translates to:
  /// **'Spin for Colour'**
  String get spinColour;

  /// No description provided for @watchAd.
  ///
  /// In en, this message translates to:
  /// **'Watch Ad'**
  String get watchAd;

  /// No description provided for @browserSettings.
  ///
  /// In en, this message translates to:
  /// **'Browser Settings'**
  String get browserSettings;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @searchEngine.
  ///
  /// In en, this message translates to:
  /// **'Search Engine'**
  String get searchEngine;

  /// No description provided for @extensions.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get extensions;

  /// No description provided for @chromeExtensionsAddonsMozillaOrg.
  ///
  /// In en, this message translates to:
  /// **'Chrome extensions and addons.mozilla.org add-ons'**
  String get chromeExtensionsAddonsMozillaOrg;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @adBlocker.
  ///
  /// In en, this message translates to:
  /// **'Ad Blocker'**
  String get adBlocker;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @blockPopUps.
  ///
  /// In en, this message translates to:
  /// **'Block Pop-ups'**
  String get blockPopUps;

  /// No description provided for @doNotTrack.
  ///
  /// In en, this message translates to:
  /// **'Do Not Track'**
  String get doNotTrack;

  /// No description provided for @updateBlocklist.
  ///
  /// In en, this message translates to:
  /// **'Update Blocklist'**
  String get updateBlocklist;

  /// No description provided for @reDownloadEasylistRules.
  ///
  /// In en, this message translates to:
  /// **'Re-download EasyList rules'**
  String get reDownloadEasylistRules;

  /// No description provided for @blocklistUpdated.
  ///
  /// In en, this message translates to:
  /// **'Blocklist updated'**
  String get blocklistUpdated;

  /// No description provided for @clearBrowsingData.
  ///
  /// In en, this message translates to:
  /// **'Clear Browsing Data'**
  String get clearBrowsingData;

  /// No description provided for @ipfsGateway.
  ///
  /// In en, this message translates to:
  /// **'IPFS Gateway'**
  String get ipfsGateway;

  /// No description provided for @defaultGatewayChain.
  ///
  /// In en, this message translates to:
  /// **'Default gateway chain'**
  String get defaultGatewayChain;

  /// No description provided for @display.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// No description provided for @desktopMode.
  ///
  /// In en, this message translates to:
  /// **'Desktop Mode'**
  String get desktopMode;

  /// No description provided for @requestDesktopVersionWebsites.
  ///
  /// In en, this message translates to:
  /// **'Request desktop version of websites'**
  String get requestDesktopVersionWebsites;

  /// No description provided for @customGatewayUrl.
  ///
  /// In en, this message translates to:
  /// **'Custom gateway URL'**
  String get customGatewayUrl;

  /// No description provided for @leaveEmptyUseBuiltPublic.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the built-in public gateways.'**
  String get leaveEmptyUseBuiltPublic;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @ipfsGatewayUpdated.
  ///
  /// In en, this message translates to:
  /// **'IPFS gateway updated'**
  String get ipfsGatewayUpdated;

  /// No description provided for @willClearBrowsingHistoryRecent.
  ///
  /// In en, this message translates to:
  /// **'This will clear your browsing history and recent sites. Favourites will not be affected.'**
  String get willClearBrowsingHistoryRecent;

  /// No description provided for @browsingDataCleared.
  ///
  /// In en, this message translates to:
  /// **'Browsing data cleared'**
  String get browsingDataCleared;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @adBlockerActive.
  ///
  /// In en, this message translates to:
  /// **'Ad blocker active'**
  String get adBlockerActive;

  /// No description provided for @desktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get desktop;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @removeFromFavourites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get removeFromFavourites;

  /// No description provided for @addFavourites.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get addFavourites;

  /// No description provided for @tabs.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get tabs;

  /// No description provided for @manageExtensions.
  ///
  /// In en, this message translates to:
  /// **'Manage extensions'**
  String get manageExtensions;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @openBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get openBrowser;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @addCookiesDownloads.
  ///
  /// In en, this message translates to:
  /// **'Add cookies (for downloads)'**
  String get addCookiesDownloads;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @userscripts.
  ///
  /// In en, this message translates to:
  /// **'Userscripts'**
  String get userscripts;

  /// No description provided for @clearBrowsingData2.
  ///
  /// In en, this message translates to:
  /// **'Clear browsing data'**
  String get clearBrowsingData2;

  /// No description provided for @castMedia.
  ///
  /// In en, this message translates to:
  /// **'Cast Media'**
  String get castMedia;

  /// No description provided for @noVideoStreamsDetected.
  ///
  /// In en, this message translates to:
  /// **'No video streams detected'**
  String get noVideoStreamsDetected;

  /// No description provided for @detectedVideos.
  ///
  /// In en, this message translates to:
  /// **'Detected Videos'**
  String get detectedVideos;

  /// No description provided for @castDevices.
  ///
  /// In en, this message translates to:
  /// **'Cast Devices'**
  String get castDevices;

  /// No description provided for @searchingDevices.
  ///
  /// In en, this message translates to:
  /// **'Searching for devices…'**
  String get searchingDevices;

  /// No description provided for @chromecast.
  ///
  /// In en, this message translates to:
  /// **'Chromecast'**
  String get chromecast;

  /// No description provided for @dlnaUpnp.
  ///
  /// In en, this message translates to:
  /// **'DLNA / UPnP'**
  String get dlnaUpnp;

  /// No description provided for @castSelectedVideo.
  ///
  /// In en, this message translates to:
  /// **'Cast Selected Video'**
  String get castSelectedVideo;

  /// No description provided for @casting.
  ///
  /// In en, this message translates to:
  /// **'Casting to {deviceName}'**
  String casting(Object deviceName);

  /// No description provided for @playing.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get playing;

  /// No description provided for @chooseExtensionPackage.
  ///
  /// In en, this message translates to:
  /// **'Choose an extension package'**
  String get chooseExtensionPackage;

  /// No description provided for @chooseUnpackedExtensionFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose an unpacked extension folder'**
  String get chooseUnpackedExtensionFolder;

  /// No description provided for @installed.
  ///
  /// In en, this message translates to:
  /// **'{installedName} is installed'**
  String installed(Object installedName);

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add {name}?'**
  String add(Object name);

  /// No description provided for @asksNoSpecialPermissions.
  ///
  /// In en, this message translates to:
  /// **'It asks for no special permissions.'**
  String get asksNoSpecialPermissions;

  /// No description provided for @willAble.
  ///
  /// In en, this message translates to:
  /// **'It will be able to:'**
  String get willAble;

  /// No description provided for @addExtension.
  ///
  /// In en, this message translates to:
  /// **'Add extension'**
  String get addExtension;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove {extensionName}?'**
  String remove(Object extensionName);

  /// No description provided for @itsSettingsDeletedTooCan.
  ///
  /// In en, this message translates to:
  /// **'Its settings are deleted too. You can install it again later.'**
  String get itsSettingsDeletedTooCan;

  /// No description provided for @installFromFileCrxZip.
  ///
  /// In en, this message translates to:
  /// **'Install from a file (.crx, .zip, .xpi)'**
  String get installFromFileCrxZip;

  /// No description provided for @installUnpackedFolder.
  ///
  /// In en, this message translates to:
  /// **'Install an unpacked folder'**
  String get installUnpackedFolder;

  /// No description provided for @installed2.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installed2;

  /// No description provided for @getExtensions.
  ///
  /// In en, this message translates to:
  /// **'Get extensions'**
  String get getExtensions;

  /// No description provided for @extensionsNotAvailableHere.
  ///
  /// In en, this message translates to:
  /// **'Extensions are not available here.'**
  String get extensionsNotAvailableHere;

  /// No description provided for @noExtensionsYetFindOne.
  ///
  /// In en, this message translates to:
  /// **'No extensions yet.\n\nFind one under Get extensions, or install a .crx, .zip or .xpi file with the buttons at the top. Chrome extensions and cross-browser Firefox extensions both work here.'**
  String get noExtensionsYetFindOne;

  /// No description provided for @itsToolbarButtonRunsBackground.
  ///
  /// In en, this message translates to:
  /// **'Its toolbar button runs a background action that WebView2 cannot trigger, so it has no popup here.'**
  String get itsToolbarButtonRunsBackground;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @searchAddonsMozillaOrg.
  ///
  /// In en, this message translates to:
  /// **'Search addons.mozilla.org'**
  String get searchAddonsMozillaOrg;

  /// No description provided for @nothingFoundTryAnotherSearch.
  ///
  /// In en, this message translates to:
  /// **'Nothing found. Try another search.'**
  String get nothingFoundTryAnotherSearch;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @recommendedByMozilla.
  ///
  /// In en, this message translates to:
  /// **'Recommended by Mozilla'**
  String get recommendedByMozilla;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @searchFavourites.
  ///
  /// In en, this message translates to:
  /// **'Search favourites'**
  String get searchFavourites;

  /// No description provided for @addPagesFavouritesUsingStar.
  ///
  /// In en, this message translates to:
  /// **'Add pages to your favourites using the star icon'**
  String get addPagesFavouritesUsingStar;

  /// No description provided for @addFavourite.
  ///
  /// In en, this message translates to:
  /// **'Add Favourite'**
  String get addFavourite;

  /// No description provided for @titleOptional.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get titleOptional;

  /// No description provided for @editFavourite.
  ///
  /// In en, this message translates to:
  /// **'Edit Favourite'**
  String get editFavourite;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @folder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folder;

  /// No description provided for @clearAllHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear all history'**
  String get clearAllHistory;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history?'**
  String get clearHistory;

  /// No description provided for @allBrowsingHistoryWillDeleted.
  ///
  /// In en, this message translates to:
  /// **'All browsing history will be deleted.'**
  String get allBrowsingHistoryWillDeleted;

  /// No description provided for @lastHour.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get lastHour;

  /// No description provided for @last24Hours.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get last24Hours;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search history…'**
  String get searchHistory;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No history'**
  String get noHistory;

  /// No description provided for @browsingHistoryWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Your browsing history will appear here'**
  String get browsingHistoryWillAppearHere;

  /// No description provided for @clearBrowsingHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear browsing history for {range}?'**
  String clearBrowsingHistory(Object range);

  /// No description provided for @chromeFirefoxExtensionsNeedDesktop.
  ///
  /// In en, this message translates to:
  /// **'Chrome and Firefox extensions need a desktop browser engine, and the web view on this device cannot load them. What most people install extensions for works here anyway: ad blocking is built in, and userscripts add dark mode, YouTube tweaks and much more.'**
  String get chromeFirefoxExtensionsNeedDesktop;

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get device;

  /// No description provided for @adTrackerBlocking.
  ///
  /// In en, this message translates to:
  /// **'Ad and tracker blocking'**
  String get adTrackerBlocking;

  /// No description provided for @builtNothingInstall.
  ///
  /// In en, this message translates to:
  /// **'Built in, nothing to install'**
  String get builtNothingInstall;

  /// No description provided for @tampermonkeyCompatibleNoneInstalledYet.
  ///
  /// In en, this message translates to:
  /// **'Tampermonkey-compatible. None installed yet'**
  String get tampermonkeyCompatibleNoneInstalledYet;

  /// No description provided for @switched.
  ///
  /// In en, this message translates to:
  /// **'{enabledCount} of {scriptsCount} switched on'**
  String switched(Object enabledCount, Object scriptsCount);

  /// No description provided for @findAddOns.
  ///
  /// In en, this message translates to:
  /// **'Find add-ons'**
  String get findAddOns;

  /// No description provided for @searchUserscripts.
  ///
  /// In en, this message translates to:
  /// **'Search userscripts'**
  String get searchUserscripts;

  /// No description provided for @siteWhatWantChange.
  ///
  /// In en, this message translates to:
  /// **'A site or what you want to change'**
  String get siteWhatWantChange;

  /// No description provided for @theseOpenGreasyForkBrowser.
  ///
  /// In en, this message translates to:
  /// **'These open Greasy Fork in the browser. On a script’s page, tap Install: the app shows where the script comes from and asks before installing it. A userscript can read and change the sites it runs on, so install only ones you trust.'**
  String get theseOpenGreasyForkBrowser;

  /// No description provided for @fullExtensions.
  ///
  /// In en, this message translates to:
  /// **'Full extensions'**
  String get fullExtensions;

  /// No description provided for @windowsAppRunsChromeExtensions.
  ///
  /// In en, this message translates to:
  /// **'The Windows app runs Chrome extensions and add-ons from addons.mozilla.org, such as uBlock Origin Lite and Dark Reader, with their buttons and settings pages.'**
  String get windowsAppRunsChromeExtensions;

  /// No description provided for @searchEnterUrl.
  ///
  /// In en, this message translates to:
  /// **'Search or enter URL'**
  String get searchEnterUrl;

  /// No description provided for @go.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get go;

  /// No description provided for @quickAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick Access'**
  String get quickAccess;

  /// No description provided for @suggestedSites.
  ///
  /// In en, this message translates to:
  /// **'Suggested Sites'**
  String get suggestedSites;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @installFromUrl.
  ///
  /// In en, this message translates to:
  /// **'Install from URL'**
  String get installFromUrl;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @scriptInstalled.
  ///
  /// In en, this message translates to:
  /// **'Script installed'**
  String get scriptInstalled;

  /// No description provided for @pasteScript.
  ///
  /// In en, this message translates to:
  /// **'Paste a script'**
  String get pasteScript;

  /// No description provided for @userscriptNameMyScript.
  ///
  /// In en, this message translates to:
  /// **'// ==UserScript==\n// @name  My script\n…'**
  String get userscriptNameMyScript;

  /// No description provided for @notUserscriptNeedsUserscriptHeader.
  ///
  /// In en, this message translates to:
  /// **'That is not a userscript — it needs a // ==UserScript== header.'**
  String get notUserscriptNeedsUserscriptHeader;

  /// No description provided for @installed3.
  ///
  /// In en, this message translates to:
  /// **'Installed \"{installedName}\"'**
  String installed3(Object installedName);

  /// No description provided for @remove2.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{scriptName}\"?'**
  String remove2(Object scriptName);

  /// No description provided for @scriptWillDeletedFromDevice.
  ///
  /// In en, this message translates to:
  /// **'The script will be deleted from this device.'**
  String get scriptWillDeletedFromDevice;

  /// No description provided for @updateAll.
  ///
  /// In en, this message translates to:
  /// **'Update all'**
  String get updateAll;

  /// No description provided for @nothingUpdate.
  ///
  /// In en, this message translates to:
  /// **'Nothing to update'**
  String get nothingUpdate;

  /// No description provided for @updatedScriptS.
  ///
  /// In en, this message translates to:
  /// **'Updated {n} script(s)'**
  String updatedScriptS(Object n);

  /// No description provided for @runUserscripts.
  ///
  /// In en, this message translates to:
  /// **'Run userscripts'**
  String get runUserscripts;

  /// No description provided for @nothingInstalledYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing installed yet'**
  String get nothingInstalledYet;

  /// No description provided for @noSitesConfiguredWillNever.
  ///
  /// In en, this message translates to:
  /// **'No sites configured — this will never run'**
  String get noSitesConfiguredWillNever;

  /// No description provided for @addScript.
  ///
  /// In en, this message translates to:
  /// **'Add script'**
  String get addScript;

  /// No description provided for @pasteLinkUserJsFile.
  ///
  /// In en, this message translates to:
  /// **'Paste a link to a .user.js file'**
  String get pasteLinkUserJsFile;

  /// No description provided for @pasteScript2.
  ///
  /// In en, this message translates to:
  /// **'Paste the script'**
  String get pasteScript2;

  /// No description provided for @copyCodeStraight.
  ///
  /// In en, this message translates to:
  /// **'Copy the code straight in'**
  String get copyCodeStraight;

  /// No description provided for @noUserscriptsYet.
  ///
  /// In en, this message translates to:
  /// **'No userscripts yet'**
  String get noUserscriptsYet;

  /// No description provided for @userscriptsChangeHowWebsitesLook.
  ///
  /// In en, this message translates to:
  /// **'Userscripts change how websites look and behave. Most scripts written for Tampermonkey or Greasemonkey work here unchanged — find them on sites like Greasy Fork and install by URL.'**
  String get userscriptsChangeHowWebsitesLook;

  /// No description provided for @openAnotherApp.
  ///
  /// In en, this message translates to:
  /// **'Open in another app?'**
  String get openAnotherApp;

  /// No description provided for @linkOpensOutsideBrowser.
  ///
  /// In en, this message translates to:
  /// **'This link opens {target} outside the browser.'**
  String linkOpensOutsideBrowser(Object target);

  /// No description provided for @stayHere.
  ///
  /// In en, this message translates to:
  /// **'Stay here'**
  String get stayHere;

  /// No description provided for @installUserscript.
  ///
  /// In en, this message translates to:
  /// **'Install userscript?'**
  String get installUserscript;

  /// No description provided for @userscriptsRunFullAccessPages.
  ///
  /// In en, this message translates to:
  /// **'Userscripts run with full access to the pages they match. Only install scripts from a source you trust.'**
  String get userscriptsRunFullAccessPages;

  /// No description provided for @userscriptInstalled.
  ///
  /// In en, this message translates to:
  /// **'Userscript installed'**
  String get userscriptInstalled;

  /// No description provided for @typeHere.
  ///
  /// In en, this message translates to:
  /// **'Type here...'**
  String get typeHere;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @removedFromFavourites.
  ///
  /// In en, this message translates to:
  /// **'Removed from favourites'**
  String get removedFromFavourites;

  /// No description provided for @addedFavourites.
  ///
  /// In en, this message translates to:
  /// **'Added to favourites'**
  String get addedFavourites;

  /// No description provided for @youtubeDownloadsNotPartPlay.
  ///
  /// In en, this message translates to:
  /// **'YouTube downloads are not part of the Play Store version.'**
  String get youtubeDownloadsNotPartPlay;

  /// No description provided for @addedQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get addedQueue;

  /// No description provided for @extractDownload.
  ///
  /// In en, this message translates to:
  /// **'Extract & Download'**
  String get extractDownload;

  /// No description provided for @appBrowserNotAvailablePlatform.
  ///
  /// In en, this message translates to:
  /// **'In-app browser is not available on this platform.\nUse the button below to open in your default browser.'**
  String get appBrowserNotAvailablePlatform;

  /// No description provided for @openExternalBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in External Browser'**
  String get openExternalBrowser;

  /// No description provided for @findPage.
  ///
  /// In en, this message translates to:
  /// **'Find in page'**
  String get findPage;

  /// No description provided for @findNext.
  ///
  /// In en, this message translates to:
  /// **'Find next'**
  String get findNext;

  /// No description provided for @linkCopiedClipboard.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedClipboard;

  /// No description provided for @browserDataCleared.
  ///
  /// In en, this message translates to:
  /// **'Browser data cleared'**
  String get browserDataCleared;

  /// No description provided for @couldNotClearBrowserData.
  ///
  /// In en, this message translates to:
  /// **'Could not clear browser data'**
  String get couldNotClearBrowserData;

  /// No description provided for @browsingHistoryQuickLinksCleared.
  ///
  /// In en, this message translates to:
  /// **'Browsing history and quick links cleared'**
  String get browsingHistoryQuickLinksCleared;

  /// No description provided for @tabs2.
  ///
  /// In en, this message translates to:
  /// **'Tabs ({tabCount})'**
  String tabs2(Object tabCount);

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get closeTab;

  /// No description provided for @pasteTrackListHereFormat.
  ///
  /// In en, this message translates to:
  /// **'Paste track list here\nFormat: Artist - Song'**
  String get pasteTrackListHereFormat;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format: '**
  String get format;

  /// No description provided for @importFromText.
  ///
  /// In en, this message translates to:
  /// **'Import from Text'**
  String get importFromText;

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import from File'**
  String get importFromFile;

  /// No description provided for @parsedTracks.
  ///
  /// In en, this message translates to:
  /// **'Parsed {parsedQueries} tracks'**
  String parsedTracks(Object parsedQueries);

  /// No description provided for @showOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Show onboarding'**
  String get showOnboarding;

  /// No description provided for @supportedPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Supported Platforms'**
  String get supportedPlatforms;

  /// No description provided for @downloadsConversionNotificationsFileConv.
  ///
  /// In en, this message translates to:
  /// **'Downloads, conversion, notifications, file converter'**
  String get downloadsConversionNotificationsFileConv;

  /// No description provided for @downloadsConversionNotificationsSafFolde.
  ///
  /// In en, this message translates to:
  /// **'Downloads, conversion, notifications, SAF folder picker'**
  String get downloadsConversionNotificationsSafFolde;

  /// No description provided for @officialLinuxBuildsEndedV14.
  ///
  /// In en, this message translates to:
  /// **'Official Linux builds ended with v14.0.0'**
  String get officialLinuxBuildsEndedV14;

  /// No description provided for @mayWorkButNotOfficially.
  ///
  /// In en, this message translates to:
  /// **'May work but not officially supported'**
  String get mayWorkButNotOfficially;

  /// No description provided for @cannotDownloadRunFfmpegBrowser.
  ///
  /// In en, this message translates to:
  /// **'Cannot download or run FFmpeg in a browser'**
  String get cannotDownloadRunFfmpegBrowser;

  /// No description provided for @requirements.
  ///
  /// In en, this message translates to:
  /// **'Requirements'**
  String get requirements;

  /// No description provided for @ffmpeg.
  ///
  /// In en, this message translates to:
  /// **'FFmpeg'**
  String get ffmpeg;

  /// No description provided for @requiredAudioConversionWindowsInstalled.
  ///
  /// In en, this message translates to:
  /// **'Required for audio conversion. On Windows it is installed automatically on first launch. On Linux, install via your package manager (e.g. sudo apt install ffmpeg).'**
  String get requiredAudioConversionWindowsInstalled;

  /// No description provided for @internetConnection.
  ///
  /// In en, this message translates to:
  /// **'Internet connection'**
  String get internetConnection;

  /// No description provided for @neededFetchTorrentMetadataDownload.
  ///
  /// In en, this message translates to:
  /// **'Needed to fetch torrent metadata and download sources.'**
  String get neededFetchTorrentMetadataDownload;

  /// No description provided for @storageSpace.
  ///
  /// In en, this message translates to:
  /// **'Storage space'**
  String get storageSpace;

  /// No description provided for @downloadedFilesSavedChosenDownload.
  ///
  /// In en, this message translates to:
  /// **'Downloaded files are saved to your chosen download folder. Videos can be large before conversion.'**
  String get downloadedFilesSavedChosenDownload;

  /// No description provided for @quickStart.
  ///
  /// In en, this message translates to:
  /// **'Quick Start'**
  String get quickStart;

  /// No description provided for @setDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Set download folder'**
  String get setDownloadFolder;

  /// No description provided for @goSettingsPickWhereFiles.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings and pick where files should be saved.'**
  String get goSettingsPickWhereFiles;

  /// No description provided for @browseOpenLinks.
  ///
  /// In en, this message translates to:
  /// **'Browse & open links'**
  String get browseOpenLinks;

  /// No description provided for @useBrowserTabOpenPages.
  ///
  /// In en, this message translates to:
  /// **'Use the Browser tab to open pages, magnet links, and .torrent links safely inside the app.'**
  String get useBrowserTabOpenPages;

  /// No description provided for @addQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get addQueue;

  /// No description provided for @chooseDestinationAddItemsDownload.
  ///
  /// In en, this message translates to:
  /// **'Choose your destination and add items to the download queue.'**
  String get chooseDestinationAddItemsDownload;

  /// No description provided for @goTorrentsTabMonitorProgress.
  ///
  /// In en, this message translates to:
  /// **'Go to the Torrents tab to monitor progress, pause/resume, and manage completed files.'**
  String get goTorrentsTabMonitorProgress;

  /// No description provided for @goQueueTabPressDownload.
  ///
  /// In en, this message translates to:
  /// **'Go to the Queue tab and press \"Download All\". The app fetches the selected content and processes it with FFmpeg when needed.'**
  String get goQueueTabPressDownload;

  /// No description provided for @tabsExplained.
  ///
  /// In en, this message translates to:
  /// **'Tabs Explained'**
  String get tabsExplained;

  /// No description provided for @browsePagesOpenMagnetTorrent.
  ///
  /// In en, this message translates to:
  /// **'Browse pages and open magnet or torrent links in-app.'**
  String get browsePagesOpenMagnetTorrent;

  /// No description provided for @configureDownloadFolderAppearanceApp.
  ///
  /// In en, this message translates to:
  /// **'Configure download folder, appearance, and app behavior.'**
  String get configureDownloadFolderAppearanceApp;

  /// No description provided for @supportLinksProjectInformation.
  ///
  /// In en, this message translates to:
  /// **'Support links and project information.'**
  String get supportLinksProjectInformation;

  /// No description provided for @instructionsSupportedPlatformsTips.
  ///
  /// In en, this message translates to:
  /// **'Instructions, supported platforms, and tips.'**
  String get instructionsSupportedPlatformsTips;

  /// No description provided for @builtMediaPlayerLocalFiles.
  ///
  /// In en, this message translates to:
  /// **'Built-in media player for local files with shuffle and repeat.'**
  String get builtMediaPlayerLocalFiles;

  /// No description provided for @torrentManagerDownloadControlCenter.
  ///
  /// In en, this message translates to:
  /// **'Torrent manager and download control center.'**
  String get torrentManagerDownloadControlCenter;

  /// No description provided for @searchByKeywordPasteMagnet.
  ///
  /// In en, this message translates to:
  /// **'Search by keyword or paste a magnet / torrent link. Preview results and add them to the queue.'**
  String get searchByKeywordPasteMagnet;

  /// No description provided for @searchAcrossMultipleSourcesOnce.
  ///
  /// In en, this message translates to:
  /// **'Search across multiple sources at once and compare results side by side.'**
  String get searchAcrossMultipleSourcesOnce;

  /// No description provided for @useIntegratedWebViewBrowse.
  ///
  /// In en, this message translates to:
  /// **'Use an integrated web view to browse supported sites and open magnet or torrent links directly.'**
  String get useIntegratedWebViewBrowse;

  /// No description provided for @viewManageDownloadsStartAll.
  ///
  /// In en, this message translates to:
  /// **'View and manage downloads. Start all, cancel, retry failed, or remove items.'**
  String get viewManageDownloadsStartAll;

  /// No description provided for @loadCollectionCompareAgainstLocal.
  ///
  /// In en, this message translates to:
  /// **'Load a collection, compare against a local folder to find missing items, and batch-download them.'**
  String get loadCollectionCompareAgainstLocal;

  /// No description provided for @pasteListLinksImportFrom.
  ///
  /// In en, this message translates to:
  /// **'Paste a list of links or import from a text/CSV file to add many items to the queue at once.'**
  String get pasteListLinksImportFrom;

  /// No description provided for @viewDownloadStatisticsTotalsSuccess.
  ///
  /// In en, this message translates to:
  /// **'View download statistics: totals, success rate, format breakdown, top artists, and trends over time.'**
  String get viewDownloadStatisticsTotalsSuccess;

  /// No description provided for @configureDownloadFoldersParallelWorkers.
  ///
  /// In en, this message translates to:
  /// **'Configure download folders, parallel workers, FFmpeg, retry behavior, and notifications.'**
  String get configureDownloadFoldersParallelWorkers;

  /// No description provided for @convertAnyLocalAudioVideo.
  ///
  /// In en, this message translates to:
  /// **'Convert any local audio/video file between formats using FFmpeg.'**
  String get convertAnyLocalAudioVideo;

  /// No description provided for @viewDetailedApplicationLogsDebugging.
  ///
  /// In en, this message translates to:
  /// **'View detailed application logs for debugging. Copy or clear the log history.'**
  String get viewDetailedApplicationLogsDebugging;

  /// No description provided for @screenInstructionsSupportedPlatformsTips.
  ///
  /// In en, this message translates to:
  /// **'This screen! Instructions, supported platforms, and tips.'**
  String get screenInstructionsSupportedPlatformsTips;

  /// No description provided for @builtMediaPlayerLocalFiles2.
  ///
  /// In en, this message translates to:
  /// **'Built‑in media player for your local files; control playback, shuffle, repeat and manage a library.'**
  String get builtMediaPlayerLocalFiles2;

  /// No description provided for @tipsTroubleshooting.
  ///
  /// In en, this message translates to:
  /// **'Tips & Troubleshooting'**
  String get tipsTroubleshooting;

  /// No description provided for @downloadsFail0.
  ///
  /// In en, this message translates to:
  /// **'Downloads fail at 0%'**
  String get downloadsFail0;

  /// No description provided for @usuallyMeansFfmpegMissingWindows.
  ///
  /// In en, this message translates to:
  /// **'This usually means FFmpeg is missing. On Windows the app installs it automatically; on Linux run: sudo apt install ffmpeg (or dnf install ffmpeg on Fedora).'**
  String get usuallyMeansFfmpegMissingWindows;

  /// No description provided for @sourceSitesBlockRequests.
  ///
  /// In en, this message translates to:
  /// **'Source sites block requests'**
  String get sourceSitesBlockRequests;

  /// No description provided for @someSourceSitesMayTemporarily.
  ///
  /// In en, this message translates to:
  /// **'Some source sites may temporarily block rapid requests. The app will automatically retry with backoff. You can increase retry count in Settings.'**
  String get someSourceSitesMayTemporarily;

  /// No description provided for @largeLibrariesSlow.
  ///
  /// In en, this message translates to:
  /// **'Large libraries are slow'**
  String get largeLibrariesSlow;

  /// No description provided for @whenLoadingLargeCollectionsUse.
  ///
  /// In en, this message translates to:
  /// **'When loading large collections, use the preview limit to load just 10-50 items first. You can always load more.'**
  String get whenLoadingLargeCollectionsUse;

  /// No description provided for @androidChooseWritableFolder.
  ///
  /// In en, this message translates to:
  /// **'Android: choose a writable folder'**
  String get androidChooseWritableFolder;

  /// No description provided for @androidMustPickDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'On Android you must pick a download folder through the system file picker so the app gets write permission.'**
  String get androidMustPickDownloadFolder;

  /// No description provided for @parallelWorkers.
  ///
  /// In en, this message translates to:
  /// **'Parallel workers'**
  String get parallelWorkers;

  /// No description provided for @moreWorkersMeansFasterBatch.
  ///
  /// In en, this message translates to:
  /// **'More workers means faster batch downloads but uses more bandwidth and may trigger rate limits. 2-3 is recommended.'**
  String get moreWorkersMeansFasterBatch;

  /// No description provided for @needRefresher.
  ///
  /// In en, this message translates to:
  /// **'Need a refresher?'**
  String get needRefresher;

  /// No description provided for @tapShowOnboardingTopScreen.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Show onboarding\" at the top of this screen to walk through every tab again.'**
  String get tapShowOnboardingTopScreen;

  /// No description provided for @supportedFormats.
  ///
  /// In en, this message translates to:
  /// **'Supported Formats'**
  String get supportedFormats;

  /// No description provided for @universalAudioFormatBestCompatibility.
  ///
  /// In en, this message translates to:
  /// **'Universal audio format. Best compatibility across all devices and players.'**
  String get universalAudioFormatBestCompatibility;

  /// No description provided for @aacAudioMp4ContainerBetter.
  ///
  /// In en, this message translates to:
  /// **'AAC audio in MP4 container. Better quality than MP3 at same bitrate. Works on Apple devices and modern players.'**
  String get aacAudioMp4ContainerBetter;

  /// No description provided for @videoAudioKeepsVideoTrack.
  ///
  /// In en, this message translates to:
  /// **'Video with audio. Keeps the video track intact when that is the selected target format.'**
  String get videoAudioKeepsVideoTrack;

  /// No description provided for @environment.
  ///
  /// In en, this message translates to:
  /// **'Your Environment'**
  String get environment;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @dartVersion.
  ///
  /// In en, this message translates to:
  /// **'Dart version'**
  String get dartVersion;

  /// No description provided for @couldNotOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Could not open the browser'**
  String get couldNotOpenBrowser;

  /// No description provided for @couldNotOpenBrowser2.
  ///
  /// In en, this message translates to:
  /// **'Could not open the browser: {e}'**
  String couldNotOpenBrowser2(Object e);

  /// No description provided for @appRefreshedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'App refreshed successfully'**
  String get appRefreshedSuccessfully;

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed: {e}'**
  String refreshFailed(Object e);

  /// No description provided for @folderAccessLost.
  ///
  /// In en, this message translates to:
  /// **'Folder access lost'**
  String get folderAccessLost;

  /// No description provided for @appCanNoLongerAccess.
  ///
  /// In en, this message translates to:
  /// **'The app can no longer access your selected download folder. Would you like to pick it again? Choosing \"No\" will use Downloads instead.'**
  String get appCanNoLongerAccess;

  /// No description provided for @useDownloads.
  ///
  /// In en, this message translates to:
  /// **'Use Downloads'**
  String get useDownloads;

  /// No description provided for @pickFolder.
  ///
  /// In en, this message translates to:
  /// **'Pick folder'**
  String get pickFolder;

  /// No description provided for @selectDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Select download folder'**
  String get selectDownloadFolder;

  /// No description provided for @downloadFolderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Download folder updated'**
  String get downloadFolderUpdated;

  /// No description provided for @magnetLinkAddedTorrents.
  ///
  /// In en, this message translates to:
  /// **'Magnet link added to torrents'**
  String get magnetLinkAddedTorrents;

  /// No description provided for @torrentFileAdded.
  ///
  /// In en, this message translates to:
  /// **'Torrent file added'**
  String get torrentFileAdded;

  /// No description provided for @torrentLinkAdded.
  ///
  /// In en, this message translates to:
  /// **'Torrent link added'**
  String get torrentLinkAdded;

  /// No description provided for @unsupportedTorrentLink.
  ///
  /// In en, this message translates to:
  /// **'Unsupported torrent link'**
  String get unsupportedTorrentLink;

  /// No description provided for @torrentAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Torrent already exists: {torrentId}'**
  String torrentAlreadyExists(Object torrentId);

  /// No description provided for @failedAddTorrent.
  ///
  /// In en, this message translates to:
  /// **'Failed to add torrent: {e}'**
  String failedAddTorrent(Object e);

  /// No description provided for @couldNotOpenBrowserSign.
  ///
  /// In en, this message translates to:
  /// **'Could not open browser sign-in.'**
  String get couldNotOpenBrowserSign;

  /// No description provided for @signSelectedBrowserThenSave.
  ///
  /// In en, this message translates to:
  /// **'Sign in in your selected browser, then save settings to enable age-restricted downloads.'**
  String get signSelectedBrowserThenSave;

  /// No description provided for @formatFolderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Format folder updated'**
  String get formatFolderUpdated;

  /// No description provided for @couldNotOpenSelectedFolder.
  ///
  /// In en, this message translates to:
  /// **'Could not open the selected folder.'**
  String get couldNotOpenSelectedFolder;

  /// No description provided for @youtubeUrl.
  ///
  /// In en, this message translates to:
  /// **'YouTube URL'**
  String get youtubeUrl;

  /// No description provided for @enterPasteYoutubeUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter or paste a YouTube URL'**
  String get enterPasteYoutubeUrl;

  /// No description provided for @clearUrl.
  ///
  /// In en, this message translates to:
  /// **'Clear URL'**
  String get clearUrl;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @youtubeConversionDisabledBuild.
  ///
  /// In en, this message translates to:
  /// **'YouTube conversion is disabled in this build.'**
  String get youtubeConversionDisabledBuild;

  /// No description provided for @downloadOptions.
  ///
  /// In en, this message translates to:
  /// **'Download Options'**
  String get downloadOptions;

  /// No description provided for @format2.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format2;

  /// No description provided for @mp4Video.
  ///
  /// In en, this message translates to:
  /// **'MP4 (Video)'**
  String get mp4Video;

  /// No description provided for @videoQuality.
  ///
  /// In en, this message translates to:
  /// **'Video Quality'**
  String get videoQuality;

  /// No description provided for @n720pHd.
  ///
  /// In en, this message translates to:
  /// **'720p (HD)'**
  String get n720pHd;

  /// No description provided for @n1080pFullHd.
  ///
  /// In en, this message translates to:
  /// **'1080p (Full HD)'**
  String get n1080pFullHd;

  /// No description provided for @bestAvailable.
  ///
  /// In en, this message translates to:
  /// **'Best Available'**
  String get bestAvailable;

  /// No description provided for @audioBitrate.
  ///
  /// In en, this message translates to:
  /// **'Audio Bitrate'**
  String get audioBitrate;

  /// No description provided for @n128Kbps.
  ///
  /// In en, this message translates to:
  /// **'128 kbps'**
  String get n128Kbps;

  /// No description provided for @n192Kbps.
  ///
  /// In en, this message translates to:
  /// **'192 kbps'**
  String get n192Kbps;

  /// No description provided for @n256Kbps.
  ///
  /// In en, this message translates to:
  /// **'256 kbps'**
  String get n256Kbps;

  /// No description provided for @n320Kbps.
  ///
  /// In en, this message translates to:
  /// **'320 kbps'**
  String get n320Kbps;

  /// No description provided for @expandPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Expand playlist'**
  String get expandPlaylist;

  /// No description provided for @showAllVideos.
  ///
  /// In en, this message translates to:
  /// **'Show all videos'**
  String get showAllVideos;

  /// No description provided for @playlistOptions.
  ///
  /// In en, this message translates to:
  /// **'Playlist Options'**
  String get playlistOptions;

  /// No description provided for @previewAmount.
  ///
  /// In en, this message translates to:
  /// **'Preview amount'**
  String get previewAmount;

  /// No description provided for @first10.
  ///
  /// In en, this message translates to:
  /// **'First 10'**
  String get first10;

  /// No description provided for @first25.
  ///
  /// In en, this message translates to:
  /// **'First 25'**
  String get first25;

  /// No description provided for @first50.
  ///
  /// In en, this message translates to:
  /// **'First 50'**
  String get first50;

  /// No description provided for @first100.
  ///
  /// In en, this message translates to:
  /// **'First 100'**
  String get first100;

  /// No description provided for @customRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range...'**
  String get customRange;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From #'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To #'**
  String get to;

  /// No description provided for @videoNumbers1BasedE.
  ///
  /// In en, this message translates to:
  /// **'Video numbers are 1-based (e.g. 1 to 25 = first 25 videos)'**
  String get videoNumbers1BasedE;

  /// No description provided for @youtubeMixPlaylistsIdsStarting.
  ///
  /// In en, this message translates to:
  /// **'YouTube Mix playlists (IDs starting with RD) cannot be expanded.'**
  String get youtubeMixPlaylistsIdsStarting;

  /// No description provided for @searchPreview.
  ///
  /// In en, this message translates to:
  /// **'Search / Preview'**
  String get searchPreview;

  /// No description provided for @loadingPreview.
  ///
  /// In en, this message translates to:
  /// **'Loading preview...'**
  String get loadingPreview;

  /// No description provided for @androidNeedsDownloadFolderSet.
  ///
  /// In en, this message translates to:
  /// **'Android needs a download folder set to work properly. Tap \"Choose folder\" below.'**
  String get androidNeedsDownloadFolderSet;

  /// No description provided for @goSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings'**
  String get goSettings;

  /// No description provided for @pleaseSelectDownloadFolderSettings.
  ///
  /// In en, this message translates to:
  /// **'Please select a download folder in Settings first.'**
  String get pleaseSelectDownloadFolderSettings;

  /// No description provided for @noPreviewResultsYet.
  ///
  /// In en, this message translates to:
  /// **'No preview results yet.'**
  String get noPreviewResultsYet;

  /// No description provided for @enterYoutubeUrlAboveClick.
  ///
  /// In en, this message translates to:
  /// **'Enter a YouTube URL above and click Search'**
  String get enterYoutubeUrlAboveClick;

  /// No description provided for @previewResults.
  ///
  /// In en, this message translates to:
  /// **'Preview Results ({itemsCount})'**
  String previewResults(Object itemsCount);

  /// No description provided for @addAll.
  ///
  /// In en, this message translates to:
  /// **'Add All'**
  String get addAll;

  /// No description provided for @addedItemsQueue.
  ///
  /// In en, this message translates to:
  /// **'Added {itemsCount} items to queue'**
  String addedItemsQueue(Object itemsCount);

  /// No description provided for @downloadAll.
  ///
  /// In en, this message translates to:
  /// **'Download All'**
  String get downloadAll;

  /// No description provided for @addRangeQueue.
  ///
  /// In en, this message translates to:
  /// **'Add range to queue'**
  String get addRangeQueue;

  /// No description provided for @from2.
  ///
  /// In en, this message translates to:
  /// **'From '**
  String get from2;

  /// No description provided for @add2.
  ///
  /// In en, this message translates to:
  /// **'Add {addRangeTo}'**
  String add2(Object addRangeTo);

  /// No description provided for @addedItemsQueue2.
  ///
  /// In en, this message translates to:
  /// **'Added {subsetCount} items to queue'**
  String addedItemsQueue2(Object subsetCount);

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download {addRangeTo}'**
  String download(Object addRangeTo);

  /// No description provided for @searchQueue.
  ///
  /// In en, this message translates to:
  /// **'Search Queue'**
  String get searchQueue;

  /// No description provided for @mediaPlayer.
  ///
  /// In en, this message translates to:
  /// **'Media Player'**
  String get mediaPlayer;

  /// No description provided for @noItemsQueue.
  ///
  /// In en, this message translates to:
  /// **'No items in queue'**
  String get noItemsQueue;

  /// No description provided for @addItemsFromPlayerTab.
  ///
  /// In en, this message translates to:
  /// **'Add items from the Player tab'**
  String get addItemsFromPlayerTab;

  /// No description provided for @addItemsFromSearchTab.
  ///
  /// In en, this message translates to:
  /// **'Add items from the Search tab'**
  String get addItemsFromSearchTab;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @previously.
  ///
  /// In en, this message translates to:
  /// **'Previously'**
  String get previously;

  /// No description provided for @noSongsUpNext.
  ///
  /// In en, this message translates to:
  /// **'No songs in Up next'**
  String get noSongsUpNext;

  /// No description provided for @noPreviouslyPlayedSongsYet.
  ///
  /// In en, this message translates to:
  /// **'No previously played songs yet'**
  String get noPreviouslyPlayedSongsYet;

  /// No description provided for @previouslyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Previously played'**
  String get previouslyPlayed;

  /// No description provided for @totalActiveDone.
  ///
  /// In en, this message translates to:
  /// **'{itemsCount} total • {inProgressCount} active • {completedCount} done'**
  String totalActiveDone(
      Object itemsCount, Object inProgressCount, Object completedCount);

  /// No description provided for @clearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue'**
  String get clearQueue;

  /// No description provided for @removeAllItemsFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove all items from the queue?'**
  String get removeAllItemsFromQueue;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed: {speed}'**
  String speed(Object speed);

  /// No description provided for @eta.
  ///
  /// In en, this message translates to:
  /// **'ETA: {eta}'**
  String eta(Object eta);

  /// No description provided for @playlistManager.
  ///
  /// In en, this message translates to:
  /// **'Playlist Manager'**
  String get playlistManager;

  /// No description provided for @watchedPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Watched Playlists'**
  String get watchedPlaylists;

  /// No description provided for @automaticDeviceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Automatic (device language)'**
  String get automaticDeviceLanguage;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// No description provided for @enjoyingConvertSpireReborn.
  ///
  /// In en, this message translates to:
  /// **'Enjoying Convert The Spire Reborn?'**
  String get enjoyingConvertSpireReborn;

  /// No description provided for @leaveReviewHelpsMoreThan.
  ///
  /// In en, this message translates to:
  /// **'Leave a review - it helps more than you think'**
  String get leaveReviewHelpsMoreThan;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @torrentStorage.
  ///
  /// In en, this message translates to:
  /// **'Torrent Storage'**
  String get torrentStorage;

  /// No description provided for @torrentFolder.
  ///
  /// In en, this message translates to:
  /// **'Torrent folder'**
  String get torrentFolder;

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// No description provided for @selectTorrentFolder.
  ///
  /// In en, this message translates to:
  /// **'Select torrent folder'**
  String get selectTorrentFolder;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @appTheme.
  ///
  /// In en, this message translates to:
  /// **'App Theme'**
  String get appTheme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @reportBug.
  ///
  /// In en, this message translates to:
  /// **'Report a bug'**
  String get reportBug;

  /// No description provided for @opensGithubVersionRecentLog.
  ///
  /// In en, this message translates to:
  /// **'Opens GitHub with your version and recent log filled in'**
  String get opensGithubVersionRecentLog;

  /// No description provided for @basicSettingsOnly.
  ///
  /// In en, this message translates to:
  /// **'Basic settings only'**
  String get basicSettingsOnly;

  /// No description provided for @versionOptimizedTorrentVaultFunctionalit.
  ///
  /// In en, this message translates to:
  /// **'This version is optimized for torrent vault functionality and complies with app store policies.'**
  String get versionOptimizedTorrentVaultFunctionalit;

  /// No description provided for @minimizeTrayClose.
  ///
  /// In en, this message translates to:
  /// **'Minimize to tray on close'**
  String get minimizeTrayClose;

  /// No description provided for @keepAppRunningBackgroundWhen.
  ///
  /// In en, this message translates to:
  /// **'Keep the app running in the background when you close the window.'**
  String get keepAppRunningBackgroundWhen;

  /// No description provided for @supportProject.
  ///
  /// In en, this message translates to:
  /// **'Support the Project'**
  String get supportProject;

  /// No description provided for @helpKeepAppOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Help keep this app open-source and ad-free by donating.'**
  String get helpKeepAppOpenSource;

  /// No description provided for @buyMeCoffee.
  ///
  /// In en, this message translates to:
  /// **'Buy Me a Coffee'**
  String get buyMeCoffee;

  /// No description provided for @couldNotOpenGithubSponsors.
  ///
  /// In en, this message translates to:
  /// **'Could not open GitHub Sponsors link.'**
  String get couldNotOpenGithubSponsors;

  /// No description provided for @githubSponsors.
  ///
  /// In en, this message translates to:
  /// **'GitHub Sponsors'**
  String get githubSponsors;

  /// No description provided for @downloadSettings.
  ///
  /// In en, this message translates to:
  /// **'Download Settings'**
  String get downloadSettings;

  /// No description provided for @downloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Download folder'**
  String get downloadFolder;

  /// No description provided for @pickFolderUsingAppFile.
  ///
  /// In en, this message translates to:
  /// **'Pick a folder using the in-app file browser. If not set, files go to Downloads/{getDefaultDownloadFolder}.'**
  String pickFolderUsingAppFile(Object getDefaultDownloadFolder);

  /// No description provided for @changeFolder.
  ///
  /// In en, this message translates to:
  /// **'Change folder'**
  String get changeFolder;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @noFolderSelectedDownloadsWill.
  ///
  /// In en, this message translates to:
  /// **'No folder selected. Downloads will be saved to Downloads/{getDefaultDownloadFolder}.'**
  String noFolderSelectedDownloadsWill(Object getDefaultDownloadFolder);

  /// No description provided for @usePerFormatSubFolders.
  ///
  /// In en, this message translates to:
  /// **'Use per-format sub-folders'**
  String get usePerFormatSubFolders;

  /// No description provided for @whenDisabledSelectedOutputFolder.
  ///
  /// In en, this message translates to:
  /// **'When disabled, the selected output folder is used directly (mp3/m4a/mp4 subfolders are skipped).'**
  String get whenDisabledSelectedOutputFolder;

  /// No description provided for @mp3FolderOptional.
  ///
  /// In en, this message translates to:
  /// **'MP3 folder (optional)'**
  String get mp3FolderOptional;

  /// No description provided for @m4aFolderOptional.
  ///
  /// In en, this message translates to:
  /// **'M4A folder (optional)'**
  String get m4aFolderOptional;

  /// No description provided for @mp4FolderOptional.
  ///
  /// In en, this message translates to:
  /// **'MP4 folder (optional)'**
  String get mp4FolderOptional;

  /// No description provided for @torrentFolderOptional.
  ///
  /// In en, this message translates to:
  /// **'Torrent folder (optional)'**
  String get torrentFolderOptional;

  /// No description provided for @whenSetVaultTorrentsUse.
  ///
  /// In en, this message translates to:
  /// **'When set, Vault torrents use this folder instead of the general download folder.'**
  String get whenSetVaultTorrentsUse;

  /// No description provided for @parallelWorkers110.
  ///
  /// In en, this message translates to:
  /// **'Parallel workers (1-10)'**
  String get parallelWorkers110;

  /// No description provided for @numberConcurrentDownloads.
  ///
  /// In en, this message translates to:
  /// **'Number of concurrent downloads'**
  String get numberConcurrentDownloads;

  /// No description provided for @showNotifications.
  ///
  /// In en, this message translates to:
  /// **'Show notifications'**
  String get showNotifications;

  /// No description provided for @displayNotificationsWhenDownloadsComplet.
  ///
  /// In en, this message translates to:
  /// **'Display notifications when downloads complete'**
  String get displayNotificationsWhenDownloadsComplet;

  /// No description provided for @qualitySettings.
  ///
  /// In en, this message translates to:
  /// **'Quality Settings'**
  String get qualitySettings;

  /// No description provided for @highResolutions1080p4k8k.
  ///
  /// In en, this message translates to:
  /// **'High resolutions (1080p+/4K/8K) download separate video + audio and merge using FFmpeg (requires yt-dlp).'**
  String get highResolutions1080p4k8k;

  /// No description provided for @higherBitrateBetterQualityLarger.
  ///
  /// In en, this message translates to:
  /// **'Higher bitrate = better quality, larger file size'**
  String get higherBitrateBetterQualityLarger;

  /// No description provided for @n128KbpsCompact.
  ///
  /// In en, this message translates to:
  /// **'128 kbps (Compact)'**
  String get n128KbpsCompact;

  /// No description provided for @n192KbpsStandard.
  ///
  /// In en, this message translates to:
  /// **'192 kbps (Standard)'**
  String get n192KbpsStandard;

  /// No description provided for @n256KbpsHigh.
  ///
  /// In en, this message translates to:
  /// **'256 kbps (High)'**
  String get n256KbpsHigh;

  /// No description provided for @n320KbpsMaximum.
  ///
  /// In en, this message translates to:
  /// **'320 kbps (Maximum)'**
  String get n320KbpsMaximum;

  /// No description provided for @highResolutions1080p4k8k2.
  ///
  /// In en, this message translates to:
  /// **'High resolutions (1080p+/4K/8K) merge separate video + audio streams (requires yt-dlp + FFmpeg)'**
  String get highResolutions1080p4k8k2;

  /// No description provided for @higherBetterQuality.
  ///
  /// In en, this message translates to:
  /// **'Higher = better quality'**
  String get higherBetterQuality;

  /// No description provided for @ffmpegPath.
  ///
  /// In en, this message translates to:
  /// **'FFmpeg path'**
  String get ffmpegPath;

  /// No description provided for @autoInstalledFirstUse.
  ///
  /// In en, this message translates to:
  /// **'Auto-installed on first use'**
  String get autoInstalledFirstUse;

  /// No description provided for @selectFfmpegExecutable.
  ///
  /// In en, this message translates to:
  /// **'Select FFmpeg executable'**
  String get selectFfmpegExecutable;

  /// No description provided for @willInstalledAutomaticallyWhenNeeded.
  ///
  /// In en, this message translates to:
  /// **'Will be installed automatically when needed.'**
  String get willInstalledAutomaticallyWhenNeeded;

  /// No description provided for @ytDlpPath.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp path'**
  String get ytDlpPath;

  /// No description provided for @autoDownloadedFirstUse.
  ///
  /// In en, this message translates to:
  /// **'Auto-downloaded on first use'**
  String get autoDownloadedFirstUse;

  /// No description provided for @selectYtDlpExecutable.
  ///
  /// In en, this message translates to:
  /// **'Select yt-dlp executable'**
  String get selectYtDlpExecutable;

  /// No description provided for @updatingYtDlp.
  ///
  /// In en, this message translates to:
  /// **'Updating yt-dlp...'**
  String get updatingYtDlp;

  /// No description provided for @ytDlp.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp: {msg} ({pct}%)'**
  String ytDlp(Object msg, Object pct);

  /// No description provided for @ytDlpUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp updated successfully'**
  String get ytDlpUpdatedSuccessfully;

  /// No description provided for @failedUpdateYtDlp.
  ///
  /// In en, this message translates to:
  /// **'Failed to update yt-dlp: {e}'**
  String failedUpdateYtDlp(Object e);

  /// No description provided for @check.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get check;

  /// No description provided for @useSponsorblock.
  ///
  /// In en, this message translates to:
  /// **'Use SponsorBlock'**
  String get useSponsorblock;

  /// No description provided for @automaticallyRemoveSponsoredIntroOutro.
  ///
  /// In en, this message translates to:
  /// **'Automatically remove sponsored/intro/outro segments when downloading videos.'**
  String get automaticallyRemoveSponsoredIntroOutro;

  /// No description provided for @useSignedYoutubeSession.
  ///
  /// In en, this message translates to:
  /// **'Use signed-in YouTube session'**
  String get useSignedYoutubeSession;

  /// No description provided for @useBrowserCookiesAgeRestricted.
  ///
  /// In en, this message translates to:
  /// **'Use browser cookies for age-restricted and private videos.'**
  String get useBrowserCookiesAgeRestricted;

  /// No description provided for @cookieSourceBrowser.
  ///
  /// In en, this message translates to:
  /// **'Cookie source browser'**
  String get cookieSourceBrowser;

  /// No description provided for @selectBrowserWhereSignedYoutube.
  ///
  /// In en, this message translates to:
  /// **'Select the browser where you are signed in to YouTube.'**
  String get selectBrowserWhereSignedYoutube;

  /// No description provided for @browserCookieExtractionNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Browser cookie extraction is not available on this platform. Use an exported cookies file instead.'**
  String get browserCookieExtractionNotAvailable;

  /// No description provided for @cookiesFileOptional.
  ///
  /// In en, this message translates to:
  /// **'Cookies file (optional)'**
  String get cookiesFileOptional;

  /// No description provided for @optionalExportedCookiesTxtUsed.
  ///
  /// In en, this message translates to:
  /// **'Optional exported cookies.txt. Used first when provided.'**
  String get optionalExportedCookiesTxtUsed;

  /// No description provided for @selectCookiesTxt.
  ///
  /// In en, this message translates to:
  /// **'Select cookies.txt'**
  String get selectCookiesTxt;

  /// No description provided for @signYoutube.
  ///
  /// In en, this message translates to:
  /// **'Sign in to YouTube'**
  String get signYoutube;

  /// No description provided for @clearCookiesFile.
  ///
  /// In en, this message translates to:
  /// **'Clear cookies file'**
  String get clearCookiesFile;

  /// No description provided for @willDownloadedAutomaticallyFirstLaunch.
  ///
  /// In en, this message translates to:
  /// **'Will be downloaded automatically on first launch.'**
  String get willDownloadedAutomaticallyFirstLaunch;

  /// No description provided for @retrySettings.
  ///
  /// In en, this message translates to:
  /// **'Retry Settings'**
  String get retrySettings;

  /// No description provided for @autoRetryInstalls.
  ///
  /// In en, this message translates to:
  /// **'Auto-retry installs'**
  String get autoRetryInstalls;

  /// No description provided for @automaticallyRetryFailedDownloads.
  ///
  /// In en, this message translates to:
  /// **'Automatically retry failed downloads'**
  String get automaticallyRetryFailedDownloads;

  /// No description provided for @retryCount010.
  ///
  /// In en, this message translates to:
  /// **'Retry count (0-10)'**
  String get retryCount010;

  /// No description provided for @numberRetryAttempts.
  ///
  /// In en, this message translates to:
  /// **'Number of retry attempts'**
  String get numberRetryAttempts;

  /// No description provided for @retryBackoffSeconds060.
  ///
  /// In en, this message translates to:
  /// **'Retry backoff seconds (0-60)'**
  String get retryBackoffSeconds060;

  /// No description provided for @waitTimeBetweenRetries.
  ///
  /// In en, this message translates to:
  /// **'Wait time between retries'**
  String get waitTimeBetweenRetries;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @redBullBasementSpireaiProject.
  ///
  /// In en, this message translates to:
  /// **'A Red Bull Basement / SpireAI project'**
  String get redBullBasementSpireaiProject;

  /// No description provided for @crossPlatformMediaToolkitMulti.
  ///
  /// In en, this message translates to:
  /// **'Cross-platform media toolkit with multi-site downloads, format conversion, and DLNA casting - built with Flutter.'**
  String get crossPlatformMediaToolkitMulti;

  /// No description provided for @copyrightC2026OrokaConner.
  ///
  /// In en, this message translates to:
  /// **'Copyright (c) 2026 Oroka Conner. Licensed under GPLv3.'**
  String get copyrightC2026OrokaConner;

  /// No description provided for @buyMeCoffee2.
  ///
  /// In en, this message translates to:
  /// **'Buy me a coffee'**
  String get buyMeCoffee2;

  /// No description provided for @visitQuizthespireCom.
  ///
  /// In en, this message translates to:
  /// **'Visit quizthespire.com'**
  String get visitQuizthespireCom;

  /// No description provided for @github.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get github;

  /// No description provided for @couldNotOpenGithubLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open the GitHub link.'**
  String get couldNotOpenGithubLink;

  /// No description provided for @browserShell.
  ///
  /// In en, this message translates to:
  /// **'Browser Shell'**
  String get browserShell;

  /// No description provided for @queueSidebarRight.
  ///
  /// In en, this message translates to:
  /// **'Queue sidebar on right'**
  String get queueSidebarRight;

  /// No description provided for @queuePanelRightSide.
  ///
  /// In en, this message translates to:
  /// **'Queue panel on the right side'**
  String get queuePanelRightSide;

  /// No description provided for @queuePanelLeftSide.
  ///
  /// In en, this message translates to:
  /// **'Queue panel on the left side'**
  String get queuePanelLeftSide;

  /// No description provided for @goHomePage.
  ///
  /// In en, this message translates to:
  /// **'Go to Home page'**
  String get goHomePage;

  /// No description provided for @navigateQuickLinksHome.
  ///
  /// In en, this message translates to:
  /// **'Navigate to quick links home'**
  String get navigateQuickLinksHome;

  /// No description provided for @resetQuickLinks.
  ///
  /// In en, this message translates to:
  /// **'Reset quick links'**
  String get resetQuickLinks;

  /// No description provided for @restoreDefaultQuickLinks.
  ///
  /// In en, this message translates to:
  /// **'Restore default quick links'**
  String get restoreDefaultQuickLinks;

  /// No description provided for @quickLinksResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Quick links reset to defaults'**
  String get quickLinksResetDefaults;

  /// No description provided for @replayTutorialTips.
  ///
  /// In en, this message translates to:
  /// **'Replay tutorial tips'**
  String get replayTutorialTips;

  /// No description provided for @showScreenDescriptionsAgain.
  ///
  /// In en, this message translates to:
  /// **'Show screen descriptions again'**
  String get showScreenDescriptionsAgain;

  /// No description provided for @tutorialTipsWillShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Tutorial tips will show again on each screen'**
  String get tutorialTipsWillShowAgain;

  /// No description provided for @checkUpdatesLaunch.
  ///
  /// In en, this message translates to:
  /// **'Check for updates on launch'**
  String get checkUpdatesLaunch;

  /// No description provided for @checkUpdatesNow.
  ///
  /// In en, this message translates to:
  /// **'Check for updates now'**
  String get checkUpdatesNow;

  /// No description provided for @couldNotOpenBuyMe.
  ///
  /// In en, this message translates to:
  /// **'Could not open the Buy Me a Coffee link.'**
  String get couldNotOpenBuyMe;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @couldNotOpenWebsite.
  ///
  /// In en, this message translates to:
  /// **'Could not open the website.'**
  String get couldNotOpenWebsite;

  /// No description provided for @couldNotOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Could not open folder: {e}'**
  String couldNotOpenFolder(Object e);

  /// No description provided for @couldNotPrepareFileSharing.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare file for sharing.'**
  String get couldNotPrepareFileSharing;

  /// No description provided for @couldNotShareFile.
  ///
  /// In en, this message translates to:
  /// **'Could not share file: {e}'**
  String couldNotShareFile(Object e);

  /// No description provided for @fileConverter.
  ///
  /// In en, this message translates to:
  /// **'File Converter'**
  String get fileConverter;

  /// No description provided for @selectFileConvert.
  ///
  /// In en, this message translates to:
  /// **'Select file to convert'**
  String get selectFileConvert;

  /// No description provided for @selectedFile.
  ///
  /// In en, this message translates to:
  /// **'Selected file:'**
  String get selectedFile;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// No description provided for @convertFormat.
  ///
  /// In en, this message translates to:
  /// **'Convert to format'**
  String get convertFormat;

  /// No description provided for @mp3Audio.
  ///
  /// In en, this message translates to:
  /// **'MP3 (Audio)'**
  String get mp3Audio;

  /// No description provided for @m4aAudio.
  ///
  /// In en, this message translates to:
  /// **'M4A (Audio)'**
  String get m4aAudio;

  /// No description provided for @wavAudio.
  ///
  /// In en, this message translates to:
  /// **'WAV (Audio)'**
  String get wavAudio;

  /// No description provided for @flacAudio.
  ///
  /// In en, this message translates to:
  /// **'FLAC (Audio)'**
  String get flacAudio;

  /// No description provided for @oggAudio.
  ///
  /// In en, this message translates to:
  /// **'OGG (Audio)'**
  String get oggAudio;

  /// No description provided for @aacAudio.
  ///
  /// In en, this message translates to:
  /// **'AAC (Audio)'**
  String get aacAudio;

  /// No description provided for @wmaAudio.
  ///
  /// In en, this message translates to:
  /// **'WMA (Audio)'**
  String get wmaAudio;

  /// No description provided for @webmVideo.
  ///
  /// In en, this message translates to:
  /// **'WebM (Video)'**
  String get webmVideo;

  /// No description provided for @mkvVideo.
  ///
  /// In en, this message translates to:
  /// **'MKV (Video)'**
  String get mkvVideo;

  /// No description provided for @aviVideo.
  ///
  /// In en, this message translates to:
  /// **'AVI (Video)'**
  String get aviVideo;

  /// No description provided for @movVideo.
  ///
  /// In en, this message translates to:
  /// **'MOV (Video)'**
  String get movVideo;

  /// No description provided for @wmvVideo.
  ///
  /// In en, this message translates to:
  /// **'WMV (Video)'**
  String get wmvVideo;

  /// No description provided for @pngImage.
  ///
  /// In en, this message translates to:
  /// **'PNG (Image)'**
  String get pngImage;

  /// No description provided for @jpgImage.
  ///
  /// In en, this message translates to:
  /// **'JPG (Image)'**
  String get jpgImage;

  /// No description provided for @bmpImage.
  ///
  /// In en, this message translates to:
  /// **'BMP (Image)'**
  String get bmpImage;

  /// No description provided for @gifImage.
  ///
  /// In en, this message translates to:
  /// **'GIF (Image)'**
  String get gifImage;

  /// No description provided for @tiffImage.
  ///
  /// In en, this message translates to:
  /// **'TIFF (Image)'**
  String get tiffImage;

  /// No description provided for @webpImage.
  ///
  /// In en, this message translates to:
  /// **'WebP (Image)'**
  String get webpImage;

  /// No description provided for @pdfDocument.
  ///
  /// In en, this message translates to:
  /// **'PDF (Document)'**
  String get pdfDocument;

  /// No description provided for @txtText.
  ///
  /// In en, this message translates to:
  /// **'TXT (Text)'**
  String get txtText;

  /// No description provided for @epubEBook.
  ///
  /// In en, this message translates to:
  /// **'EPUB (E-book)'**
  String get epubEBook;

  /// No description provided for @zipArchive.
  ///
  /// In en, this message translates to:
  /// **'ZIP (Archive)'**
  String get zipArchive;

  /// No description provided for @cbzComicArchive.
  ///
  /// In en, this message translates to:
  /// **'CBZ (Comic Archive)'**
  String get cbzComicArchive;

  /// No description provided for @converting2.
  ///
  /// In en, this message translates to:
  /// **'Converting…'**
  String get converting2;

  /// No description provided for @convertFile.
  ///
  /// In en, this message translates to:
  /// **'Convert File'**
  String get convertFile;

  /// No description provided for @conversionFailed.
  ///
  /// In en, this message translates to:
  /// **'Conversion failed: {error}'**
  String conversionFailed(Object error);

  /// No description provided for @convertedFiles.
  ///
  /// In en, this message translates to:
  /// **'Converted Files ({convertResultsCount})'**
  String convertedFiles(Object convertResultsCount);

  /// No description provided for @couldNotSaveLogsTab.
  ///
  /// In en, this message translates to:
  /// **'Could not save {resultName}. The Logs tab has the reason.'**
  String couldNotSaveLogsTab(Object resultName);

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved {resultName} to {savedTo}'**
  String saved(Object resultName, Object savedTo);

  /// No description provided for @applicationLogs.
  ///
  /// In en, this message translates to:
  /// **'Application Logs ({logsCount})'**
  String applicationLogs(Object logsCount);

  /// No description provided for @clearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear Logs'**
  String get clearLogs;

  /// No description provided for @noLogsYet.
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get noLogsYet;

  /// No description provided for @activityWillLoggedHere.
  ///
  /// In en, this message translates to:
  /// **'Activity will be logged here'**
  String get activityWillLoggedHere;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @torrentVaultMediaHubAdd.
  ///
  /// In en, this message translates to:
  /// **'{getAppTitle} is a torrent vault and media hub. Add magnet links and .torrent files, manage downloads, and keep everything organized from one app.'**
  String torrentVaultMediaHubAdd(Object getAppTitle);

  /// No description provided for @crossPlatformTorrentMediaToolkit.
  ///
  /// In en, this message translates to:
  /// **'{getAppTitle} is a cross-platform torrent and media toolkit. Add magnet links and .torrent files, manage downloads, convert formats, cast to your TV, and more - all from one app.'**
  String crossPlatformTorrentMediaToolkit(Object getAppTitle);

  /// No description provided for @findAddContent.
  ///
  /// In en, this message translates to:
  /// **'Find & Add Content'**
  String get findAddContent;

  /// No description provided for @browseWebBuiltViewOpen.
  ///
  /// In en, this message translates to:
  /// **'Browse the web in the built-in view and open magnet or torrent links directly, without leaving the app.'**
  String get browseWebBuiltViewOpen;

  /// No description provided for @addTorrentFilesMagnetLinks.
  ///
  /// In en, this message translates to:
  /// **'Add torrent files, magnet links, browser links, or local files. Search by keyword, compare results from more than one source, browse the web for links, or paste a whole list to import at once.'**
  String get addTorrentFilesMagnetLinks;

  /// No description provided for @previewResultBeforeDownload.
  ///
  /// In en, this message translates to:
  /// **'Preview a result before you download it'**
  String get previewResultBeforeDownload;

  /// No description provided for @multiSearch.
  ///
  /// In en, this message translates to:
  /// **'Multi-Search'**
  String get multiSearch;

  /// No description provided for @compareResultsFromSeveralSources.
  ///
  /// In en, this message translates to:
  /// **'Compare results from several sources at once'**
  String get compareResultsFromSeveralSources;

  /// No description provided for @browseWebOpenLinksApp.
  ///
  /// In en, this message translates to:
  /// **'Browse the web and open links in-app'**
  String get browseWebOpenLinksApp;

  /// No description provided for @bulkImport.
  ///
  /// In en, this message translates to:
  /// **'Bulk Import'**
  String get bulkImport;

  /// No description provided for @pasteImportListLinksOnce.
  ///
  /// In en, this message translates to:
  /// **'Paste or import a list of links at once'**
  String get pasteImportListLinksOnce;

  /// No description provided for @manageDownloads.
  ///
  /// In en, this message translates to:
  /// **'Manage Your Downloads'**
  String get manageDownloads;

  /// No description provided for @manageDownloadsStartRetryCancel.
  ///
  /// In en, this message translates to:
  /// **'Manage your downloads: start, retry, or cancel, and find finished files in your file manager.'**
  String get manageDownloadsStartRetryCancel;

  /// No description provided for @manageDownloadsStartRetryCancel2.
  ///
  /// In en, this message translates to:
  /// **'Manage your downloads: start, retry, cancel, or cast to your TV. Check totals, success rate, and trends any time in Stats.'**
  String get manageDownloadsStartRetryCancel2;

  /// No description provided for @startRetryCancelTrackStatus.
  ///
  /// In en, this message translates to:
  /// **'Start, retry, cancel, and track status'**
  String get startRetryCancelTrackStatus;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @totalsSuccessRateTrendsOver.
  ///
  /// In en, this message translates to:
  /// **'Totals, success rate, and trends over time'**
  String get totalsSuccessRateTrendsOver;

  /// No description provided for @playConvertCustomize.
  ///
  /// In en, this message translates to:
  /// **'Play, Convert & Customize'**
  String get playConvertCustomize;

  /// No description provided for @playFilesBuiltPlayerConvert.
  ///
  /// In en, this message translates to:
  /// **'Play your files in the built-in player, convert between formats with FFmpeg, and set folders, defaults, and appearance in Settings.'**
  String get playFilesBuiltPlayerConvert;

  /// No description provided for @playFilesBuiltPlayerSet.
  ///
  /// In en, this message translates to:
  /// **'Play your files in the built-in player, and set folders, format defaults, and appearance in Settings.'**
  String get playFilesBuiltPlayerSet;

  /// No description provided for @playbackShuffleRepeatSimpleLibrary.
  ///
  /// In en, this message translates to:
  /// **'Playback, shuffle, repeat, and a simple library'**
  String get playbackShuffleRepeatSimpleLibrary;

  /// No description provided for @convertAudioVideoBetweenFormats.
  ///
  /// In en, this message translates to:
  /// **'Convert audio/video between formats with FFmpeg'**
  String get convertAudioVideoBetweenFormats;

  /// No description provided for @foldersFormatDefaultsRetryBehaviour.
  ///
  /// In en, this message translates to:
  /// **'Folders, format defaults, retry behaviour, and more'**
  String get foldersFormatDefaultsRetryBehaviour;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @revisitGuideAnyTimeNeed.
  ///
  /// In en, this message translates to:
  /// **'Revisit the Guide any time you need a refresher, and help keep the project going with a donation.'**
  String get revisitGuideAnyTimeNeed;

  /// No description provided for @revisitGuideAnyTimeCheck.
  ///
  /// In en, this message translates to:
  /// **'Revisit the Guide any time, check the internal Logs if something goes wrong, and help keep the project open-source and ad-free with a donation.'**
  String get revisitGuideAnyTimeCheck;

  /// No description provided for @step.
  ///
  /// In en, this message translates to:
  /// **'Step {page} of {pagesCount}'**
  String step(Object page, Object pagesCount);

  /// No description provided for @themeTapCycle.
  ///
  /// In en, this message translates to:
  /// **'Theme: {themeLabel} — tap to cycle'**
  String themeTapCycle(Object themeLabel);

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @letsGo.
  ///
  /// In en, this message translates to:
  /// **'Let\'s Go!'**
  String get letsGo;

  /// No description provided for @helpScreenCanRevisitAny.
  ///
  /// In en, this message translates to:
  /// **'A help screen you can revisit any time'**
  String get helpScreenCanRevisitAny;

  /// No description provided for @inspectCopyClearInternalApp.
  ///
  /// In en, this message translates to:
  /// **'Inspect, copy, or clear the internal app log'**
  String get inspectCopyClearInternalApp;

  /// No description provided for @supportDonation.
  ///
  /// In en, this message translates to:
  /// **'Support with a donation'**
  String get supportDonation;

  /// No description provided for @buyMeCoffeeSponsorGithub.
  ///
  /// In en, this message translates to:
  /// **'Buy Me a Coffee or sponsor on GitHub'**
  String get buyMeCoffeeSponsorGithub;

  /// No description provided for @noAnalyticsEverythingRunsLocally.
  ///
  /// In en, this message translates to:
  /// **'No analytics - everything runs locally (ads use your advertising ID)'**
  String get noAnalyticsEverythingRunsLocally;

  /// No description provided for @noAnalyticsEverythingRunsLocally2.
  ///
  /// In en, this message translates to:
  /// **'No analytics - everything runs locally'**
  String get noAnalyticsEverythingRunsLocally2;

  /// No description provided for @goSettingsSupportDonate.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings → Support to donate'**
  String get goSettingsSupportDonate;

  /// No description provided for @roomWatchingWhichNotLibrary.
  ///
  /// In en, this message translates to:
  /// **'The room is watching \"{label}\", which is not in your library.'**
  String roomWatchingWhichNotLibrary(Object label);

  /// No description provided for @streamingFromHost.
  ///
  /// In en, this message translates to:
  /// **'Streaming \"{label}\" from the host.'**
  String streamingFromHost(Object label);

  /// No description provided for @exitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get exitFullscreen;

  /// No description provided for @fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get fullscreen;

  /// No description provided for @noSongsNeedMetadataFixes.
  ///
  /// In en, this message translates to:
  /// **'No songs need metadata fixes'**
  String get noSongsNeedMetadataFixes;

  /// No description provided for @fixingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Fixing metadata'**
  String get fixingMetadata;

  /// No description provided for @songsProcessed.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} songs processed'**
  String songsProcessed(Object done, Object total);

  /// No description provided for @metadataFixesComplete.
  ///
  /// In en, this message translates to:
  /// **'Metadata fixes complete'**
  String get metadataFixesComplete;

  /// No description provided for @selectMediaFolder.
  ///
  /// In en, this message translates to:
  /// **'Select media folder'**
  String get selectMediaFolder;

  /// No description provided for @scanningFolder.
  ///
  /// In en, this message translates to:
  /// **'Scanning folder'**
  String get scanningFolder;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait...'**
  String get pleaseWait;

  /// No description provided for @noMediaFilesFoundFolder.
  ///
  /// In en, this message translates to:
  /// **'No media files found in folder'**
  String get noMediaFilesFoundFolder;

  /// No description provided for @errorScanningFolder.
  ///
  /// In en, this message translates to:
  /// **'Error scanning folder: {e}'**
  String errorScanningFolder(Object e);

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All ({allCount})'**
  String all(Object allCount);

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'Songs ({songCount})'**
  String songs(Object songCount);

  /// No description provided for @videos.
  ///
  /// In en, this message translates to:
  /// **'Videos ({videoCount})'**
  String videos(Object videoCount);

  /// No description provided for @fav.
  ///
  /// In en, this message translates to:
  /// **'Fav ({favCount})'**
  String fav(Object favCount);

  /// No description provided for @organizeMedia.
  ///
  /// In en, this message translates to:
  /// **'Organize media'**
  String get organizeMedia;

  /// No description provided for @fixMissingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Fix missing metadata'**
  String get fixMissingMetadata;

  /// No description provided for @watchTogether.
  ///
  /// In en, this message translates to:
  /// **'Watch Together: {roomCode}'**
  String watchTogether(Object roomCode);

  /// No description provided for @watchTogether2.
  ///
  /// In en, this message translates to:
  /// **'Watch Together'**
  String get watchTogether2;

  /// No description provided for @volumeLeveling.
  ///
  /// In en, this message translates to:
  /// **'Volume leveling: on'**
  String get volumeLeveling;

  /// No description provided for @volumeLevelingOff.
  ///
  /// In en, this message translates to:
  /// **'Volume leveling: off'**
  String get volumeLevelingOff;

  /// No description provided for @volumeLevelingEveryTrackPlays.
  ///
  /// In en, this message translates to:
  /// **'Volume leveling on - every track plays at the same loudness'**
  String get volumeLevelingEveryTrackPlays;

  /// No description provided for @volumeLevelingOff2.
  ///
  /// In en, this message translates to:
  /// **'Volume leveling off'**
  String get volumeLevelingOff2;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @room.
  ///
  /// In en, this message translates to:
  /// **'Room {roomCode}'**
  String room(Object roomCode);

  /// No description provided for @volumeLeveling2.
  ///
  /// In en, this message translates to:
  /// **'Volume leveling'**
  String get volumeLeveling2;

  /// No description provided for @queueActions.
  ///
  /// In en, this message translates to:
  /// **'Queue actions'**
  String get queueActions;

  /// No description provided for @queueUpdated.
  ///
  /// In en, this message translates to:
  /// **'Queue updated'**
  String get queueUpdated;

  /// No description provided for @queueCurrentTab.
  ///
  /// In en, this message translates to:
  /// **'Queue current tab'**
  String get queueCurrentTab;

  /// No description provided for @queueAll.
  ///
  /// In en, this message translates to:
  /// **'Queue all'**
  String get queueAll;

  /// No description provided for @queueSongs.
  ///
  /// In en, this message translates to:
  /// **'Queue songs'**
  String get queueSongs;

  /// No description provided for @queueVideos.
  ///
  /// In en, this message translates to:
  /// **'Queue videos'**
  String get queueVideos;

  /// No description provided for @queueFavourites.
  ///
  /// In en, this message translates to:
  /// **'Queue favourites'**
  String get queueFavourites;

  /// No description provided for @queueFavouriteSongs.
  ///
  /// In en, this message translates to:
  /// **'Queue favourite songs'**
  String get queueFavouriteSongs;

  /// No description provided for @queueFavouriteVideos.
  ///
  /// In en, this message translates to:
  /// **'Queue favourite videos'**
  String get queueFavouriteVideos;

  /// No description provided for @clearQueue2.
  ///
  /// In en, this message translates to:
  /// **'Clear queue'**
  String get clearQueue2;

  /// No description provided for @scanningCommonFoldersMedia.
  ///
  /// In en, this message translates to:
  /// **'Scanning common folders for media...'**
  String get scanningCommonFoldersMedia;

  /// No description provided for @discoveredFolders.
  ///
  /// In en, this message translates to:
  /// **'Discovered folders ({discoveredCount})'**
  String discoveredFolders(Object discoveredCount);

  /// No description provided for @selectTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Select target folder'**
  String get selectTargetFolder;

  /// No description provided for @chooseTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose target folder'**
  String get chooseTargetFolder;

  /// No description provided for @noTargetSelected.
  ///
  /// In en, this message translates to:
  /// **'No target selected'**
  String get noTargetSelected;

  /// No description provided for @createPlaylistTargetFolderAfter.
  ///
  /// In en, this message translates to:
  /// **'Create playlist in target folder after organizing'**
  String get createPlaylistTargetFolderAfter;

  /// No description provided for @pleaseChooseTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Please choose a target folder'**
  String get pleaseChooseTargetFolder;

  /// No description provided for @organizedMovedFilesDeletedDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Organized: moved {moved} files, deleted {deleted} duplicates'**
  String organizedMovedFilesDeletedDuplicates(Object moved, Object deleted);

  /// No description provided for @errorDuringOrganization.
  ///
  /// In en, this message translates to:
  /// **'Error during organization: {e}'**
  String errorDuringOrganization(Object e);

  /// No description provided for @organize.
  ///
  /// In en, this message translates to:
  /// **'Organize'**
  String get organize;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// No description provided for @oldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get oldestFirst;

  /// No description provided for @titleZ.
  ///
  /// In en, this message translates to:
  /// **'Title A-Z'**
  String get titleZ;

  /// No description provided for @titleZ2.
  ///
  /// In en, this message translates to:
  /// **'Title Z-A'**
  String get titleZ2;

  /// No description provided for @shortestFirst.
  ///
  /// In en, this message translates to:
  /// **'Shortest first'**
  String get shortestFirst;

  /// No description provided for @mostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get mostPlayed;

  /// No description provided for @leastPlayed.
  ///
  /// In en, this message translates to:
  /// **'Least played'**
  String get leastPlayed;

  /// No description provided for @recentlyPlayed.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get recentlyPlayed;

  /// No description provided for @removeFavourite.
  ///
  /// In en, this message translates to:
  /// **'Remove favourite'**
  String get removeFavourite;

  /// No description provided for @addFavourite2.
  ///
  /// In en, this message translates to:
  /// **'Add favourite'**
  String get addFavourite2;

  /// No description provided for @undoDislike.
  ///
  /// In en, this message translates to:
  /// **'Undo dislike'**
  String get undoDislike;

  /// No description provided for @dislike.
  ///
  /// In en, this message translates to:
  /// **'Dislike'**
  String get dislike;

  /// No description provided for @streamingFromWatchTogetherHost.
  ///
  /// In en, this message translates to:
  /// **'Streaming from the Watch Together host'**
  String get streamingFromWatchTogetherHost;

  /// No description provided for @openedFileNotInLibrary.
  ///
  /// In en, this message translates to:
  /// **'Opened file, not in your library'**
  String get openedFileNotInLibrary;

  /// No description provided for @trackActions.
  ///
  /// In en, this message translates to:
  /// **'Track actions'**
  String get trackActions;

  /// No description provided for @metadataFixed.
  ///
  /// In en, this message translates to:
  /// **'Metadata fixed'**
  String get metadataFixed;

  /// No description provided for @couldNotFixMetadata.
  ///
  /// In en, this message translates to:
  /// **'Could not fix metadata'**
  String get couldNotFixMetadata;

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete file?'**
  String get deleteFile;

  /// No description provided for @permanentlyDeletesFromDisk.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes \"{item}\" from disk.'**
  String permanentlyDeletesFromDisk(Object item);

  /// No description provided for @fileDeleted.
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get fileDeleted;

  /// No description provided for @couldNotDeleteFile.
  ///
  /// In en, this message translates to:
  /// **'Could not delete file'**
  String get couldNotDeleteFile;

  /// No description provided for @fixMetadata.
  ///
  /// In en, this message translates to:
  /// **'Fix Metadata'**
  String get fixMetadata;

  /// No description provided for @deleteFile2.
  ///
  /// In en, this message translates to:
  /// **'Delete file'**
  String get deleteFile2;

  /// No description provided for @opening.
  ///
  /// In en, this message translates to:
  /// **'Opening {restoringFolder}…'**
  String opening(Object restoringFolder);

  /// No description provided for @libraryEmptyOpenFolderMusic.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty.\nOpen the folder your music and videos are in. The app remembers it for next time.'**
  String get libraryEmptyOpenFolderMusic;

  /// No description provided for @noResultsSearch.
  ///
  /// In en, this message translates to:
  /// **'No results for this search.'**
  String get noResultsSearch;

  /// No description provided for @noSongsFound.
  ///
  /// In en, this message translates to:
  /// **'No songs found.'**
  String get noSongsFound;

  /// No description provided for @noVideosFound.
  ///
  /// In en, this message translates to:
  /// **'No videos found.'**
  String get noVideosFound;

  /// No description provided for @noFavouritesYetTapStar.
  ///
  /// In en, this message translates to:
  /// **'No favourites yet.\nTap the star on any track to add it here.'**
  String get noFavouritesYetTapStar;

  /// No description provided for @plays.
  ///
  /// In en, this message translates to:
  /// **'{playCount} plays • {totalPlayedDuration}'**
  String plays(Object playCount, Object totalPlayedDuration);

  /// No description provided for @selectMusicFolderCompare.
  ///
  /// In en, this message translates to:
  /// **'Select music folder to compare'**
  String get selectMusicFolderCompare;

  /// No description provided for @noFilesCouldMoved.
  ///
  /// In en, this message translates to:
  /// **'No files could be moved'**
  String get noFilesCouldMoved;

  /// No description provided for @movedFilesDeletedDuplicates.
  ///
  /// In en, this message translates to:
  /// **'{label}: moved {moved} files, deleted {deleted} duplicates'**
  String movedFilesDeletedDuplicates(
      Object label, Object moved, Object deleted);

  /// No description provided for @autoResolveFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto-resolve failed: {e}'**
  String autoResolveFailed(Object e);

  /// No description provided for @deletedIncompleteDownloadFiles.
  ///
  /// In en, this message translates to:
  /// **'Deleted {removed} incomplete download files'**
  String deletedIncompleteDownloadFiles(Object removed);

  /// No description provided for @chooseFolderFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder for {entryKey} files'**
  String chooseFolderFiles(Object entryKey);

  /// No description provided for @chooseFolderMoveExtraFiles.
  ///
  /// In en, this message translates to:
  /// **'Choose folder to move extra files into'**
  String get chooseFolderMoveExtraFiles;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted {fileName}'**
  String deleted(Object fileName);

  /// No description provided for @chooseFolderFiles2.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder for {extensionValue} files'**
  String chooseFolderFiles2(Object extensionValue);

  /// No description provided for @exportMissingTracks.
  ///
  /// In en, this message translates to:
  /// **'Export missing tracks'**
  String get exportMissingTracks;

  /// No description provided for @exportedTracks.
  ///
  /// In en, this message translates to:
  /// **'Exported {missingCount} tracks'**
  String exportedTracks(Object missingCount);

  /// No description provided for @saveM3uPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Save M3U playlist'**
  String get saveM3uPlaylist;

  /// No description provided for @savedM3uPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Saved the M3U playlist'**
  String get savedM3uPlaylist;

  /// No description provided for @couldNotSaveFile.
  ///
  /// In en, this message translates to:
  /// **'Could not save the file: {e}'**
  String couldNotSaveFile(Object e);

  /// No description provided for @downloading2.
  ///
  /// In en, this message translates to:
  /// **'Downloading \"{firstTitle}\"'**
  String downloading2(Object firstTitle);

  /// No description provided for @downloadingTracks.
  ///
  /// In en, this message translates to:
  /// **'Downloading {tracksCount} tracks'**
  String downloadingTracks(Object tracksCount);

  /// No description provided for @compare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get compare;

  /// No description provided for @folderCompare.
  ///
  /// In en, this message translates to:
  /// **'Folder to compare'**
  String get folderCompare;

  /// No description provided for @localMusicFolderPath.
  ///
  /// In en, this message translates to:
  /// **'Local music folder path'**
  String get localMusicFolderPath;

  /// No description provided for @youtubePlaylistUrl.
  ///
  /// In en, this message translates to:
  /// **'YouTube playlist URL'**
  String get youtubePlaylistUrl;

  /// No description provided for @load.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// No description provided for @browse2.
  ///
  /// In en, this message translates to:
  /// **'Browse…'**
  String get browse2;

  /// No description provided for @downloadFormat.
  ///
  /// In en, this message translates to:
  /// **'Download format:'**
  String get downloadFormat;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @matched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get matched;

  /// No description provided for @missing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get missing;

  /// No description provided for @extras.
  ///
  /// In en, this message translates to:
  /// **'Extras'**
  String get extras;

  /// No description provided for @tracks.
  ///
  /// In en, this message translates to:
  /// **'{playlistInfo}  •  {tracks} tracks  •  {tracks2}'**
  String tracks(Object playlistInfo, Object tracks, Object tracks2);

  /// No description provided for @exportM3u.
  ///
  /// In en, this message translates to:
  /// **'Export as M3U'**
  String get exportM3u;

  /// No description provided for @exportMissingList.
  ///
  /// In en, this message translates to:
  /// **'Export missing list'**
  String get exportMissingList;

  /// No description provided for @tracksMatchedLowConfidenceReview.
  ///
  /// In en, this message translates to:
  /// **'{comparison} tracks matched with low confidence - review them in the Matched tab.'**
  String tracksMatchedLowConfidenceReview(Object comparison);

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @downloadAllMissingTracks.
  ///
  /// In en, this message translates to:
  /// **'Download All {comparison} Missing Tracks'**
  String downloadAllMissingTracks(Object comparison);

  /// No description provided for @theyGoDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'They go to your download folder.'**
  String get theyGoDownloadFolder;

  /// No description provided for @theyGoIntoNextRest.
  ///
  /// In en, this message translates to:
  /// **'They go into {downloadFolderForMissing}, next to the rest of the playlist.'**
  String theyGoIntoNextRest(Object downloadFolderForMissing);

  /// No description provided for @tracksLoadedChooseFolderAbove.
  ///
  /// In en, this message translates to:
  /// **'{tracks} tracks loaded. Choose a folder above to see which you already have.'**
  String tracksLoadedChooseFolderAbove(Object tracks);

  /// No description provided for @tracksLoadedPressCompareSee.
  ///
  /// In en, this message translates to:
  /// **'{tracks} tracks loaded. Press Compare to see which are already in the folder.'**
  String tracksLoadedPressCompareSee(Object tracks);

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @completion.
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get completion;

  /// No description provided for @minConfidence.
  ///
  /// In en, this message translates to:
  /// **'Min confidence: '**
  String get minConfidence;

  /// No description provided for @playlistOrder.
  ///
  /// In en, this message translates to:
  /// **'Playlist order'**
  String get playlistOrder;

  /// No description provided for @confidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence ↑'**
  String get confidence;

  /// No description provided for @noMatchesConfidenceLevel.
  ///
  /// In en, this message translates to:
  /// **'No matches at this confidence level'**
  String get noMatchesConfidenceLevel;

  /// No description provided for @allPlaylistTracksFolder.
  ///
  /// In en, this message translates to:
  /// **'All playlist tracks are in the folder!'**
  String get allPlaylistTracksFolder;

  /// No description provided for @downloadSelected.
  ///
  /// In en, this message translates to:
  /// **'Download Selected ({missingSelectionCount}/{comparison})'**
  String downloadSelected(Object missingSelectionCount, Object comparison);

  /// No description provided for @clearSelection2.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get clearSelection2;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @exportList.
  ///
  /// In en, this message translates to:
  /// **'Export List'**
  String get exportList;

  /// No description provided for @rangeSelectStartedTapAnother.
  ///
  /// In en, this message translates to:
  /// **'Range select started. Tap another item to select a range.'**
  String get rangeSelectStartedTapAnother;

  /// No description provided for @downloadTrack.
  ///
  /// In en, this message translates to:
  /// **'Download this track'**
  String get downloadTrack;

  /// No description provided for @noMusicFiles.
  ///
  /// In en, this message translates to:
  /// **'No music files in {comparison}.'**
  String noMusicFiles(Object comparison);

  /// No description provided for @whyEveryTrackShowsMissing.
  ///
  /// In en, this message translates to:
  /// **'That is why every track shows as missing. Pick the folder your songs are in; subfolders are included.'**
  String get whyEveryTrackShowsMissing;

  /// No description provided for @chooseAnotherFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose another folder'**
  String get chooseAnotherFolder;

  /// No description provided for @runComparisonFirst.
  ///
  /// In en, this message translates to:
  /// **'Run a comparison first'**
  String get runComparisonFirst;

  /// No description provided for @folder2.
  ///
  /// In en, this message translates to:
  /// **'Folder: {folder}'**
  String folder2(Object folder);

  /// No description provided for @compareNow.
  ///
  /// In en, this message translates to:
  /// **'Compare Now'**
  String get compareNow;

  /// No description provided for @chooseFolder2.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder'**
  String get chooseFolder2;

  /// No description provided for @noExtraFilesFolderMatches.
  ///
  /// In en, this message translates to:
  /// **'No extra files - folder matches the playlist perfectly'**
  String get noExtraFilesFolderMatches;

  /// No description provided for @incompleteDownloads.
  ///
  /// In en, this message translates to:
  /// **'Incomplete downloads'**
  String get incompleteDownloads;

  /// No description provided for @partiallyDownloadedTempArtifactsSafe.
  ///
  /// In en, this message translates to:
  /// **'Partially-downloaded temp artifacts - safe to delete'**
  String get partiallyDownloadedTempArtifactsSafe;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @wrongFormat.
  ///
  /// In en, this message translates to:
  /// **'Wrong format'**
  String get wrongFormat;

  /// No description provided for @filesWhoseFormatDiffersFrom.
  ///
  /// In en, this message translates to:
  /// **'Files whose format differs from the folder\'s dominant format'**
  String get filesWhoseFormatDiffersFrom;

  /// No description provided for @moveAll.
  ///
  /// In en, this message translates to:
  /// **'Move all'**
  String get moveAll;

  /// No description provided for @notPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Not in playlist'**
  String get notPlaylist;

  /// No description provided for @rightFormatFilesNoPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Right-format files that no playlist track matches'**
  String get rightFormatFilesNoPlaylist;

  /// No description provided for @more2.
  ///
  /// In en, this message translates to:
  /// **'…and {files} more'**
  String more2(Object files);

  /// No description provided for @downloadFolderScanComplete.
  ///
  /// In en, this message translates to:
  /// **'Download folder scan complete'**
  String get downloadFolderScanComplete;

  /// No description provided for @enterSearchTermFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter a search term first.'**
  String get enterSearchTermFirst;

  /// No description provided for @searchMusicAcrossSources.
  ///
  /// In en, this message translates to:
  /// **'Search for music across sources…'**
  String get searchMusicAcrossSources;

  /// No description provided for @scanningDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Scanning download folder…'**
  String get scanningDownloadFolder;

  /// No description provided for @refreshDownloadedFileStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh downloaded file status'**
  String get refreshDownloadedFileStatus;

  /// No description provided for @searchingAcrossAllSources.
  ///
  /// In en, this message translates to:
  /// **'Searching across all sources…'**
  String get searchingAcrossAllSources;

  /// No description provided for @lastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {lastDownloadFolderScan}'**
  String lastScan(Object lastDownloadFolderScan);

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @searchMusicAcrossSources2.
  ///
  /// In en, this message translates to:
  /// **'Search for music across sources'**
  String get searchMusicAcrossSources2;

  /// No description provided for @tryDifferentArtistTitleSource.
  ///
  /// In en, this message translates to:
  /// **'Try a different artist, title, or source.'**
  String get tryDifferentArtistTitleSource;

  /// No description provided for @enterQueryAboveStartSearching.
  ///
  /// In en, this message translates to:
  /// **'Enter a query above to start searching.'**
  String get enterQueryAboveStartSearching;

  /// No description provided for @previewBrowser.
  ///
  /// In en, this message translates to:
  /// **'Preview in browser'**
  String get previewBrowser;

  /// No description provided for @noDownloadDataYet.
  ///
  /// In en, this message translates to:
  /// **'No download data yet'**
  String get noDownloadDataYet;

  /// No description provided for @statisticsWillAppearHereAfter.
  ///
  /// In en, this message translates to:
  /// **'Statistics will appear here after your first download.'**
  String get statisticsWillAppearHereAfter;

  /// No description provided for @resetStatistics.
  ///
  /// In en, this message translates to:
  /// **'Reset Statistics'**
  String get resetStatistics;

  /// No description provided for @successful.
  ///
  /// In en, this message translates to:
  /// **'Successful'**
  String get successful;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @successRate.
  ///
  /// In en, this message translates to:
  /// **'Success Rate'**
  String get successRate;

  /// No description provided for @resetStatistics2.
  ///
  /// In en, this message translates to:
  /// **'Reset Statistics?'**
  String get resetStatistics2;

  /// No description provided for @willPermanentlyDeleteAllDownload.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all download statistics. This action cannot be undone.'**
  String get willPermanentlyDeleteAllDownload;

  /// No description provided for @removeAdsUnlockedAllAds.
  ///
  /// In en, this message translates to:
  /// **'Remove Ads unlocked. All ads are off.'**
  String get removeAdsUnlockedAllAds;

  /// No description provided for @couldNotLaunch.
  ///
  /// In en, this message translates to:
  /// **'Could not launch {url}'**
  String couldNotLaunch(Object url);

  /// No description provided for @removeAdsPurchasesOnlyAvailable.
  ///
  /// In en, this message translates to:
  /// **'Remove Ads purchases are only available on Android Play builds.'**
  String get removeAdsPurchasesOnlyAvailable;

  /// No description provided for @openingPlayPurchaseFlow.
  ///
  /// In en, this message translates to:
  /// **'Opening the Play purchase flow…'**
  String get openingPlayPurchaseFlow;

  /// No description provided for @restoreRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Restore request sent.'**
  String get restoreRequestSent;

  /// No description provided for @chooseAppThemeUsedAcross.
  ///
  /// In en, this message translates to:
  /// **'Choose the app theme used across the desktop and mobile UI.'**
  String get chooseAppThemeUsedAcross;

  /// No description provided for @themeSet.
  ///
  /// In en, this message translates to:
  /// **'Theme set to {nextMode}'**
  String themeSet(Object nextMode);

  /// No description provided for @adPreferences.
  ///
  /// In en, this message translates to:
  /// **'Ad Preferences'**
  String get adPreferences;

  /// No description provided for @manageAdPersonalisationConsent.
  ///
  /// In en, this message translates to:
  /// **'Manage your ad personalisation consent.'**
  String get manageAdPersonalisationConsent;

  /// No description provided for @manageAdPreferences.
  ///
  /// In en, this message translates to:
  /// **'Manage Ad Preferences'**
  String get manageAdPreferences;

  /// No description provided for @adsOffFor30MinutesThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you! Ads are off for 30 minutes.'**
  String get adsOffFor30MinutesThanks;

  /// No description provided for @noRewardRecordedAdsStayOn.
  ///
  /// In en, this message translates to:
  /// **'No reward was recorded. Ads stay on.'**
  String get noRewardRecordedAdsStayOn;

  /// No description provided for @thanksForSupportAdsStayOn.
  ///
  /// In en, this message translates to:
  /// **'Great! Thanks for your support. Ads stay on.'**
  String get thanksForSupportAdsStayOn;

  /// No description provided for @noRewardRecordedTryAgain.
  ///
  /// In en, this message translates to:
  /// **'No reward was recorded. Try again if you want to support.'**
  String get noRewardRecordedTryAgain;

  /// No description provided for @favouritesCleanedRemovedInvalidDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Favourites cleaned: removed {removed} invalid or duplicate entries.'**
  String favouritesCleanedRemovedInvalidDuplicate(Object removed);

  /// No description provided for @noInvalidDuplicateFavouritesFound.
  ///
  /// In en, this message translates to:
  /// **'No invalid or duplicate favourites found.'**
  String get noInvalidDuplicateFavouritesFound;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support {getAppTitle}'**
  String support(Object getAppTitle);

  /// No description provided for @ifEnjoyUsingBestWay.
  ///
  /// In en, this message translates to:
  /// **'If you enjoy using {getAppTitle}, the best way to support continued development is via donations or the one-time Remove Ads unlock.'**
  String ifEnjoyUsingBestWay(Object getAppTitle);

  /// No description provided for @adsWatchedBySupporters.
  ///
  /// In en, this message translates to:
  /// **'Ads watched by supporters: {adsWatchedCount}'**
  String adsWatchedBySupporters(Object adsWatchedCount);

  /// No description provided for @adsPausedRemaining.
  ///
  /// In en, this message translates to:
  /// **'Ads paused: {adBreakRemaining} remaining'**
  String adsPausedRemaining(Object adBreakRemaining);

  /// No description provided for @removeAds.
  ///
  /// In en, this message translates to:
  /// **'Remove Ads'**
  String get removeAds;

  /// No description provided for @adsAlreadyRemovedDevice.
  ///
  /// In en, this message translates to:
  /// **'Ads are already removed on this device.'**
  String get adsAlreadyRemovedDevice;

  /// No description provided for @oneTimeUnlockSuppressesEvery.
  ///
  /// In en, this message translates to:
  /// **'One-time unlock that suppresses every ad placement in the app.'**
  String get oneTimeUnlockSuppressesEvery;

  /// No description provided for @adsRemoved.
  ///
  /// In en, this message translates to:
  /// **'Ads removed'**
  String get adsRemoved;

  /// No description provided for @removeAds2.
  ///
  /// In en, this message translates to:
  /// **'Remove Ads — {removeAdsPriceLabel}'**
  String removeAds2(Object removeAdsPriceLabel);

  /// No description provided for @restorePurchase.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchase'**
  String get restorePurchase;

  /// No description provided for @purchasesOnlyAvailableAndroidPlay.
  ///
  /// In en, this message translates to:
  /// **'Purchases are only available on Android Play builds.'**
  String get purchasesOnlyAvailableAndroidPlay;

  /// No description provided for @playerFavourites2.
  ///
  /// In en, this message translates to:
  /// **'Player Favourites'**
  String get playerFavourites2;

  /// No description provided for @removeGhostEntriesDeduplicateFavourites.
  ///
  /// In en, this message translates to:
  /// **'Remove ghost entries and deduplicate favourites by path, URL, or content id.'**
  String get removeGhostEntriesDeduplicateFavourites;

  /// No description provided for @cleanUpFavourites.
  ///
  /// In en, this message translates to:
  /// **'Clean Up Favourites'**
  String get cleanUpFavourites;

  /// No description provided for @goodwillSupportAds.
  ///
  /// In en, this message translates to:
  /// **'Goodwill Support Ads'**
  String get goodwillSupportAds;

  /// No description provided for @noFakePromisesTheseActions.
  ///
  /// In en, this message translates to:
  /// **'No fake promises: these actions are exactly what they claim.'**
  String get noFakePromisesTheseActions;

  /// No description provided for @turnAdsOff30Min.
  ///
  /// In en, this message translates to:
  /// **'Turn ads off for 30 min'**
  String get turnAdsOff30Min;

  /// No description provided for @supportMeAdsStay.
  ///
  /// In en, this message translates to:
  /// **'Support me (ads stay on)'**
  String get supportMeAdsStay;

  /// No description provided for @adPauseActiveRewardedAds.
  ///
  /// In en, this message translates to:
  /// **'Ad pause active. Rewarded ads are temporarily hidden.'**
  String get adPauseActiveRewardedAds;

  /// No description provided for @rewardedAdsCurrentlyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Rewarded ads are currently unavailable.'**
  String get rewardedAdsCurrentlyUnavailable;

  /// No description provided for @watchDemoVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch the demo video'**
  String get watchDemoVideo;

  /// No description provided for @quickTourAppYoutube.
  ///
  /// In en, this message translates to:
  /// **'A quick tour of the app on YouTube'**
  String get quickTourAppYoutube;

  /// No description provided for @helpKeepProjectFreeOpen.
  ///
  /// In en, this message translates to:
  /// **'Help keep this project free & open-source'**
  String get helpKeepProjectFreeOpen;

  /// No description provided for @advancedBuildGithub.
  ///
  /// In en, this message translates to:
  /// **'Advanced build on GitHub'**
  String get advancedBuildGithub;

  /// No description provided for @openSourceBuildAllFeatures.
  ///
  /// In en, this message translates to:
  /// **'Open-source build with all features enabled'**
  String get openSourceBuildAllFeatures;

  /// No description provided for @supportOngoingDevelopmentFeatureWork.
  ///
  /// In en, this message translates to:
  /// **'Support ongoing development and feature work'**
  String get supportOngoingDevelopmentFeatureWork;

  /// No description provided for @privacyFirst.
  ///
  /// In en, this message translates to:
  /// **'Privacy First'**
  String get privacyFirst;

  /// No description provided for @appDoesNotCollectAnalytics.
  ///
  /// In en, this message translates to:
  /// **'This app does not collect analytics or track what you download, and all processing happens locally on your device. Ads are served by Google AdMob, which uses your device advertising ID.'**
  String get appDoesNotCollectAnalytics;

  /// No description provided for @appDoesNotCollectAnalytics2.
  ///
  /// In en, this message translates to:
  /// **'This app does not collect analytics or track what you download. All processing happens locally on your device.'**
  String get appDoesNotCollectAnalytics2;

  /// No description provided for @everyoneSameWifiStaysStep.
  ///
  /// In en, this message translates to:
  /// **'Everyone on the same wifi stays in step — play, pause and seek together.'**
  String get everyoneSameWifiStaysStep;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get name;

  /// No description provided for @startRoom.
  ///
  /// In en, this message translates to:
  /// **'Start a room'**
  String get startRoom;

  /// No description provided for @joinOne.
  ///
  /// In en, this message translates to:
  /// **'or join one'**
  String get joinOne;

  /// No description provided for @roomCode.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get roomCode;

  /// No description provided for @lookingRoom.
  ///
  /// In en, this message translates to:
  /// **'Looking for the room…'**
  String get lookingRoom;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @roomCode2.
  ///
  /// In en, this message translates to:
  /// **'Your room code'**
  String get roomCode2;

  /// No description provided for @room2.
  ///
  /// In en, this message translates to:
  /// **'In room'**
  String get room2;

  /// No description provided for @roomCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Room code copied'**
  String get roomCodeCopied;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @closeRoom.
  ///
  /// In en, this message translates to:
  /// **'Close the room'**
  String get closeRoom;

  /// No description provided for @leaveRoom.
  ///
  /// In en, this message translates to:
  /// **'Leave the room'**
  String get leaveRoom;

  /// No description provided for @pleaseEnterValidYoutubePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid YouTube playlist URL'**
  String get pleaseEnterValidYoutubePlaylist;

  /// No description provided for @removePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove Playlist'**
  String get removePlaylist;

  /// No description provided for @stopWatchingPlaylistCanRe.
  ///
  /// In en, this message translates to:
  /// **'Stop watching this playlist? You can re-add it later.'**
  String get stopWatchingPlaylistCanRe;

  /// No description provided for @newTrackSQueuedDownload.
  ///
  /// In en, this message translates to:
  /// **'{found} new track(s) queued for download'**
  String newTrackSQueuedDownload(Object found);

  /// No description provided for @failedCheckPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Failed to check playlists: {e}'**
  String failedCheckPlaylists(Object e);

  /// No description provided for @watchedPlaylistsCheckedPeriodicallyAny.
  ///
  /// In en, this message translates to:
  /// **'Watched playlists are checked periodically, and any new tracks are automatically downloaded.'**
  String get watchedPlaylistsCheckedPeriodicallyAny;

  /// No description provided for @pasteYoutubePlaylistUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste YouTube playlist URL'**
  String get pasteYoutubePlaylistUrl;

  /// No description provided for @addPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add playlist'**
  String get addPlaylist;

  /// No description provided for @checkAllNewTracks.
  ///
  /// In en, this message translates to:
  /// **'Check all for new tracks'**
  String get checkAllNewTracks;

  /// No description provided for @noWatchedPlaylistsYet.
  ///
  /// In en, this message translates to:
  /// **'No watched playlists yet'**
  String get noWatchedPlaylistsYet;

  /// No description provided for @addYoutubePlaylistUrlAbove.
  ///
  /// In en, this message translates to:
  /// **'Add a YouTube playlist URL above to track new tracks'**
  String get addYoutubePlaylistUrlAbove;

  /// No description provided for @editWatchSettings.
  ///
  /// In en, this message translates to:
  /// **'Edit watch settings'**
  String get editWatchSettings;

  /// No description provided for @removePlaylist2.
  ///
  /// In en, this message translates to:
  /// **'Remove playlist'**
  String get removePlaylist2;

  /// No description provided for @selectWatchedFolder.
  ///
  /// In en, this message translates to:
  /// **'Select watched folder'**
  String get selectWatchedFolder;

  /// No description provided for @editWatchedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Edit watched playlist'**
  String get editWatchedPlaylist;

  /// No description provided for @addWatchedPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add watched playlist'**
  String get addWatchedPlaylist;

  /// No description provided for @downloadFormat2.
  ///
  /// In en, this message translates to:
  /// **'Download format'**
  String get downloadFormat2;

  /// No description provided for @appDefault.
  ///
  /// In en, this message translates to:
  /// **'App default'**
  String get appDefault;

  /// No description provided for @useDefaultFolder.
  ///
  /// In en, this message translates to:
  /// **'Use default folder'**
  String get useDefaultFolder;

  /// No description provided for @aiSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'AI settings saved'**
  String get aiSettingsSaved;

  /// No description provided for @noDownloadFolderSet.
  ///
  /// In en, this message translates to:
  /// **'No download folder set.'**
  String get noDownloadFolderSet;

  /// No description provided for @downloadFolderDoesNotExist.
  ///
  /// In en, this message translates to:
  /// **'Download folder does not exist.'**
  String get downloadFolderDoesNotExist;

  /// No description provided for @unableOpenFolderAutomaticallyFiles.
  ///
  /// In en, this message translates to:
  /// **'Unable to open folder automatically. Files saved to: {directoryPath}'**
  String unableOpenFolderAutomaticallyFiles(Object directoryPath);

  /// No description provided for @failedOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Failed to open folder.'**
  String get failedOpenFolder;

  /// No description provided for @connectionSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Connection settings saved'**
  String get connectionSettingsSaved;

  /// No description provided for @downloadFolderSaved.
  ///
  /// In en, this message translates to:
  /// **'Download folder saved'**
  String get downloadFolderSaved;

  /// No description provided for @unableOpenPrivacyPolicyLink.
  ///
  /// In en, this message translates to:
  /// **'Unable to open privacy policy link.'**
  String get unableOpenPrivacyPolicyLink;

  /// No description provided for @diagnosticsExportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics export cancelled.'**
  String get diagnosticsExportCancelled;

  /// No description provided for @diagnosticsExported.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics exported: {path}'**
  String diagnosticsExported(Object path);

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @defaultDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Default download folder'**
  String get defaultDownloadFolder;

  /// No description provided for @downloadFolderSet.
  ///
  /// In en, this message translates to:
  /// **'Download folder set: {result}'**
  String downloadFolderSet(Object result);

  /// No description provided for @chooseDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose download folder'**
  String get chooseDownloadFolder;

  /// No description provided for @saveFolder.
  ///
  /// In en, this message translates to:
  /// **'Save Folder'**
  String get saveFolder;

  /// No description provided for @autoStartWhenAdded.
  ///
  /// In en, this message translates to:
  /// **'Auto-start when added'**
  String get autoStartWhenAdded;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @listenPort.
  ///
  /// In en, this message translates to:
  /// **'Listen port'**
  String get listenPort;

  /// No description provided for @maxGlobalConnections.
  ///
  /// In en, this message translates to:
  /// **'Max global connections'**
  String get maxGlobalConnections;

  /// No description provided for @maxConnectionsPerTorrent.
  ///
  /// In en, this message translates to:
  /// **'Max connections per torrent'**
  String get maxConnectionsPerTorrent;

  /// No description provided for @maxActiveDownloads.
  ///
  /// In en, this message translates to:
  /// **'Max active downloads'**
  String get maxActiveDownloads;

  /// No description provided for @downloadRateLimitKibS.
  ///
  /// In en, this message translates to:
  /// **'Download rate limit (KiB/s, 0 = unlimited)'**
  String get downloadRateLimitKibS;

  /// No description provided for @uploadRateLimitKibS.
  ///
  /// In en, this message translates to:
  /// **'Upload rate limit (KiB/s, 0 = unlimited)'**
  String get uploadRateLimitKibS;

  /// No description provided for @seedingRatioCapEG.
  ///
  /// In en, this message translates to:
  /// **'Seeding ratio cap (e.g. 1.50, 0 = unlimited)'**
  String get seedingRatioCapEG;

  /// No description provided for @allowSeedingAfterCompletion.
  ///
  /// In en, this message translates to:
  /// **'Allow seeding after completion'**
  String get allowSeedingAfterCompletion;

  /// No description provided for @disableAutoPauseTorrentsSoon.
  ///
  /// In en, this message translates to:
  /// **'Disable to auto-pause torrents as soon as download completes.'**
  String get disableAutoPauseTorrentsSoon;

  /// No description provided for @enableDht.
  ///
  /// In en, this message translates to:
  /// **'Enable DHT'**
  String get enableDht;

  /// No description provided for @enablePeerExchangePex.
  ///
  /// In en, this message translates to:
  /// **'Enable Peer Exchange (PEX)'**
  String get enablePeerExchangePex;

  /// No description provided for @enableLocalPeerDiscoveryLpd.
  ///
  /// In en, this message translates to:
  /// **'Enable Local Peer Discovery (LPD)'**
  String get enableLocalPeerDiscoveryLpd;

  /// No description provided for @enableProxy.
  ///
  /// In en, this message translates to:
  /// **'Enable proxy'**
  String get enableProxy;

  /// No description provided for @proxyHost.
  ///
  /// In en, this message translates to:
  /// **'Proxy host'**
  String get proxyHost;

  /// No description provided for @proxyPort.
  ///
  /// In en, this message translates to:
  /// **'Proxy port'**
  String get proxyPort;

  /// No description provided for @proxyUsername.
  ///
  /// In en, this message translates to:
  /// **'Proxy username'**
  String get proxyUsername;

  /// No description provided for @proxyPassword.
  ///
  /// In en, this message translates to:
  /// **'Proxy password'**
  String get proxyPassword;

  /// No description provided for @useProxyTrackers.
  ///
  /// In en, this message translates to:
  /// **'Use proxy for trackers'**
  String get useProxyTrackers;

  /// No description provided for @useProxyPeers.
  ///
  /// In en, this message translates to:
  /// **'Use proxy for peers'**
  String get useProxyPeers;

  /// No description provided for @proxyConnectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Proxy connection successful'**
  String get proxyConnectionSuccessful;

  /// No description provided for @proxyTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Proxy test failed'**
  String get proxyTestFailed;

  /// No description provided for @proxyTestFailed2.
  ///
  /// In en, this message translates to:
  /// **'Proxy test failed: {e}'**
  String proxyTestFailed2(Object e);

  /// No description provided for @testProxy.
  ///
  /// In en, this message translates to:
  /// **'Test proxy'**
  String get testProxy;

  /// No description provided for @socks5ProxySettingsSharedBy.
  ///
  /// In en, this message translates to:
  /// **'SOCKS5 proxy settings are shared by torrent tasks and yt-dlp downloads.'**
  String get socks5ProxySettingsSharedBy;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveConnectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Connection Settings'**
  String get saveConnectionSettings;

  /// No description provided for @enableAiCopilot.
  ///
  /// In en, this message translates to:
  /// **'Enable AI Copilot'**
  String get enableAiCopilot;

  /// No description provided for @enableSmartSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Enable smart suggestions'**
  String get enableSmartSuggestions;

  /// No description provided for @ollamaHostUrl.
  ///
  /// In en, this message translates to:
  /// **'Ollama Host URL'**
  String get ollamaHostUrl;

  /// No description provided for @recommendedModelDetectedLocalModels.
  ///
  /// In en, this message translates to:
  /// **'Recommended model: {kDefaultAiModel}\nDetected local models: {availableModelsCount}'**
  String recommendedModelDetectedLocalModels(
      Object kDefaultAiModel, Object availableModelsCount);

  /// No description provided for @modelUse.
  ///
  /// In en, this message translates to:
  /// **'Model to use'**
  String get modelUse;

  /// No description provided for @refreshAvailableModels.
  ///
  /// In en, this message translates to:
  /// **'Refresh available models'**
  String get refreshAvailableModels;

  /// No description provided for @downloadingRecommendedModel.
  ///
  /// In en, this message translates to:
  /// **'Downloading recommended model...'**
  String get downloadingRecommendedModel;

  /// No description provided for @downloadRecommendedModel.
  ///
  /// In en, this message translates to:
  /// **'Download Recommended Model'**
  String get downloadRecommendedModel;

  /// No description provided for @saveAiSettings.
  ///
  /// In en, this message translates to:
  /// **'Save AI Settings'**
  String get saveAiSettings;

  /// No description provided for @generalSettings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get generalSettings;

  /// No description provided for @generalAppSettingsCentralizedMain.
  ///
  /// In en, this message translates to:
  /// **'General app settings are centralized in the main app Settings tab. This screen now contains torrent-specific configuration only.'**
  String get generalAppSettingsCentralizedMain;

  /// No description provided for @aboutDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'About and Diagnostics'**
  String get aboutDiagnostics;

  /// No description provided for @vaultSpire.
  ///
  /// In en, this message translates to:
  /// **'Vault The Spire'**
  String get vaultSpire;

  /// No description provided for @torrentManagerAndroid.
  ///
  /// In en, this message translates to:
  /// **'Torrent manager for Android'**
  String get torrentManagerAndroid;

  /// No description provided for @torrentManagerBuiltAiCopilot.
  ///
  /// In en, this message translates to:
  /// **'Torrent manager with built-in AI copilot'**
  String get torrentManagerBuiltAiCopilot;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get appVersion;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @rateConvertSpireReborn.
  ///
  /// In en, this message translates to:
  /// **'Rate Convert The Spire Reborn'**
  String get rateConvertSpireReborn;

  /// No description provided for @leaveRatingPlayStore.
  ///
  /// In en, this message translates to:
  /// **'Leave a rating on the Play Store'**
  String get leaveRatingPlayStore;

  /// No description provided for @exportDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Export Diagnostics'**
  String get exportDiagnostics;

  /// No description provided for @clearBrowserHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Browser History'**
  String get clearBrowserHistory;

  /// No description provided for @lastDiagnosticsExportNever.
  ///
  /// In en, this message translates to:
  /// **'Last diagnostics export: never'**
  String get lastDiagnosticsExportNever;

  /// No description provided for @lastDiagnosticsExport.
  ///
  /// In en, this message translates to:
  /// **'Last diagnostics export: {lastDiagnosticsExport}'**
  String lastDiagnosticsExport(Object lastDiagnosticsExport);

  /// No description provided for @dataSafetyNoPersonalData.
  ///
  /// In en, this message translates to:
  /// **'Data Safety:\n- No personal data collection\n- No location data\n- No analytics; downloads and browsing stay on your device\n- Ads are served by Google AdMob, which uses your device advertising ID'**
  String get dataSafetyNoPersonalData;

  /// No description provided for @dataSafetyNoPersonalData2.
  ///
  /// In en, this message translates to:
  /// **'Data Safety:\n- No personal data collection\n- No location data\n- No identifiers shared\n- No advertising or analytics'**
  String get dataSafetyNoPersonalData2;

  /// No description provided for @localAiChatOllama.
  ///
  /// In en, this message translates to:
  /// **'Local AI Chat (Ollama)'**
  String get localAiChatOllama;

  /// No description provided for @refreshModelStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh model status'**
  String get refreshModelStatus;

  /// No description provided for @connectOllamaNetwork.
  ///
  /// In en, this message translates to:
  /// **'Connect to Ollama on your network'**
  String get connectOllamaNetwork;

  /// No description provided for @ollamaNeedsRunComputerSame.
  ///
  /// In en, this message translates to:
  /// **'Ollama needs to run on a computer on the same Wi-Fi network as this device. On that computer, expose Ollama to the network with:'**
  String get ollamaNeedsRunComputerSame;

  /// No description provided for @ollamaHost000.
  ///
  /// In en, this message translates to:
  /// **'OLLAMA_HOST=0.0.0.0 ollama serve'**
  String get ollamaHost000;

  /// No description provided for @thenEnterComputersIpAddress.
  ///
  /// In en, this message translates to:
  /// **'Then enter your computer\'s IP address below. Note: this only works on trusted local networks — Ollama has no built-in auth.'**
  String get thenEnterComputersIpAddress;

  /// No description provided for @ollamaUrl.
  ///
  /// In en, this message translates to:
  /// **'Ollama URL'**
  String get ollamaUrl;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @startLocal.
  ///
  /// In en, this message translates to:
  /// **'Start Local'**
  String get startLocal;

  /// No description provided for @installOllama.
  ///
  /// In en, this message translates to:
  /// **'Install Ollama'**
  String get installOllama;

  /// No description provided for @ollamaCliDetected.
  ///
  /// In en, this message translates to:
  /// **'Ollama CLI detected'**
  String get ollamaCliDetected;

  /// No description provided for @ollamaCliNotDetected.
  ///
  /// In en, this message translates to:
  /// **'Ollama CLI not detected'**
  String get ollamaCliNotDetected;

  /// No description provided for @modelRouting.
  ///
  /// In en, this message translates to:
  /// **'Model routing'**
  String get modelRouting;

  /// No description provided for @recommendedModel.
  ///
  /// In en, this message translates to:
  /// **'Recommended model: {kDefaultAiModel}'**
  String recommendedModel(Object kDefaultAiModel);

  /// No description provided for @activeModel.
  ///
  /// In en, this message translates to:
  /// **'Active model: {activeModel}'**
  String activeModel(Object activeModel);

  /// No description provided for @noLocalModelListReturned.
  ///
  /// In en, this message translates to:
  /// **'No local model list returned. The app will still try the recommended model.'**
  String get noLocalModelListReturned;

  /// No description provided for @detectedInstalledModelS.
  ///
  /// In en, this message translates to:
  /// **'Detected {modelsCount} installed model(s).'**
  String detectedInstalledModelS(Object modelsCount);

  /// No description provided for @selectModelUse.
  ///
  /// In en, this message translates to:
  /// **'Select model to use'**
  String get selectModelUse;

  /// No description provided for @askLocalModelAnything.
  ///
  /// In en, this message translates to:
  /// **'Ask your local model anything.'**
  String get askLocalModelAnything;

  /// No description provided for @typeMessageLocalAi.
  ///
  /// In en, this message translates to:
  /// **'Type a message to your local AI...'**
  String get typeMessageLocalAi;

  /// No description provided for @selectFiles.
  ///
  /// In en, this message translates to:
  /// **'Select files'**
  String get selectFiles;

  /// No description provided for @selectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select folder'**
  String get selectFolder;

  /// No description provided for @selectOutputFolder.
  ///
  /// In en, this message translates to:
  /// **'Select output folder'**
  String get selectOutputFolder;

  /// No description provided for @torrentNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Torrent name is required.'**
  String get torrentNameRequired;

  /// No description provided for @selectFilesFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Select files or a folder first.'**
  String get selectFilesFolderFirst;

  /// No description provided for @outputLocationRequired.
  ///
  /// In en, this message translates to:
  /// **'Output location is required.'**
  String get outputLocationRequired;

  /// No description provided for @torrentCreated.
  ///
  /// In en, this message translates to:
  /// **'Torrent Created'**
  String get torrentCreated;

  /// No description provided for @savedAddDownloadsNow.
  ///
  /// In en, this message translates to:
  /// **'Saved to:\n{torrentPath}\n\nAdd to downloads now?'**
  String savedAddDownloadsNow(Object torrentPath);

  /// No description provided for @torrentFileCreatedButFailed.
  ///
  /// In en, this message translates to:
  /// **'Torrent file created, but failed to add to downloads: {e}'**
  String torrentFileCreatedButFailed(Object e);

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'Created {torrentPath}'**
  String created(Object torrentPath);

  /// No description provided for @failedCreateTorrent.
  ///
  /// In en, this message translates to:
  /// **'Failed to create torrent: {e}'**
  String failedCreateTorrent(Object e);

  /// No description provided for @createTorrent.
  ///
  /// In en, this message translates to:
  /// **'Create Torrent'**
  String get createTorrent;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add Files'**
  String get addFiles;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get addFolder;

  /// No description provided for @totalSize.
  ///
  /// In en, this message translates to:
  /// **'Total size: {size}'**
  String totalSize(Object size);

  /// No description provided for @torrentName.
  ///
  /// In en, this message translates to:
  /// **'Torrent Name'**
  String get torrentName;

  /// No description provided for @trackersOnePerLine.
  ///
  /// In en, this message translates to:
  /// **'Trackers (one per line)'**
  String get trackersOnePerLine;

  /// No description provided for @pieceSize.
  ///
  /// In en, this message translates to:
  /// **'Piece Size'**
  String get pieceSize;

  /// No description provided for @commentOptional.
  ///
  /// In en, this message translates to:
  /// **'Comment (optional)'**
  String get commentOptional;

  /// No description provided for @privateTorrent.
  ///
  /// In en, this message translates to:
  /// **'Private Torrent'**
  String get privateTorrent;

  /// No description provided for @disablesDhtPexPrivateTrackers.
  ///
  /// In en, this message translates to:
  /// **'Disables DHT and PEX for private trackers'**
  String get disablesDhtPexPrivateTrackers;

  /// No description provided for @outputLocation.
  ///
  /// In en, this message translates to:
  /// **'Output Location'**
  String get outputLocation;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @creating.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get creating;

  /// No description provided for @fastPrivateBittorrentClientDownloading.
  ///
  /// In en, this message translates to:
  /// **'A fast, private BitTorrent client for downloading freely distributed files - open-source software, Creative Commons media, public domain content, and files you own the rights to.'**
  String get fastPrivateBittorrentClientDownloading;

  /// No description provided for @openSource.
  ///
  /// In en, this message translates to:
  /// **'Open Source'**
  String get openSource;

  /// No description provided for @noAds.
  ///
  /// In en, this message translates to:
  /// **'No Ads'**
  String get noAds;

  /// No description provided for @legalUseOnly.
  ///
  /// In en, this message translates to:
  /// **'Legal Use Only'**
  String get legalUseOnly;

  /// No description provided for @gettingStarted.
  ///
  /// In en, this message translates to:
  /// **'Getting Started'**
  String get gettingStarted;

  /// No description provided for @understandingDownloadProgress.
  ///
  /// In en, this message translates to:
  /// **'Understanding Download Progress'**
  String get understandingDownloadProgress;

  /// No description provided for @verifyingRedownloading.
  ///
  /// In en, this message translates to:
  /// **'Verifying & Redownloading'**
  String get verifyingRedownloading;

  /// No description provided for @privacyData.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Your Data'**
  String get privacyData;

  /// No description provided for @androidTips.
  ///
  /// In en, this message translates to:
  /// **'Android Tips'**
  String get androidTips;

  /// No description provided for @desktopTips.
  ///
  /// In en, this message translates to:
  /// **'Desktop Tips'**
  String get desktopTips;

  /// No description provided for @proTipSeedRatioMatters.
  ///
  /// In en, this message translates to:
  /// **'Pro tip: Seed ratio matters. Keeping a torrent seeding after download helps other users get the same file. A ratio of 1.0 means you\'ve shared back as much as you downloaded.'**
  String get proTipSeedRatioMatters;

  /// No description provided for @proTipBittorrentProtocolPeer.
  ///
  /// In en, this message translates to:
  /// **'Pro tip: The BitTorrent protocol is peer-to-peer - every downloader also uploads to others. Leaving seeding on after your download benefits the whole community and keeps rare files alive.'**
  String get proTipBittorrentProtocolPeer;

  /// No description provided for @copyMagnetLink.
  ///
  /// In en, this message translates to:
  /// **'Copy magnet link'**
  String get copyMagnetLink;

  /// No description provided for @magnetLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Magnet link copied'**
  String get magnetLinkCopied;

  /// No description provided for @shared.
  ///
  /// In en, this message translates to:
  /// **'Shared: {view}'**
  String shared(Object view);

  /// No description provided for @forceRefresh.
  ///
  /// In en, this message translates to:
  /// **'Force refresh'**
  String get forceRefresh;

  /// No description provided for @connectionRefreshTriggered.
  ///
  /// In en, this message translates to:
  /// **'Connection refresh triggered'**
  String get connectionRefreshTriggered;

  /// No description provided for @forceReannounce.
  ///
  /// In en, this message translates to:
  /// **'Force reannounce'**
  String get forceReannounce;

  /// No description provided for @trackerReannounceTriggered.
  ///
  /// In en, this message translates to:
  /// **'Tracker reannounce triggered'**
  String get trackerReannounceTriggered;

  /// No description provided for @reannounceFailed.
  ///
  /// In en, this message translates to:
  /// **'Reannounce failed: {e}'**
  String reannounceFailed(Object e);

  /// No description provided for @forceDhtRefresh.
  ///
  /// In en, this message translates to:
  /// **'Force DHT refresh'**
  String get forceDhtRefresh;

  /// No description provided for @dhtRefreshTriggered.
  ///
  /// In en, this message translates to:
  /// **'DHT refresh triggered'**
  String get dhtRefreshTriggered;

  /// No description provided for @dhtRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'DHT refresh failed: {e}'**
  String dhtRefreshFailed(Object e);

  /// No description provided for @retryMetadataNow.
  ///
  /// In en, this message translates to:
  /// **'Retry metadata now'**
  String get retryMetadataNow;

  /// No description provided for @metadataRetryQueued.
  ///
  /// In en, this message translates to:
  /// **'Metadata retry queued'**
  String get metadataRetryQueued;

  /// No description provided for @redownload.
  ///
  /// In en, this message translates to:
  /// **'Redownload'**
  String get redownload;

  /// No description provided for @copyLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get copyLogs;

  /// No description provided for @logsCopiedClipboard.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopiedClipboard;

  /// No description provided for @verifyFiles.
  ///
  /// In en, this message translates to:
  /// **'Verify files'**
  String get verifyFiles;

  /// No description provided for @verifyingFilesDiskMayTake.
  ///
  /// In en, this message translates to:
  /// **'Verifying files on disk  -  this may take a moment…'**
  String get verifyingFilesDiskMayTake;

  /// No description provided for @verificationComplete.
  ///
  /// In en, this message translates to:
  /// **'Verification complete.'**
  String get verificationComplete;

  /// No description provided for @verifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Verify failed: {e}'**
  String verifyFailed(Object e);

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @totalSize2.
  ///
  /// In en, this message translates to:
  /// **'Total size'**
  String get totalSize2;

  /// No description provided for @uploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploaded;

  /// No description provided for @pieces.
  ///
  /// In en, this message translates to:
  /// **'Pieces'**
  String get pieces;

  /// No description provided for @seeders.
  ///
  /// In en, this message translates to:
  /// **'Seeders'**
  String get seeders;

  /// No description provided for @leechers.
  ///
  /// In en, this message translates to:
  /// **'Leechers'**
  String get leechers;

  /// No description provided for @lastAnnounce.
  ///
  /// In en, this message translates to:
  /// **'Last announce'**
  String get lastAnnounce;

  /// No description provided for @metadataRetry.
  ///
  /// In en, this message translates to:
  /// **'Metadata retry'**
  String get metadataRetry;

  /// No description provided for @savePath.
  ///
  /// In en, this message translates to:
  /// **'Save path'**
  String get savePath;

  /// No description provided for @infoHash.
  ///
  /// In en, this message translates to:
  /// **'Info hash'**
  String get infoHash;

  /// No description provided for @redownloadFromScratch.
  ///
  /// In en, this message translates to:
  /// **'Redownload from scratch?'**
  String get redownloadFromScratch;

  /// No description provided for @willDeletedFromDiskDownloaded.
  ///
  /// In en, this message translates to:
  /// **'\"{torrentName}\" will be deleted from disk and downloaded again from 0%. The .torrent source file is kept.'**
  String willDeletedFromDiskDownloaded(Object torrentName);

  /// No description provided for @redownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Redownload started'**
  String get redownloadStarted;

  /// No description provided for @failed2.
  ///
  /// In en, this message translates to:
  /// **'Failed: {e}'**
  String failed2(Object e);

  /// No description provided for @downloadFolderNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'Download folder \"{folder}\" no longer exists.'**
  String downloadFolderNoLongerExists(Object folder);

  /// No description provided for @cannotAccessDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Cannot access download folder: {e}'**
  String cannotAccessDownloadFolder(Object e);

  /// No description provided for @setDownloadFolder2.
  ///
  /// In en, this message translates to:
  /// **'Set Download Folder'**
  String get setDownloadFolder2;

  /// No description provided for @mustSetDownloadFolderBefore.
  ///
  /// In en, this message translates to:
  /// **'You must set a download folder before adding torrents. This prevents downloads from being stored in inaccessible app storage. Please go to Settings > Download Location and select a folder on external storage.'**
  String get mustSetDownloadFolderBefore;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @unableToggle.
  ///
  /// In en, this message translates to:
  /// **'Unable to toggle: {e}'**
  String unableToggle(Object e);

  /// No description provided for @willDeletedFromDiskDownloaded2.
  ///
  /// In en, this message translates to:
  /// **'\"{modelName}\" will be deleted from disk and downloaded again from 0%. The .torrent source file is preserved.'**
  String willDeletedFromDiskDownloaded2(Object modelName);

  /// No description provided for @restartedFromScratch.
  ///
  /// In en, this message translates to:
  /// **'\"{tsName}\" restarted from scratch.'**
  String restartedFromScratch(Object tsName);

  /// No description provided for @redownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Redownload failed: {e}'**
  String redownloadFailed(Object e);

  /// No description provided for @removeTorrent.
  ///
  /// In en, this message translates to:
  /// **'Remove torrent?'**
  String get removeTorrent;

  /// No description provided for @willRemovedFromList.
  ///
  /// In en, this message translates to:
  /// **'\"{tsName}\" will be removed from the list.'**
  String willRemovedFromList(Object tsName);

  /// No description provided for @alsoDeleteDownloadedFiles.
  ///
  /// In en, this message translates to:
  /// **'Also delete downloaded files'**
  String get alsoDeleteDownloadedFiles;

  /// No description provided for @removeDeleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Remove + Delete files'**
  String get removeDeleteFiles;

  /// No description provided for @torrentRemovedFilesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Torrent removed and files deleted.'**
  String get torrentRemovedFilesDeleted;

  /// No description provided for @torrentRemoved.
  ///
  /// In en, this message translates to:
  /// **'Torrent removed.'**
  String get torrentRemoved;

  /// No description provided for @removeFailed.
  ///
  /// In en, this message translates to:
  /// **'Remove failed: {e}'**
  String removeFailed(Object e);

  /// No description provided for @noDownloadFolderConfigured.
  ///
  /// In en, this message translates to:
  /// **'No download folder configured.'**
  String get noDownloadFolderConfigured;

  /// No description provided for @folderDoesNotExist.
  ///
  /// In en, this message translates to:
  /// **'Folder does not exist.'**
  String get folderDoesNotExist;

  /// No description provided for @unableOpenFolderAutomaticallyFiles2.
  ///
  /// In en, this message translates to:
  /// **'Unable to open folder automatically. Files saved to:\n{directoryPath}'**
  String unableOpenFolderAutomaticallyFiles2(Object directoryPath);

  /// No description provided for @failedOpenFolder2.
  ///
  /// In en, this message translates to:
  /// **'Failed to open folder: {directoryPath}'**
  String failedOpenFolder2(Object directoryPath);

  /// No description provided for @selectTorrentFile.
  ///
  /// In en, this message translates to:
  /// **'Select torrent file'**
  String get selectTorrentFile;

  /// No description provided for @torrentAddedFromFile.
  ///
  /// In en, this message translates to:
  /// **'Torrent added from file.'**
  String get torrentAddedFromFile;

  /// No description provided for @failedAddTorrentFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to add torrent file: {e}'**
  String failedAddTorrentFile(Object e);

  /// No description provided for @torrentAddedViaDragDrop.
  ///
  /// In en, this message translates to:
  /// **'Torrent added via drag & drop.'**
  String get torrentAddedViaDragDrop;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {e}'**
  String importFailed(Object e);

  /// No description provided for @addTorrent.
  ///
  /// In en, this message translates to:
  /// **'Add torrent'**
  String get addTorrent;

  /// No description provided for @pasteMagnetLinkMagnetXt.
  ///
  /// In en, this message translates to:
  /// **'Paste magnet link (magnet:?xt=...)'**
  String get pasteMagnetLinkMagnetXt;

  /// No description provided for @torrentAdded.
  ///
  /// In en, this message translates to:
  /// **'Torrent added!'**
  String get torrentAdded;

  /// No description provided for @torrentAlreadyList.
  ///
  /// In en, this message translates to:
  /// **'This torrent is already in your list.'**
  String get torrentAlreadyList;

  /// No description provided for @failedAdd.
  ///
  /// In en, this message translates to:
  /// **'Failed to add: {e}'**
  String failedAdd(Object e);

  /// No description provided for @addCreateTorrent.
  ///
  /// In en, this message translates to:
  /// **'Add or create torrent'**
  String get addCreateTorrent;

  /// No description provided for @addMagnetLink.
  ///
  /// In en, this message translates to:
  /// **'Add magnet link'**
  String get addMagnetLink;

  /// No description provided for @addTorrentFile.
  ///
  /// In en, this message translates to:
  /// **'Add .torrent file'**
  String get addTorrentFile;

  /// No description provided for @createTorrent2.
  ///
  /// In en, this message translates to:
  /// **'Create torrent'**
  String get createTorrent2;

  /// No description provided for @pickTorrentFile.
  ///
  /// In en, this message translates to:
  /// **'Pick .torrent file'**
  String get pickTorrentFile;

  /// No description provided for @pasteMagnet.
  ///
  /// In en, this message translates to:
  /// **'Paste magnet'**
  String get pasteMagnet;

  /// No description provided for @closeActions.
  ///
  /// In en, this message translates to:
  /// **'Close actions'**
  String get closeActions;

  /// No description provided for @searchTorrents.
  ///
  /// In en, this message translates to:
  /// **'Search torrents…'**
  String get searchTorrents;

  /// No description provided for @cancelSearch.
  ///
  /// In en, this message translates to:
  /// **'Cancel search'**
  String get cancelSearch;

  /// No description provided for @searchTorrents2.
  ///
  /// In en, this message translates to:
  /// **'Search torrents'**
  String get searchTorrents2;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @openDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Open download folder'**
  String get openDownloadFolder;

  /// No description provided for @noTorrentsYet.
  ///
  /// In en, this message translates to:
  /// **'No torrents yet'**
  String get noTorrentsYet;

  /// No description provided for @setDownloadFolderFirst.
  ///
  /// In en, this message translates to:
  /// **'Set Download Folder First'**
  String get setDownloadFolderFirst;

  /// No description provided for @goSettingsDownloadLocationChoose.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings > Download Location and choose a folder on external storage to prevent file corruption from inaccessible app storage.'**
  String get goSettingsDownloadLocationChoose;

  /// No description provided for @addMagnet.
  ///
  /// In en, this message translates to:
  /// **'Add Magnet'**
  String get addMagnet;

  /// No description provided for @addTorrentFile2.
  ///
  /// In en, this message translates to:
  /// **'Add .torrent File'**
  String get addTorrentFile2;

  /// No description provided for @visitQuizSpire.
  ///
  /// In en, this message translates to:
  /// **'Visit Quiz the Spire'**
  String get visitQuizSpire;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{searchQuery}\"'**
  String noResults(Object searchQuery);

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @noMagnetLinkAvailable.
  ///
  /// In en, this message translates to:
  /// **'No magnet link available'**
  String get noMagnetLinkAvailable;

  /// No description provided for @copyFilePath.
  ///
  /// In en, this message translates to:
  /// **'Copy file path'**
  String get copyFilePath;

  /// No description provided for @filePathCopied.
  ///
  /// In en, this message translates to:
  /// **'File path copied'**
  String get filePathCopied;

  /// No description provided for @redownloadFromScratch2.
  ///
  /// In en, this message translates to:
  /// **'Redownload from scratch'**
  String get redownloadFromScratch2;

  /// No description provided for @mustSetDownloadFolderBefore2.
  ///
  /// In en, this message translates to:
  /// **'You must set a download folder before downloading torrents. This prevents downloads from being stored in inaccessible app storage and causing file corruption. Please navigate to Settings and select a folder on external storage.'**
  String get mustSetDownloadFolderBefore2;

  /// No description provided for @couldntFetchTorrentInfoYet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t fetch torrent info yet - no peers responded. Added to queue and will retry metadata automatically.'**
  String get couldntFetchTorrentInfoYet;

  /// No description provided for @resolvingMetadataTimedOutAfter.
  ///
  /// In en, this message translates to:
  /// **'Resolving metadata timed out after 30 seconds. Please retry.'**
  String get resolvingMetadataTimedOutAfter;

  /// No description provided for @aiCopilotDisabledSettings.
  ///
  /// In en, this message translates to:
  /// **'AI Copilot is disabled in Settings.'**
  String get aiCopilotDisabledSettings;

  /// No description provided for @vaultSpireAi.
  ///
  /// In en, this message translates to:
  /// **'Vault The Spire AI'**
  String get vaultSpireAi;

  /// No description provided for @focusMode.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get focusMode;

  /// No description provided for @chatMode.
  ///
  /// In en, this message translates to:
  /// **'Chat mode'**
  String get chatMode;

  /// No description provided for @resolvingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Resolving metadata...'**
  String get resolvingMetadata;

  /// No description provided for @pasteMagnetLink.
  ///
  /// In en, this message translates to:
  /// **'Paste magnet link'**
  String get pasteMagnetLink;

  /// No description provided for @noActiveTorrentsYetAdd.
  ///
  /// In en, this message translates to:
  /// **'No active torrents yet. Add a magnet link or start one from search.'**
  String get noActiveTorrentsYetAdd;

  /// No description provided for @downloadQueue.
  ///
  /// In en, this message translates to:
  /// **'Download queue'**
  String get downloadQueue;

  /// No description provided for @peers.
  ///
  /// In en, this message translates to:
  /// **'{statusLabel} • {peers} peers'**
  String peers(Object statusLabel, Object peers);

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get searchResults;

  /// No description provided for @aiInfoCard.
  ///
  /// In en, this message translates to:
  /// **'AI Info Card'**
  String get aiInfoCard;

  /// No description provided for @tellMeMore.
  ///
  /// In en, this message translates to:
  /// **'Tell me more'**
  String get tellMeMore;

  /// No description provided for @aiReady.
  ///
  /// In en, this message translates to:
  /// **'AI Ready'**
  String get aiReady;

  /// No description provided for @aiCopilotOfflineCheckOllama.
  ///
  /// In en, this message translates to:
  /// **'AI copilot offline  -  check your Ollama connection in Settings'**
  String get aiCopilotOfflineCheckOllama;

  /// No description provided for @aiCopilotDisabledSettings2.
  ///
  /// In en, this message translates to:
  /// **'AI Copilot disabled in Settings'**
  String get aiCopilotDisabledSettings2;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessage;

  /// No description provided for @copilot.
  ///
  /// In en, this message translates to:
  /// **'Copilot'**
  String get copilot;

  /// No description provided for @aiChat.
  ///
  /// In en, this message translates to:
  /// **'AI Chat'**
  String get aiChat;

  /// No description provided for @detailsCopiedClipboard.
  ///
  /// In en, this message translates to:
  /// **'Details copied to clipboard'**
  String get detailsCopiedClipboard;

  /// No description provided for @somethingBrokeHere.
  ///
  /// In en, this message translates to:
  /// **'Something broke here'**
  String get somethingBrokeHere;

  /// No description provided for @copyDetails.
  ///
  /// In en, this message translates to:
  /// **'Copy details'**
  String get copyDetails;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report this'**
  String get report;

  /// No description provided for @toggleQueuePanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle queue panel'**
  String get toggleQueuePanel;

  /// No description provided for @openQueue.
  ///
  /// In en, this message translates to:
  /// **'Open queue'**
  String get openQueue;

  /// No description provided for @expandPlayer.
  ///
  /// In en, this message translates to:
  /// **'Expand player'**
  String get expandPlayer;

  /// No description provided for @collapsePlayer.
  ///
  /// In en, this message translates to:
  /// **'Collapse player'**
  String get collapsePlayer;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @back10s.
  ///
  /// In en, this message translates to:
  /// **'Back 10s'**
  String get back10s;

  /// No description provided for @forward10s.
  ///
  /// In en, this message translates to:
  /// **'Forward 10s'**
  String get forward10s;

  /// No description provided for @searchPagesEnterWebAddress.
  ///
  /// In en, this message translates to:
  /// **'Search pages or enter web address...'**
  String get searchPagesEnterWebAddress;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open {normalized}'**
  String open(Object normalized);

  /// No description provided for @navigateDirectlySite.
  ///
  /// In en, this message translates to:
  /// **'Navigate directly to the site'**
  String get navigateDirectlySite;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search {searchEngine} for \"{trimmed}\"'**
  String search(Object searchEngine, Object trimmed);

  /// No description provided for @plainTextFallsBackSearch.
  ///
  /// In en, this message translates to:
  /// **'Plain text falls back to search'**
  String get plainTextFallsBackSearch;

  /// No description provided for @deleteFile3.
  ///
  /// In en, this message translates to:
  /// **'Delete this file?'**
  String get deleteFile3;

  /// No description provided for @willPermanentlyDeleteFileFrom.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the file from your device. This can\'t be undone.'**
  String get willPermanentlyDeleteFileFrom;

  /// No description provided for @searchDownloads.
  ///
  /// In en, this message translates to:
  /// **'Search downloads…'**
  String get searchDownloads;

  /// No description provided for @allProtocols.
  ///
  /// In en, this message translates to:
  /// **'All protocols'**
  String get allProtocols;

  /// No description provided for @directHttp.
  ///
  /// In en, this message translates to:
  /// **'Direct HTTP'**
  String get directHttp;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get allStatuses;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @allCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get allCategories;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @appUpdates.
  ///
  /// In en, this message translates to:
  /// **'App updates'**
  String get appUpdates;

  /// No description provided for @archives.
  ///
  /// In en, this message translates to:
  /// **'Archives'**
  String get archives;

  /// No description provided for @noMediaYet.
  ///
  /// In en, this message translates to:
  /// **'No media yet'**
  String get noMediaYet;

  /// No description provided for @scanLibrary.
  ///
  /// In en, this message translates to:
  /// **'Scan library'**
  String get scanLibrary;

  /// No description provided for @pasteUrlFirst.
  ///
  /// In en, this message translates to:
  /// **'Paste a URL first.'**
  String get pasteUrlFirst;

  /// No description provided for @queuedTracksDownload.
  ///
  /// In en, this message translates to:
  /// **'Queued {selectedCount} tracks for download'**
  String queuedTracksDownload(Object selectedCount);

  /// No description provided for @queuedDownload.
  ///
  /// In en, this message translates to:
  /// **'Queued for download'**
  String get queuedDownload;

  /// No description provided for @downloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Download started'**
  String get downloadStarted;

  /// No description provided for @couldNotFetchVideoInfo.
  ///
  /// In en, this message translates to:
  /// **'Could not fetch video info.'**
  String get couldNotFetchVideoInfo;

  /// No description provided for @quickDownload.
  ///
  /// In en, this message translates to:
  /// **'Quick Download'**
  String get quickDownload;

  /// No description provided for @pasteUrl.
  ///
  /// In en, this message translates to:
  /// **'Paste URL'**
  String get pasteUrl;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @best.
  ///
  /// In en, this message translates to:
  /// **'Best'**
  String get best;

  /// No description provided for @enterVideoPlaylistUrlPreview.
  ///
  /// In en, this message translates to:
  /// **'Enter a video or playlist URL to preview it and add to the download queue.'**
  String get enterVideoPlaylistUrlPreview;

  /// No description provided for @selectTracksDownload.
  ///
  /// In en, this message translates to:
  /// **'Select tracks to download'**
  String get selectTracksDownload;

  /// No description provided for @downloadSelected2.
  ///
  /// In en, this message translates to:
  /// **'Download Selected'**
  String get downloadSelected2;

  /// No description provided for @format3.
  ///
  /// In en, this message translates to:
  /// **'Format: {format}'**
  String format3(Object format);

  /// No description provided for @quality2.
  ///
  /// In en, this message translates to:
  /// **'Quality: {quality}'**
  String quality2(Object quality);

  /// No description provided for @fetchingEstimatedSize.
  ///
  /// In en, this message translates to:
  /// **'Fetching estimated size...'**
  String get fetchingEstimatedSize;

  /// No description provided for @estimatedSize.
  ///
  /// In en, this message translates to:
  /// **'Estimated size: {estimatedSize}'**
  String estimatedSize(Object estimatedSize);

  /// No description provided for @downloadWillEnqueuedUsingSettings.
  ///
  /// In en, this message translates to:
  /// **'The download will be enqueued using your settings (quality, destination, etc.).'**
  String get downloadWillEnqueuedUsingSettings;

  /// No description provided for @pasteVideoPlaylistUrlBelow.
  ///
  /// In en, this message translates to:
  /// **'Paste a video or playlist URL below to start downloading.'**
  String get pasteVideoPlaylistUrlBelow;

  /// No description provided for @androidPleaseSelectDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Android: please select your download folder once so permissions remain valid.'**
  String get androidPleaseSelectDownloadFolder;

  /// No description provided for @downloadFolderBecameUnreachablePlease.
  ///
  /// In en, this message translates to:
  /// **'Download folder became unreachable, please pick it again.'**
  String get downloadFolderBecameUnreachablePlease;

  /// No description provided for @choose.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get choose;

  /// No description provided for @checkingEngine.
  ///
  /// In en, this message translates to:
  /// **'Checking engine...'**
  String get checkingEngine;

  /// No description provided for @engineCheckInterruptedRetrying.
  ///
  /// In en, this message translates to:
  /// **'Engine check interrupted — retrying...'**
  String get engineCheckInterruptedRetrying;

  /// No description provided for @ytDlpNotAvailableClick.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp not available (click Settings)'**
  String get ytDlpNotAvailableClick;

  /// No description provided for @downloadFromYoutubeUrl.
  ///
  /// In en, this message translates to:
  /// **'Download from YouTube URL'**
  String get downloadFromYoutubeUrl;

  /// No description provided for @searchYoutubeSoundcloud.
  ///
  /// In en, this message translates to:
  /// **'Search YouTube & SoundCloud'**
  String get searchYoutubeSoundcloud;

  /// No description provided for @appWebBrowser.
  ///
  /// In en, this message translates to:
  /// **'In-app web browser'**
  String get appWebBrowser;

  /// No description provided for @youtubePlaylistsFolders.
  ///
  /// In en, this message translates to:
  /// **'YouTube playlists & folders'**
  String get youtubePlaylistsFolders;

  /// No description provided for @importTrackLists.
  ///
  /// In en, this message translates to:
  /// **'Import track lists'**
  String get importTrackLists;

  /// No description provided for @downloadStatistics.
  ///
  /// In en, this message translates to:
  /// **'Download statistics'**
  String get downloadStatistics;

  /// No description provided for @appConfiguration.
  ///
  /// In en, this message translates to:
  /// **'App configuration'**
  String get appConfiguration;

  /// No description provided for @supportViaDonations.
  ///
  /// In en, this message translates to:
  /// **'Support via donations'**
  String get supportViaDonations;

  /// No description provided for @leaveReview.
  ///
  /// In en, this message translates to:
  /// **'Leave a review'**
  String get leaveReview;

  /// No description provided for @convertAudioVideoFiles.
  ///
  /// In en, this message translates to:
  /// **'Convert audio/video files'**
  String get convertAudioVideoFiles;

  /// No description provided for @activityLogViewer.
  ///
  /// In en, this message translates to:
  /// **'Activity log viewer'**
  String get activityLogViewer;

  /// No description provided for @helpDocumentation.
  ///
  /// In en, this message translates to:
  /// **'Help & documentation'**
  String get helpDocumentation;

  /// No description provided for @mediaPlayerLibrary.
  ///
  /// In en, this message translates to:
  /// **'Media player & library'**
  String get mediaPlayerLibrary;

  /// No description provided for @vaultTorrentManager.
  ///
  /// In en, this message translates to:
  /// **'Vault torrent manager'**
  String get vaultTorrentManager;

  /// No description provided for @mac.
  ///
  /// In en, this message translates to:
  /// **'Mac'**
  String get mac;

  /// No description provided for @root.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get root;

  /// No description provided for @useFolder.
  ///
  /// In en, this message translates to:
  /// **'Use this folder'**
  String get useFolder;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @vAvailable.
  ///
  /// In en, this message translates to:
  /// **'v{latestVersion} available'**
  String vAvailable(Object latestVersion);

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @downloadWhat.
  ///
  /// In en, this message translates to:
  /// **'Download what?'**
  String get downloadWhat;

  /// No description provided for @videoPlayingFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'This video is playing from a playlist.'**
  String get videoPlayingFromPlaylist;

  /// No description provided for @justVideo.
  ///
  /// In en, this message translates to:
  /// **'Just this video'**
  String get justVideo;

  /// No description provided for @wholePlaylist.
  ///
  /// In en, this message translates to:
  /// **'The whole playlist'**
  String get wholePlaylist;

  /// No description provided for @seeWhichSongsAlreadyHave.
  ///
  /// In en, this message translates to:
  /// **'See which songs you already have, then get the rest'**
  String get seeWhichSongsAlreadyHave;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What’s new in {version}'**
  String whatsNew(Object version);

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(Object version);

  /// No description provided for @got.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get got;

  /// No description provided for @addonDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode for every site'**
  String get addonDarkMode;

  /// No description provided for @addonYoutubeDislikes.
  ///
  /// In en, this message translates to:
  /// **'See YouTube dislikes again'**
  String get addonYoutubeDislikes;

  /// No description provided for @addonSponsorBlock.
  ///
  /// In en, this message translates to:
  /// **'Skip sponsor segments on YouTube'**
  String get addonSponsorBlock;

  /// No description provided for @addonYoutubeTweaks.
  ///
  /// In en, this message translates to:
  /// **'YouTube tweaks and cleanups'**
  String get addonYoutubeTweaks;

  /// No description provided for @addonTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate pages'**
  String get addonTranslate;

  /// No description provided for @addonReddit.
  ///
  /// In en, this message translates to:
  /// **'Cleaner Reddit'**
  String get addonReddit;

  /// No description provided for @revealed.
  ///
  /// In en, this message translates to:
  /// **'Revealed {rewardIndex} of {rewardsCount}'**
  String revealed(Object rewardIndex, Object rewardsCount);

  /// No description provided for @pull.
  ///
  /// In en, this message translates to:
  /// **'Pull {rewardIndex} of {rewardsCount}'**
  String pull(Object rewardIndex, Object rewardsCount);

  /// No description provided for @loadingPrice.
  ///
  /// In en, this message translates to:
  /// **'Loading price…'**
  String get loadingPrice;

  /// No description provided for @newTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get newTab;

  /// No description provided for @hlsStream.
  ///
  /// In en, this message translates to:
  /// **'HLS Stream'**
  String get hlsStream;

  /// No description provided for @dashStream.
  ///
  /// In en, this message translates to:
  /// **'DASH Stream'**
  String get dashStream;

  /// No description provided for @mp4Video2.
  ///
  /// In en, this message translates to:
  /// **'MP4 Video'**
  String get mp4Video2;

  /// No description provided for @webmVideo2.
  ///
  /// In en, this message translates to:
  /// **'WebM Video'**
  String get webmVideo2;

  /// No description provided for @mkvVideo2.
  ///
  /// In en, this message translates to:
  /// **'MKV Video'**
  String get mkvVideo2;

  /// No description provided for @videoStream.
  ///
  /// In en, this message translates to:
  /// **'Video Stream'**
  String get videoStream;

  /// No description provided for @couldNotOpenPage.
  ///
  /// In en, this message translates to:
  /// **'Could not open this page: {e}'**
  String couldNotOpenPage(Object e);

  /// No description provided for @extensionsUnavailableSessionAnotherCopy.
  ///
  /// In en, this message translates to:
  /// **'Extensions are unavailable in this session: another copy of the app had the browser open first. Close every copy and start the app again.'**
  String get extensionsUnavailableSessionAnotherCopy;

  /// No description provided for @extensionLabel.
  ///
  /// In en, this message translates to:
  /// **'this extension'**
  String get extensionLabel;

  /// No description provided for @firefoxExtensionsRunHereWhen.
  ///
  /// In en, this message translates to:
  /// **'Firefox extensions run here when they also support Chromium. The app checks after downloading and tells you if not.'**
  String get firefoxExtensionsRunHereWhen;

  /// No description provided for @more3.
  ///
  /// In en, this message translates to:
  /// **' and more'**
  String get more3;

  /// No description provided for @installedFromFile.
  ///
  /// In en, this message translates to:
  /// **'installed from a file'**
  String get installedFromFile;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @mAgo.
  ///
  /// In en, this message translates to:
  /// **'{inMinutes}m ago'**
  String mAgo(Object inMinutes);

  /// No description provided for @hAgo.
  ///
  /// In en, this message translates to:
  /// **'{inHours}h ago'**
  String hAgo(Object inHours);

  /// No description provided for @dAgo.
  ///
  /// In en, this message translates to:
  /// **'{inDays}d ago'**
  String dAgo(Object inDays);

  /// No description provided for @more4.
  ///
  /// In en, this message translates to:
  /// **' +{targets} more'**
  String more4(Object targets);

  /// No description provided for @anotherApp.
  ///
  /// In en, this message translates to:
  /// **'another app'**
  String get anotherApp;

  /// No description provided for @windows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get windows;

  /// No description provided for @fullSupport.
  ///
  /// In en, this message translates to:
  /// **'Full support'**
  String get fullSupport;

  /// No description provided for @android.
  ///
  /// In en, this message translates to:
  /// **'Android'**
  String get android;

  /// No description provided for @linux.
  ///
  /// In en, this message translates to:
  /// **'Linux'**
  String get linux;

  /// No description provided for @discontinued.
  ///
  /// In en, this message translates to:
  /// **'Discontinued'**
  String get discontinued;

  /// No description provided for @macosIos.
  ///
  /// In en, this message translates to:
  /// **'macOS / iOS'**
  String get macosIos;

  /// No description provided for @untested.
  ///
  /// In en, this message translates to:
  /// **'Untested'**
  String get untested;

  /// No description provided for @web.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get web;

  /// No description provided for @notSupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get notSupported;

  /// No description provided for @vault.
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get vault;

  /// No description provided for @macos.
  ///
  /// In en, this message translates to:
  /// **'macOS'**
  String get macos;

  /// No description provided for @ios.
  ///
  /// In en, this message translates to:
  /// **'iOS'**
  String get ios;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @ytDlpCouldNotCheck.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp {versionText} - Could not check for updates'**
  String ytDlpCouldNotCheck(Object versionText);

  /// No description provided for @ytDlpCheckingUpdates.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp {versionText} - Checking for updates...'**
  String ytDlpCheckingUpdates(Object versionText);

  /// No description provided for @ytDlpUpDate.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp {versionText} - Up to date'**
  String ytDlpUpDate(Object versionText);

  /// No description provided for @lastChecked.
  ///
  /// In en, this message translates to:
  /// **'Last checked: {ytDlpLastChecked}'**
  String lastChecked(Object ytDlpLastChecked);

  /// No description provided for @fetchingPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Fetching playlist…'**
  String get fetchingPlaylist;

  /// No description provided for @scanningFolderMatching.
  ///
  /// In en, this message translates to:
  /// **'Scanning folder & matching…'**
  String get scanningFolderMatching;

  /// No description provided for @movedFiles.
  ///
  /// In en, this message translates to:
  /// **'Moved {valueCount} {entryKey} files'**
  String movedFiles(Object valueCount, Object entryKey);

  /// No description provided for @movedFilesNotPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Moved {extrasCount} files not in playlist'**
  String movedFilesNotPlaylist(Object extrasCount);

  /// No description provided for @moved.
  ///
  /// In en, this message translates to:
  /// **'Moved {fileName}'**
  String moved(Object fileName);

  /// No description provided for @deleteFile4.
  ///
  /// In en, this message translates to:
  /// **'Delete this file'**
  String get deleteFile4;

  /// No description provided for @moveFileFormatFolder.
  ///
  /// In en, this message translates to:
  /// **'Move {extensionValue} file to format folder'**
  String moveFileFormatFolder(Object extensionValue);

  /// No description provided for @moveTargetFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to target folder'**
  String get moveTargetFolder;

  /// No description provided for @incompleteDownload.
  ///
  /// In en, this message translates to:
  /// **'Incomplete download  •  {extensionValue}'**
  String incompleteDownload(Object extensionValue);

  /// No description provided for @differentFromFolderFormat.
  ///
  /// In en, this message translates to:
  /// **'{extensionValue}  •  different from folder format'**
  String differentFromFolderFormat(Object extensionValue);

  /// No description provided for @exact.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get exact;

  /// No description provided for @contains.
  ///
  /// In en, this message translates to:
  /// **'Contains'**
  String get contains;

  /// No description provided for @artistTitle.
  ///
  /// In en, this message translates to:
  /// **'Artist+Title'**
  String get artistTitle;

  /// No description provided for @tokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get tokens;

  /// No description provided for @fuzzy.
  ///
  /// In en, this message translates to:
  /// **'Fuzzy'**
  String get fuzzy;

  /// No description provided for @downloadsOverTime.
  ///
  /// In en, this message translates to:
  /// **'Downloads Over Time'**
  String get downloadsOverTime;

  /// No description provided for @formats.
  ///
  /// In en, this message translates to:
  /// **'Formats'**
  String get formats;

  /// No description provided for @sources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get sources;

  /// No description provided for @topArtists.
  ///
  /// In en, this message translates to:
  /// **'Top Artists'**
  String get topArtists;

  /// No description provided for @device2.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get device2;

  /// No description provided for @couldNotStartRoom.
  ///
  /// In en, this message translates to:
  /// **'Could not start the room: {e}'**
  String couldNotStartRoom(Object e);

  /// No description provided for @formatAppDefault.
  ///
  /// In en, this message translates to:
  /// **'Format: app default'**
  String get formatAppDefault;

  /// No description provided for @folderDefault.
  ///
  /// In en, this message translates to:
  /// **'Folder: (default)'**
  String get folderDefault;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @fetchingModels.
  ///
  /// In en, this message translates to:
  /// **'Fetching models...'**
  String get fetchingModels;

  /// No description provided for @noModelsDetectedFromHost.
  ///
  /// In en, this message translates to:
  /// **'No models detected from host.'**
  String get noModelsDetectedFromHost;

  /// No description provided for @successfullyFetchedModelS.
  ///
  /// In en, this message translates to:
  /// **'Successfully fetched {modelsCount} model(s)'**
  String successfullyFetchedModelS(Object modelsCount);

  /// No description provided for @failedFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch models: {e}'**
  String failedFetchModels(Object e);

  /// No description provided for @downloadingRecommendedModel2.
  ///
  /// In en, this message translates to:
  /// **'Downloading recommended model {kDefaultAiModel}...'**
  String downloadingRecommendedModel2(Object kDefaultAiModel);

  /// No description provided for @recommendedModelReadySelected.
  ///
  /// In en, this message translates to:
  /// **'Recommended model is ready and selected.'**
  String get recommendedModelReadySelected;

  /// No description provided for @recommendedModelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Recommended model download failed: {e}'**
  String recommendedModelDownloadFailed(Object e);

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {trimmed} ...'**
  String connecting(Object trimmed);

  /// No description provided for @connectedOllama.
  ///
  /// In en, this message translates to:
  /// **'Connected to Ollama at {trimmed}'**
  String connectedOllama(Object trimmed);

  /// No description provided for @cantReachAddressMakeSure.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach that address. Make sure Ollama is running on your computer with OLLAMA_HOST=0.0.0.0 set, and that your phone is on the same Wi-Fi network.'**
  String get cantReachAddressMakeSure;

  /// No description provided for @cannotReachOllama.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach Ollama at {trimmed}'**
  String cannotReachOllama(Object trimmed);

  /// No description provided for @connectedNoLocalModelsFound.
  ///
  /// In en, this message translates to:
  /// **'Connected. No local models found, fallback set to {kDefaultAiModel}'**
  String connectedNoLocalModelsFound(Object kDefaultAiModel);

  /// No description provided for @connectedSelectedModel.
  ///
  /// In en, this message translates to:
  /// **'Connected. Selected model: {activeModel}'**
  String connectedSelectedModel(Object activeModel);

  /// No description provided for @connectedSelectedModelNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Connected. Selected model not installed; recommended model is available.'**
  String get connectedSelectedModelNotInstalled;

  /// No description provided for @connectedSelectedModelNotInstalled2.
  ///
  /// In en, this message translates to:
  /// **'Connected. Selected model not installed; choose one from the list.'**
  String get connectedSelectedModelNotInstalled2;

  /// No description provided for @selectedModel.
  ///
  /// In en, this message translates to:
  /// **'Selected model: {model}'**
  String selectedModel(Object model);

  /// No description provided for @downloadingRecommendedModel3.
  ///
  /// In en, this message translates to:
  /// **'Downloading recommended model {kDefaultAiModel} ...'**
  String downloadingRecommendedModel3(Object kDefaultAiModel);

  /// No description provided for @forLabel.
  ///
  /// In en, this message translates to:
  /// **'{status} ({progress}%) for {kDefaultAiModel}'**
  String forLabel(Object status, Object progress, Object kDefaultAiModel);

  /// No description provided for @downloading3.
  ///
  /// In en, this message translates to:
  /// **'Downloading {kDefaultAiModel} ...'**
  String downloading3(Object kDefaultAiModel);

  /// No description provided for @recommendedModelReady.
  ///
  /// In en, this message translates to:
  /// **'Recommended model {kDefaultAiModel} is ready.'**
  String recommendedModelReady(Object kDefaultAiModel);

  /// No description provided for @modelDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Model download failed: {e}'**
  String modelDownloadFailed(Object e);

  /// No description provided for @startedLocalOllamaServer.
  ///
  /// In en, this message translates to:
  /// **'Started local Ollama server.'**
  String get startedLocalOllamaServer;

  /// No description provided for @failedStartOllamaServer.
  ///
  /// In en, this message translates to:
  /// **'Failed to start Ollama server: {e}'**
  String failedStartOllamaServer(Object e);

  /// No description provided for @installingOllama.
  ///
  /// In en, this message translates to:
  /// **'Installing Ollama...'**
  String get installingOllama;

  /// No description provided for @ollamaInstalledLocally.
  ///
  /// In en, this message translates to:
  /// **'Ollama installed locally.'**
  String get ollamaInstalledLocally;

  /// No description provided for @installerLaunchedCompleteInstallThen.
  ///
  /// In en, this message translates to:
  /// **'Installer launched. Complete install then reconnect.'**
  String get installerLaunchedCompleteInstallThen;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get preparing;

  /// No description provided for @vaultSpireDesignedExclusivelyLegal.
  ///
  /// In en, this message translates to:
  /// **'Vault The Spire is designed exclusively for legal downloading. This includes:\n\n- Open-source software (Linux distros, development tools, games released freely)\n- Creative Commons licensed music, video, and books\n- Public domain content (old films, historical recordings, classic literature)\n- Files you own and have backed up yourself\n- Content explicitly shared by creators for free distribution\n\nDownloading or sharing copyrighted material without permission is illegal in most countries. The developers of this app do not condone or support unauthorized copyright violations.'**
  String get vaultSpireDesignedExclusivelyLegal;

  /// No description provided for @tapButtonPasteMagnetLink.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button to paste a magnet link, or open a .torrent file from your Files app to begin a download.\n\nSet your download folder in Settings before starting large downloads to make sure files go where you expect.\n\nWatch progress in the Torrents tab. Tap any torrent to see detailed speed, peers, and size information.'**
  String get tapButtonPasteMagnetLink;

  /// No description provided for @dragTorrentFileOntoWindow.
  ///
  /// In en, this message translates to:
  /// **'Drag a .torrent file onto the window, or paste a magnet link using the + button in the Torrents tab.\n\nSet your download folder in Settings. For large downloads, choose a drive with plenty of free space.\n\nThe app continues downloading in the system tray when you close the window - use the tray icon to monitor progress.'**
  String get dragTorrentFileOntoWindow;

  /// No description provided for @downloadingPiecesBeingReceivedFrom.
  ///
  /// In en, this message translates to:
  /// **'Downloading: Pieces are being received from peers across the internet. Larger torrents (10 GB+) can take hours on a typical home connection.\n\nStalled / Searching for peers: The app is looking for other users sharing this file. Rarer files may take longer to find peers. Try Force Refresh in the torrent details.\n\nSeeding: Download is complete. The app is sharing your copy with others - this is good for the community and is how BitTorrent works.\n\nChecking: After a redownload or app restart, pieces are being verified against their checksums. This ensures file integrity.'**
  String get downloadingPiecesBeingReceivedFrom;

  /// No description provided for @ifDownloadedFileSeemsCorrupt.
  ///
  /// In en, this message translates to:
  /// **'If a downloaded file seems corrupt or won\'t open, tap the torrent to open its detail view, then tap \"Verify files\". This re-reads every piece from disk and checks it against the original checksums - no data is deleted.\n\nIf verification finds bad pieces, or if you want to start completely fresh, tap \"Redownload\". This deletes the local copy and downloads everything again from peers.\n\nLarge repacks (multi-part installer archives) sometimes need a verify pass after completing because pieces can arrive out of order across many files.'**
  String get ifDownloadedFileSeemsCorrupt;

  /// No description provided for @vaultSpireStoresAllData.
  ///
  /// In en, this message translates to:
  /// **'Vault The Spire stores all data locally on your device. No torrent history, download statistics, or file names are sent to any server.\n\nYour IP address is visible to other peers in any torrent swarm you join - this is how BitTorrent works. A VPN will mask your IP if privacy from other peers is important to you.\n\nThe built-in browser does not sync history to any cloud. History is stored only on-device and can be cleared in Settings.'**
  String get vaultSpireStoresAllData;

  /// No description provided for @disableBatteryOptimisationVaultSpire.
  ///
  /// In en, this message translates to:
  /// **'- Disable battery optimisation for Vault The Spire in Android Settings -> Apps to prevent the OS from pausing active downloads.\n\n- If a torrent shows \"File already in use\", close any other app that has the file open, then tap Redownload.\n\n- Pull down on the Torrents list to force a refresh if progress looks frozen.\n\n- For best results on Android 12+, grant the app storage permission when prompted at first launch.'**
  String get disableBatteryOptimisationVaultSpire;

  /// No description provided for @appKeepsDownloadingWhenMinimised.
  ///
  /// In en, this message translates to:
  /// **'- The app keeps downloading when minimised to the system tray. Right-click the tray icon to pause all or quit cleanly.\n\n- If Windows shows a file as \"in use\" after a download completes, wait a few seconds for the app to release the write handle - it does this automatically on completion.\n\n- Use the browser tab to find magnet links without leaving the app. Detected magnets are highlighted automatically.\n\n- For very large torrents (20 GB+), make sure your drive has at least 10% free space beyond the download size.'**
  String get appKeepsDownloadingWhenMinimised;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @sAgo.
  ///
  /// In en, this message translates to:
  /// **'{inSeconds}s ago'**
  String sAgo(Object inSeconds);

  /// No description provided for @magnetLink.
  ///
  /// In en, this message translates to:
  /// **'Magnet link'**
  String get magnetLink;

  /// No description provided for @torrentFile.
  ///
  /// In en, this message translates to:
  /// **'Torrent file'**
  String get torrentFile;

  /// No description provided for @dhtTracker.
  ///
  /// In en, this message translates to:
  /// **'{seeders} (DHT: {dhtNodes}, Tracker: {trackers})'**
  String dhtTracker(Object seeders, Object dhtNodes, Object trackers);

  /// No description provided for @dateAdded.
  ///
  /// In en, this message translates to:
  /// **'Date added'**
  String get dateAdded;

  /// No description provided for @nameZ.
  ///
  /// In en, this message translates to:
  /// **'Name A → Z'**
  String get nameZ;

  /// No description provided for @nameZ2.
  ///
  /// In en, this message translates to:
  /// **'Name Z → A'**
  String get nameZ2;

  /// No description provided for @sizeSmallest.
  ///
  /// In en, this message translates to:
  /// **'Size smallest'**
  String get sizeSmallest;

  /// No description provided for @sizeLargest.
  ///
  /// In en, this message translates to:
  /// **'Size largest'**
  String get sizeLargest;

  /// No description provided for @progress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progress;

  /// No description provided for @kbS.
  ///
  /// In en, this message translates to:
  /// **'{bps} KB/s'**
  String kbS(Object bps);

  /// No description provided for @mbS.
  ///
  /// In en, this message translates to:
  /// **'{bps} MB/s'**
  String mbS(Object bps);

  /// No description provided for @tapAddCreateTorrents.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add or create torrents'**
  String get tapAddCreateTorrents;

  /// No description provided for @useTopBarAddCreate.
  ///
  /// In en, this message translates to:
  /// **'Use + in the top bar to add or create torrents\nYou can also drag and drop files'**
  String get useTopBarAddCreate;

  /// No description provided for @couldNotFetchSize.
  ///
  /// In en, this message translates to:
  /// **'Could not fetch size'**
  String get couldNotFetchSize;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select file'**
  String get selectFile;

  /// No description provided for @couldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {currentDirPath}: {e}'**
  String couldNotOpen(Object currentDirPath, Object e);

  /// No description provided for @usbDrive.
  ///
  /// In en, this message translates to:
  /// **'USB Drive'**
  String get usbDrive;

  /// No description provided for @storageLocationNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Storage location not available: {locationLabel}'**
  String storageLocationNotAvailable(Object locationLabel);

  /// No description provided for @permTabs.
  ///
  /// In en, this message translates to:
  /// **'See the address and title of your open tabs'**
  String get permTabs;

  /// No description provided for @permHistory.
  ///
  /// In en, this message translates to:
  /// **'Read and change your browsing history'**
  String get permHistory;

  /// No description provided for @permBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Read and change your bookmarks'**
  String get permBookmarks;

  /// No description provided for @permCookies.
  ///
  /// In en, this message translates to:
  /// **'Read and change cookies'**
  String get permCookies;

  /// No description provided for @permDownloads.
  ///
  /// In en, this message translates to:
  /// **'Manage your downloads'**
  String get permDownloads;

  /// No description provided for @permClipboardRead.
  ///
  /// In en, this message translates to:
  /// **'Read what you copy'**
  String get permClipboardRead;

  /// No description provided for @permClipboardWrite.
  ///
  /// In en, this message translates to:
  /// **'Change what is on your clipboard'**
  String get permClipboardWrite;

  /// No description provided for @permGeolocation.
  ///
  /// In en, this message translates to:
  /// **'Know your location'**
  String get permGeolocation;

  /// No description provided for @permNativeMessaging.
  ///
  /// In en, this message translates to:
  /// **'Talk to other programs on your computer'**
  String get permNativeMessaging;

  /// No description provided for @permWebRequest.
  ///
  /// In en, this message translates to:
  /// **'Watch the requests pages make'**
  String get permWebRequest;

  /// No description provided for @permWebRequestBlocking.
  ///
  /// In en, this message translates to:
  /// **'Block or change the requests pages make'**
  String get permWebRequestBlocking;

  /// No description provided for @permScripting.
  ///
  /// In en, this message translates to:
  /// **'Run scripts on pages it has access to'**
  String get permScripting;

  /// No description provided for @permPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Change privacy settings'**
  String get permPrivacy;

  /// No description provided for @permManagement.
  ///
  /// In en, this message translates to:
  /// **'Manage your other extensions'**
  String get permManagement;

  /// No description provided for @permProxy.
  ///
  /// In en, this message translates to:
  /// **'Control your proxy settings'**
  String get permProxy;

  /// No description provided for @permNotifications.
  ///
  /// In en, this message translates to:
  /// **'Show notifications'**
  String get permNotifications;

  /// No description provided for @permStorage.
  ///
  /// In en, this message translates to:
  /// **'Store its own data'**
  String get permStorage;

  /// No description provided for @permUnlimitedStorage.
  ///
  /// In en, this message translates to:
  /// **'Store an unlimited amount of its own data'**
  String get permUnlimitedStorage;

  /// No description provided for @permContextMenus.
  ///
  /// In en, this message translates to:
  /// **'Add items to right-click menus'**
  String get permContextMenus;

  /// No description provided for @permAlarms.
  ///
  /// In en, this message translates to:
  /// **'Run on a schedule'**
  String get permAlarms;

  /// No description provided for @permActiveTab.
  ///
  /// In en, this message translates to:
  /// **'Access the current page when you use it'**
  String get permActiveTab;

  /// No description provided for @permTheme.
  ///
  /// In en, this message translates to:
  /// **'Change the browser’s colours'**
  String get permTheme;

  /// No description provided for @permWebNavigation.
  ///
  /// In en, this message translates to:
  /// **'See which pages you visit'**
  String get permWebNavigation;

  /// No description provided for @permTopSites.
  ///
  /// In en, this message translates to:
  /// **'See your most visited sites'**
  String get permTopSites;

  /// No description provided for @permSessions.
  ///
  /// In en, this message translates to:
  /// **'See recently closed tabs'**
  String get permSessions;

  /// No description provided for @permBrowsingData.
  ///
  /// In en, this message translates to:
  /// **'Clear your browsing data'**
  String get permBrowsingData;

  /// No description provided for @permSearch.
  ///
  /// In en, this message translates to:
  /// **'Use your search engine'**
  String get permSearch;

  /// No description provided for @permIdentity.
  ///
  /// In en, this message translates to:
  /// **'Sign you in to its own service'**
  String get permIdentity;

  /// No description provided for @permFontSettings.
  ///
  /// In en, this message translates to:
  /// **'Read your font settings'**
  String get permFontSettings;

  /// No description provided for @permUserScripts.
  ///
  /// In en, this message translates to:
  /// **'Run user scripts on pages'**
  String get permUserScripts;

  /// No description provided for @permIdle.
  ///
  /// In en, this message translates to:
  /// **'Know when you are away from the computer'**
  String get permIdle;

  /// No description provided for @permSidePanel.
  ///
  /// In en, this message translates to:
  /// **'Show a side panel'**
  String get permSidePanel;

  /// No description provided for @permOffscreen.
  ///
  /// In en, this message translates to:
  /// **'Run hidden pages in the background'**
  String get permOffscreen;

  /// No description provided for @permDns.
  ///
  /// In en, this message translates to:
  /// **'Look up web addresses'**
  String get permDns;

  /// No description provided for @permPageCapture.
  ///
  /// In en, this message translates to:
  /// **'Save pages'**
  String get permPageCapture;

  /// No description provided for @permTabGroups.
  ///
  /// In en, this message translates to:
  /// **'Organise your tab groups'**
  String get permTabGroups;

  /// No description provided for @permDebugger.
  ///
  /// In en, this message translates to:
  /// **'Inspect and control pages as a debugger'**
  String get permDebugger;

  /// No description provided for @permDesktopCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture your screen'**
  String get permDesktopCapture;

  /// No description provided for @permTabCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture a tab’s sound and picture'**
  String get permTabCapture;

  /// No description provided for @permEveryWebsite.
  ///
  /// In en, this message translates to:
  /// **'Read and change everything on every website'**
  String get permEveryWebsite;

  /// No description provided for @permSomeWebsites.
  ///
  /// In en, this message translates to:
  /// **'Read and change data on {hosts}{more}'**
  String permSomeWebsites(Object hosts, Object more);

  /// No description provided for @permUnknown.
  ///
  /// In en, this message translates to:
  /// **'Use \"{permission}\"'**
  String permUnknown(Object permission);

  /// No description provided for @extensionUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'update to {version} available'**
  String extensionUpdateAvailable(Object version);

  /// No description provided for @ytDlpUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'yt-dlp {versionText} - Update available: {latest}'**
  String ytDlpUpdateAvailable(Object versionText, Object latest);

  /// No description provided for @featureTorrentDownloads.
  ///
  /// In en, this message translates to:
  /// **'Torrent downloads'**
  String get featureTorrentDownloads;

  /// No description provided for @featureQueueLibrary.
  ///
  /// In en, this message translates to:
  /// **'Queue & library'**
  String get featureQueueLibrary;

  /// No description provided for @featureFormatConversion.
  ///
  /// In en, this message translates to:
  /// **'Format conversion'**
  String get featureFormatConversion;

  /// No description provided for @featureDlnaCast.
  ///
  /// In en, this message translates to:
  /// **'DLNA / Cast to TV'**
  String get featureDlnaCast;

  /// No description provided for @watchedFormat.
  ///
  /// In en, this message translates to:
  /// **'Format: {format}'**
  String watchedFormat(Object format);

  /// No description provided for @watchedFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder: {folder}'**
  String watchedFolder(Object folder);

  /// No description provided for @storageDevice.
  ///
  /// In en, this message translates to:
  /// **'Device storage'**
  String get storageDevice;

  /// No description provided for @storagePrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary storage'**
  String get storagePrimary;

  /// No description provided for @storageSdCard.
  ///
  /// In en, this message translates to:
  /// **'SD card'**
  String get storageSdCard;

  /// No description provided for @bannerSearch.
  ///
  /// In en, this message translates to:
  /// **'Add a torrent, magnet link, or supported source to the queue.'**
  String get bannerSearch;

  /// No description provided for @bannerMultiSearch.
  ///
  /// In en, this message translates to:
  /// **'Search multiple sources simultaneously and add results to your queue.'**
  String get bannerMultiSearch;

  /// No description provided for @bannerBrowser.
  ///
  /// In en, this message translates to:
  /// **'Browse the web with built-in ad blocking and link detection.'**
  String get bannerBrowser;

  /// No description provided for @bannerQueue.
  ///
  /// In en, this message translates to:
  /// **'Track and manage your downloads here.'**
  String get bannerQueue;

  /// No description provided for @bannerPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Load collections, compare with local folders, and download missing items.'**
  String get bannerPlaylists;

  /// No description provided for @bannerBulkImport.
  ///
  /// In en, this message translates to:
  /// **'Paste a list of links or items to bulk-download them.'**
  String get bannerBulkImport;

  /// No description provided for @bannerStats.
  ///
  /// In en, this message translates to:
  /// **'View your download statistics and trends.'**
  String get bannerStats;

  /// No description provided for @bannerSettings.
  ///
  /// In en, this message translates to:
  /// **'Configure download directory, format, quality, and tools.'**
  String get bannerSettings;

  /// No description provided for @bannerSupport.
  ///
  /// In en, this message translates to:
  /// **'Support the project via donations or by contributing feedback.'**
  String get bannerSupport;

  /// No description provided for @bannerConvert.
  ///
  /// In en, this message translates to:
  /// **'Convert audio and video files between formats using FFmpeg.'**
  String get bannerConvert;

  /// No description provided for @bannerLogs.
  ///
  /// In en, this message translates to:
  /// **'View the activity log for debugging and monitoring.'**
  String get bannerLogs;

  /// No description provided for @bannerGuide.
  ///
  /// In en, this message translates to:
  /// **'Documentation, tips, and troubleshooting.'**
  String get bannerGuide;

  /// No description provided for @bannerPlayer.
  ///
  /// In en, this message translates to:
  /// **'Play your downloaded music and videos with the built-in media player.'**
  String get bannerPlayer;

  /// No description provided for @colourSlate.
  ///
  /// In en, this message translates to:
  /// **'Slate'**
  String get colourSlate;

  /// No description provided for @colourSteel.
  ///
  /// In en, this message translates to:
  /// **'Steel'**
  String get colourSteel;

  /// No description provided for @colourGraphite.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get colourGraphite;

  /// No description provided for @colourMist.
  ///
  /// In en, this message translates to:
  /// **'Mist'**
  String get colourMist;

  /// No description provided for @colourAsh.
  ///
  /// In en, this message translates to:
  /// **'Ash'**
  String get colourAsh;

  /// No description provided for @colourOceanBlue.
  ///
  /// In en, this message translates to:
  /// **'Ocean Blue'**
  String get colourOceanBlue;

  /// No description provided for @colourDeepTeal.
  ///
  /// In en, this message translates to:
  /// **'Deep Teal'**
  String get colourDeepTeal;

  /// No description provided for @colourIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get colourIndigo;

  /// No description provided for @colourBurntSienna.
  ///
  /// In en, this message translates to:
  /// **'Burnt Sienna'**
  String get colourBurntSienna;

  /// No description provided for @colourBark.
  ///
  /// In en, this message translates to:
  /// **'Bark'**
  String get colourBark;

  /// No description provided for @colourRuby.
  ///
  /// In en, this message translates to:
  /// **'Ruby'**
  String get colourRuby;

  /// No description provided for @colourBerry.
  ///
  /// In en, this message translates to:
  /// **'Berry'**
  String get colourBerry;

  /// No description provided for @colourCyanDepth.
  ///
  /// In en, this message translates to:
  /// **'Cyan Depth'**
  String get colourCyanDepth;

  /// No description provided for @colourFern.
  ///
  /// In en, this message translates to:
  /// **'Fern'**
  String get colourFern;

  /// No description provided for @colourSaffron.
  ///
  /// In en, this message translates to:
  /// **'Saffron'**
  String get colourSaffron;

  /// No description provided for @colourVoidPurple.
  ///
  /// In en, this message translates to:
  /// **'Void Purple'**
  String get colourVoidPurple;

  /// No description provided for @colourCrimsonRose.
  ///
  /// In en, this message translates to:
  /// **'Crimson Rose'**
  String get colourCrimsonRose;

  /// No description provided for @colourAbyss.
  ///
  /// In en, this message translates to:
  /// **'Abyss'**
  String get colourAbyss;

  /// No description provided for @colourForestKing.
  ///
  /// In en, this message translates to:
  /// **'Forest King'**
  String get colourForestKing;

  /// No description provided for @colourEmber.
  ///
  /// In en, this message translates to:
  /// **'Ember'**
  String get colourEmber;

  /// No description provided for @colourDarkGold.
  ///
  /// In en, this message translates to:
  /// **'Dark Gold'**
  String get colourDarkGold;

  /// No description provided for @colourRoyalAmethyst.
  ///
  /// In en, this message translates to:
  /// **'Royal Amethyst'**
  String get colourRoyalAmethyst;

  /// No description provided for @colourDragonTeal.
  ///
  /// In en, this message translates to:
  /// **'Dragon Teal'**
  String get colourDragonTeal;

  /// No description provided for @colourWineCrest.
  ///
  /// In en, this message translates to:
  /// **'Wine Crest'**
  String get colourWineCrest;

  /// No description provided for @colourMythicRed.
  ///
  /// In en, this message translates to:
  /// **'Mythic Red'**
  String get colourMythicRed;

  /// No description provided for @colourMangoPassion.
  ///
  /// In en, this message translates to:
  /// **'Mango Passion'**
  String get colourMangoPassion;

  /// No description provided for @colourObsidianBlack.
  ///
  /// In en, this message translates to:
  /// **'Obsidian Black'**
  String get colourObsidianBlack;

  /// No description provided for @colourIvoryPrime.
  ///
  /// In en, this message translates to:
  /// **'Ivory Prime'**
  String get colourIvoryPrime;

  /// No description provided for @rarityCommon.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get rarityCommon;

  /// No description provided for @rarityUncommon.
  ///
  /// In en, this message translates to:
  /// **'Uncommon'**
  String get rarityUncommon;

  /// No description provided for @rarityRare.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get rarityRare;

  /// No description provided for @rarityEpic.
  ///
  /// In en, this message translates to:
  /// **'Epic'**
  String get rarityEpic;

  /// No description provided for @rarityLegendary.
  ///
  /// In en, this message translates to:
  /// **'Legendary'**
  String get rarityLegendary;

  /// No description provided for @rarityMythic.
  ///
  /// In en, this message translates to:
  /// **'Mythic'**
  String get rarityMythic;

  /// No description provided for @pieceSizeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (recommended)'**
  String get pieceSizeAuto;

  /// No description provided for @torrentStatusSeeding.
  ///
  /// In en, this message translates to:
  /// **'Seeding'**
  String get torrentStatusSeeding;

  /// No description provided for @torrentStatusSeedingPartial.
  ///
  /// In en, this message translates to:
  /// **'Seeding (partial)'**
  String get torrentStatusSeedingPartial;

  /// No description provided for @torrentStatusStalled.
  ///
  /// In en, this message translates to:
  /// **'Stalled'**
  String get torrentStatusStalled;

  /// No description provided for @torrentStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get torrentStatusChecking;

  /// No description provided for @torrentStatusPendingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Waiting for metadata'**
  String get torrentStatusPendingMetadata;

  /// No description provided for @torrentStatusFetchingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Fetching metadata'**
  String get torrentStatusFetchingMetadata;

  /// No description provided for @torrentStatusFileInUse.
  ///
  /// In en, this message translates to:
  /// **'File in use'**
  String get torrentStatusFileInUse;

  /// No description provided for @torrentStatusMissingFiles.
  ///
  /// In en, this message translates to:
  /// **'Files missing'**
  String get torrentStatusMissingFiles;
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
