const bool kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: false,
);

const bool kYouTubeConversionEnabled = bool.fromEnvironment(
  'ENABLE_YOUTUBE_CONVERSION',
  defaultValue: !kPlayStoreBuild,
);

// App branding
String getAppTitle() => kPlayStoreBuild ? 'Vault the Spire' : 'Convert the Spire Reborn';
String getAppSubtitle() => kPlayStoreBuild ? 'Torrent vault & media hub' : 'Torrent manager & media toolkit';

// Tab visibility control for PLAY_STORE_BUILD
// In Play Store, only these tabs are shown: 3 (deprecated), 6 (Stats), 7 (Settings), 
// 8 (Support), 11 (Guide), 12 (Player), 13 (Home), 14 (Torrents/Vault)
// Tabs hidden in PLAY_STORE_BUILD: 0 (Search), 1 (Multi-Search), 2 (Browser), 
// 3 (Queue), 4 (Playlists), 5 (Bulk Import), 9 (Convert), 10 (Logs)
bool isTabVisibleInPlayStore(int tabIndex) {
  if (!kPlayStoreBuild) return true;
  
  const playStoreVisibleTabs = {6, 7, 8, 11, 12, 13, 14};
  return playStoreVisibleTabs.contains(tabIndex);
}
