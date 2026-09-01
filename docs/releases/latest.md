# Release Notes - v13.0.0

## fix & compliance release

## Highlights

* Fixed Linux/macOS yt-dlp downloads — the app was fetching a yt-dlp release asset that needs a system Python 3.11+ interpreter instead of the correct self-contained binary, which broke downloads (including playlists) on machines without a new enough system Python. This is what Linux Mint users were reporting.
* Raised `targetSdkVersion` to 36 (Android 16) to stay compliant with Google Play's target API policy.
* Fixed `build_release.sh`: removed a hardcoded, stale version/build number that could silently override `pubspec.yaml`'s version, and added the missing `GITHUB_RELEASE` dart-define so the GitHub build's ad-free/unlocked-colours mode actually activates.
* Rebuilt the Play Store AAB for `v13.0.0` and replaced the old local AAB artifacts.
* Release assets continue to include Windows, Linux, macOS, Android APK, SHA256 checksums, and the AAB (AAB is uploaded to Play Console separately, not attached to the GitHub release).

## Build Notes

* GitHub release tag: `v13.0.0`
* Release page: [v13.0.0](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.0)
* `flutter analyze` and `flutter test --coverage` pass cleanly.
