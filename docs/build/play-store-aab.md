# Play Store AAB Build Guide

This project uses the `play` flavor for the Google Play / Android TV bundle.

## Build

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
flutter build appbundle --flavor play --release --no-tree-shake-icons --dart-define=PLAY_STORE_BUILD=true --dart-define=GITHUB_RELEASE=false
```

This is the same command the release workflow runs.

## Current Release

* Latest GitHub release tag: `v10.7.1`
* Release AAB asset: `zaab.aab`
* Play build output remains `build/app/outputs/bundle/playRelease/app-play-release.aab`

## TV Verification

The Play bundle must keep these manifest entries after merging:

* `android.software.leanback` with `required="false"`
* `android.hardware.touchscreen` with `required="false"`
* `android.hardware.faketouch` with `required="false"`
* `LEANBACK_LAUNCHER`
* `android:banner="@mipmap/banner"`: 320x180 px at xhdpi, and a launcher icon of at least 160x160 px at xhdpi (regenerate both with store/google-play/build_store_assets.py)
