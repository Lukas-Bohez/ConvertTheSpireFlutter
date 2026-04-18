import 'package:flutter/foundation.dart';

import 'full_mode_access.dart';

const bool kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: true,
);

bool get isYouTubeConversionEnabledInCurrentBuild {
  if (!kPlayStoreBuild) return true;
  return !FullModeAccess.instance.isLimitedPlayMode;
}

bool get _isLimitedBrandingMode =>
  kPlayStoreBuild && FullModeAccess.instance.isLimitedPlayMode;

// App branding
String getAppTitle() =>
  _isLimitedBrandingMode ? 'Bitplayer' : 'Convert the Spire Reborn';
String getAppSubtitle() =>
  _isLimitedBrandingMode ? 'Torrent vault & media hub' : 'Torrent manager & media toolkit';
String getDefaultDownloadFolderName() =>
  _isLimitedBrandingMode ? 'Bitplayer' : 'ConvertTheSpireReborn';

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
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && tabIndex == 9) {
    return false;
  }

  if (FullModeAccess.instance.isLimitedPlayMode) {
    return isTabVisibleInPlayStore(tabIndex);
  }

  return true;
}
