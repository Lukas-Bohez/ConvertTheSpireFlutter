import 'package:flutter/foundation.dart';

const bool kPlayStoreBuild = bool.fromEnvironment(
  'PLAY_STORE_BUILD',
  defaultValue: false,
);

bool get isYouTubeConversionEnabledInCurrentBuild {
  if (!kPlayStoreBuild) return true;
  return false; // YouTube conversion disabled in Play Store builds per policy
}

// App branding — consistent across all builds
String getAppTitle() => 'Convert the Spire Reborn';
String getAppSubtitle() => 'Torrent manager & media toolkit';
String getDefaultDownloadFolderName() => 'ConvertTheSpireReborn';

// Tab visibility — all tabs visible in all builds
bool isTabVisibleInCurrentBuild(int tabIndex) {
  // Convert tab (tabIndex 9) is disabled on Android per platform limitations
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && tabIndex == 9) {
    return false;
  }
  return true;
}
