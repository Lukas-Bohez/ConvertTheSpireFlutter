# Play Store AAB Build Guide

This project uses the `play` flavor for the Google Play / Android TV bundle.

## Build

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
flutter build appbundle --flavor play --release --dart-define=PLAY_STORE_BUILD=true
```

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
* `android:banner="@drawable/tv_banner"`
