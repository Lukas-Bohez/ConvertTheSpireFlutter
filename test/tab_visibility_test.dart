import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:convert_the_spire_reborn/src/config/build_flags.dart';

/// A tab is hidden only where Play policy requires it: the YouTube download
/// features in the Play build. File conversion is shown everywhere.
void main() {
  const convert = 9;
  // Search, Multi-Search, Playlists, Bulk Import, Statistics, Logs.
  const playOnlyHidden = [0, 1, 4, 5, 6, 10];

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    setPlayStoreBuildFlag(false);
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    test('Convert is shown on ${platform.name}, in both builds', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(isTabVisibleInCurrentBuild(convert), isTrue);
      setPlayStoreBuildFlag(true);
      expect(isTabVisibleInCurrentBuild(convert), isTrue);
    });
  }

  test('the GitHub build shows every tab', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    for (var i = 0; i <= 14; i++) {
      expect(isTabVisibleInCurrentBuild(i), isTrue, reason: 'tab $i');
    }
  });

  test('the Play build hides only the tabs it lists', () {
    setPlayStoreBuildFlag(true);
    for (var i = 0; i <= 14; i++) {
      expect(isTabVisibleInCurrentBuild(i), !playOnlyHidden.contains(i),
          reason: 'tab $i');
    }
  });
}
