import 'package:flutter/foundation.dart';

const bool kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: false,
);

const bool kYouTubeConversionEnabled = bool.fromEnvironment(
  'ENABLE_YOUTUBE_CONVERSION',
  defaultValue: !kPlayStoreBuild,
);

// App branding
String getAppTitle() => kPlayStoreBuild ? 'Bitplayer' : 'Convert Spire Reborn';
String getAppSubtitle() => kPlayStoreBuild ? 'Torrent vault & media hub' : 'Torrent manager & media toolkit';
String getDefaultDownloadFolderName() =>
  kPlayStoreBuild ? 'Bitplayer' : 'ConvertTheSpireReborn';

// Tab visibility control for PLAY_STORE_BUILD
// In Play Store, only these tabs are shown: 2 (Browser), 7 (Settings),
// 8 (Support), 11 (Guide), 12 (Player), 13 (Home), 14 (Torrents/Vault)
// Tabs hidden in PLAY_STORE_BUILD: 0 (Search), 1 (Multi-Search),
// 3 (Queue), 4 (hidden tools), 5 (Bulk Import), 9 (Convert), 10 (Logs)
bool isTabVisibleInPlayStore(int tabIndex) {
  if (!kPlayStoreBuild) return true;
  
  const playStoreVisibleTabs = {2, 7, 8, 11, 12, 13, 14};
  return playStoreVisibleTabs.contains(tabIndex);
}

bool isTabVisibleInCurrentBuild(int tabIndex) {
  if (kPlayStoreBuild) {
    return isTabVisibleInPlayStore(tabIndex);
  }

  // Convert is currently unreliable on Android and should stay hidden there
  // to avoid dead-end UX in non-Play APK builds.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (tabIndex == 9) return false;
  }

  return true;
}
