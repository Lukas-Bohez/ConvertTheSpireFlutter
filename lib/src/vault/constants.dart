const String kBaseUrl = 'https://quizthespire.com/vault/api';

const String kPrivacyPolicyUrl = 'https://quizthespire.com/privacy';

const int kDefaultTorrentPort = 6881;

const bool kTorrentFeatureEnabled = bool.fromEnvironment(
  'TORRENT_FEATURE',
  defaultValue: true,
);
const bool kAppStoreBuild = bool.fromEnvironment(
  'APP_STORE',
  defaultValue: false,
);

// Shared icon assets for desktop, tray, and UI branding
const String kAppIconIco = 'assets/icons/app_icon.ico';
const String kAppFavicon192 = 'assets/icons/favicon-192x192.png';
