const String kBaseUrl = 'https://quizthespire.com/vault/api';

const String kPrivacyPolicyUrl = 'https://quizthespire.com/privacy-policy';

const int kDefaultTorrentPort = 6881;

const bool kTorrentFeatureEnabled = bool.fromEnvironment(
  'TORRENT_FEATURE',
  defaultValue: true,
);
const bool kAppStoreBuild = bool.fromEnvironment(
  'APP_STORE',
  defaultValue: false,
);

// Single recommended local AI model used across the app.
const String kDefaultAiModel = 'llama3.1:8b';

// Android emulator loopback for a host machine Ollama server.
const String kAndroidLocalOllamaUrl = 'http://10.0.2.2:11434';

// Shared icon assets for desktop, tray, and UI branding
const String kAppIconIco = 'assets/icons/app_icon.ico';
const String kAppFavicon192 = 'assets/icons/favicon-192x192.png';
