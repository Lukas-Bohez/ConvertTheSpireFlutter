import 'package:flutter/foundation.dart';

/// Compile-time flag: true when building for Play Store with ads enabled.
/// Set via: --dart-define=PLAY_STORE_BUILD=true during Play build.
/// Falls back to runtime-detected flavor if not provided.
const bool kIsPlayStoreBuildDefine =
    bool.fromEnvironment('PLAY_STORE_BUILD', defaultValue: false);

/// Compile-time flag: true when building for GitHub Releases (ad-free, all colours unlocked).
/// Set via: --dart-define=GITHUB_RELEASE=true during GitHub APK build.
const bool kIsGithubRelease =
    bool.fromEnvironment('GITHUB_RELEASE', defaultValue: false);

/// Runtime-play detection. This is initialized early in `main()` by
/// calling `initAppFlavor()` so that synchronous calls to `kPlayStoreBuild`
/// reflect the actual app branding at runtime.
/// If PLAY_STORE_BUILD dart-define is provided, it overrides runtime detection.
bool get kPlayStoreBuild => _kPlayStoreBuild;
bool _kPlayStoreBuild = false;

bool get isYouTubeConversionEnabledInCurrentBuild {
  if (!kPlayStoreBuild) return true;
  return false; // YouTube conversion disabled in Play Store builds per policy
}

// App branding — adapt to the detected flavor
String getAppTitle() => kPlayStoreBuild ? 'Bitplayer' : 'Convert the Spire Reborn';
String getAppSubtitle() => kPlayStoreBuild ? 'Bitplayer — media & torrents' : 'Torrent manager & media toolkit';
String getDefaultDownloadFolderName() => kPlayStoreBuild ? 'Bitplayer' : 'ConvertTheSpireReborn';

// Tab visibility — hide/modify tabs for Play builds
bool isTabVisibleInCurrentBuild(int tabIndex) {
  // Convert tab (tabIndex 9) is disabled on Android per platform limitations
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && tabIndex == 9) {
    return false;
  }
  // In Play builds hide Search, Multi-Search, Playlists, Bulk Import, Stats, and Logs.
  if (kPlayStoreBuild &&
      (tabIndex == 0 ||
          tabIndex == 1 ||
          tabIndex == 4 ||
          tabIndex == 5 ||
          tabIndex == 6 ||
          tabIndex == 10)) {
    return false;
  }
  return true;
}

// Internal: allow main() to set the play-store flag after reading package label.
void setPlayStoreBuildFlag(bool v) => _kPlayStoreBuild = v;
