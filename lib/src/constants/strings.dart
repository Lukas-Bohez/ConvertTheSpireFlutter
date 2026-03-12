/// User-facing string constants for the app.
///
/// Centralising strings here makes future i18n (e.g. intl / ARB files)
/// straightforward: grep for `Strings.` and replace with generated code.
abstract final class Strings {
  // ── App ─────────────────────────────────────────────────────────────────
  static const appName = 'Convert the Spire Reborn';

  // ── Navigation / Tabs ───────────────────────────────────────────────────
  static const tabSearch = 'Search';
  static const tabMultiSearch = 'Search+';
  static const tabBrowser = 'Browser';
  static const tabQueue = 'Queue';
  static const tabPlaylists = 'Playlists';
  static const tabImport = 'Import';
  static const tabStats = 'Statistics';
  static const tabSettings = 'Settings';
  static const tabSupport = 'Support';
  static const tabConvert = 'Convert';
  static const tabLogs = 'Logs';
  static const tabGuide = 'Guide';
  static const tabPlayer = 'Player';
  static const tabHome = 'Home';

  // ── Downloads ───────────────────────────────────────────────────────────
  static const downloadComplete = 'Download Complete';
  static const downloadFailed = 'Download Failed';
  static const downloadCancelled = 'Cancelled';
  static const downloading = 'Downloading';
  static const queued = 'Queued';
  static const converting = 'Converting';

  // ── Cast ────────────────────────────────────────────────────────────────
  static const castToDevice = 'Cast to Device';
  static const scanningForDevices = 'Scanning for devices…';
  static const noDevicesFound = 'No devices found';
  static const rescan = 'Rescan';
  static const enterIp = 'Enter IP';
  static const enterIpManually = 'Enter IP manually';
  static const disconnect = 'Disconnect';

  // ── Player ──────────────────────────────────────────────────────────────
  static const noFavouritesYet = 'No favourites yet';
  static const tapHeartHint = 'Tap the heart icon on any track';
  static const shuffle = 'Shuffle';
  static const repeat = 'Repeat';
  static const playbackMode = 'Playback Mode';

  // ── Errors ──────────────────────────────────────────────────────────────
  static const errorGeneric = 'Something went wrong. Please try again.';
  static const errorNoInternet = 'No internet connection.';
  static const errorCookiesRequired =
      'This site may require browser cookies for access. '
      'Try using the browser to log in first.';
}
