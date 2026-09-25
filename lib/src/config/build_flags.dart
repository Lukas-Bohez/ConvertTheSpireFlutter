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
// Prefer an explicit compile-time dart-define override. If not provided,
// fall back to the runtime-detected flavor set from `initAppFlavor()`.
bool get kPlayStoreBuild => kIsPlayStoreBuildDefine || _kPlayStoreBuild;
bool _kPlayStoreBuild = false;

bool get isYouTubeConversionEnabledInCurrentBuild {
  if (!kPlayStoreBuild) return true;
  return false; // YouTube conversion disabled in Play Store builds per policy
}

bool get kYouTubeConversionEnabled => isYouTubeConversionEnabledInCurrentBuild;

// App branding -- unified across all flavors.
String getAppTitle() {
   return kPlayStoreBuild ? 'BitPlayer' : 'Convert the Spire Reborn';
}

String getAppSubtitle() {
   return kPlayStoreBuild ? 'BitPlayer -- media & torrents' : 'Convert the Spire Reborn -- media & torrents';
}

String getDefaultDownloadFolderName() {
   return kPlayStoreBuild ? 'BitPlayer' : 'ConvertTheSpireReborn';
}

// Tab visibility -- hide tabs in Play builds only.
//
// A tab is hidden only when Play policy requires it: the YouTube download
// features stay out of the Play build. Everything else, the file converter
// included, is shown on every platform. Convert used to be hidden on all of
// Android; FFmpegKit ships in the Android app, so it converts there too.
/// The page index the old Search page had; nothing shows it any more.
const int kRemovedSearchTab = 0;

bool isTabVisibleInCurrentBuild(int tabIndex) {
  // Search (0) is gone from every build: Quick Download on Home and the
  // Playlist Manager do what it did. Multi-Search stays. The page numbers
  // are kept, so every other page keeps its index.
  if (tabIndex == kRemovedSearchTab) return false;
  // In Play builds hide Multi-Search, Playlists, Bulk Import, Stats, and Logs.
  if (kPlayStoreBuild &&
      (tabIndex == 1 ||
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