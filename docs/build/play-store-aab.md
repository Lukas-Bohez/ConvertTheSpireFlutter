# Play Store AAB Build Guide

This project uses the `play` flavor for the Google Play / Android TV bundle. On Play the app is called **BitPlayer** (`com.torrentspire.ai`); it has everything except the YouTube download features, which Play policy does not allow.

## Build

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
flutter build appbundle --flavor play --release --no-tree-shake-icons --dart-define=PLAY_STORE_BUILD=true --dart-define=GITHUB_RELEASE=false
```

This is the same command the release workflow runs. The output is `build/app/outputs/bundle/playRelease/app-play-release.aab`. Copy it to `aab/ConvertTheSpireReborn-v<version>+<build>-play.aab` (the `aab/` folder is git-ignored) and keep only the newest one there.

The GitHub release does not carry the AAB. The release workflow builds one too (the run's `android-aab-play` artifact), but the bundle uploaded to Play is the one built locally as above.

## Signing

`android/key.properties` points at `android/app/release.keystore` (certificate "CN=TorrentSpire AI"), which is the key Play accepts uploads from. Neither file is in git.

`aab/upload_cert.der` is **not** the upload key: it is a Google certificate. To confirm a new bundle is signed correctly, compare it with the last bundle Play accepted (see below).

## Check before uploading

```bash
python scripts/verify_play_aab.py aab/ConvertTheSpireReborn-v15.0.0+1299-play.aab \
    --previous path/to/the-last-accepted.aab
```

It needs Java, Pillow and [bundletool](https://github.com/google/bundletool/releases) (`--bundletool path/to/bundletool-all.jar` or `BUNDLETOOL_JAR`). It fails if any of these is off:

* the version is not the one in `pubspec.yaml`;
* the bundled `CHANGELOG.md` has no entry for it, so What's new would be empty;
* an Android TV requirement below is missing;
* with `--previous`, the signing key differs from that earlier upload.

## Android TV requirements

Play review checks these; 14.4.1 was turned down for the banner and icon ("no full-size app banner and/or icon", guideline TV-LB).

* `LEANBACK_LAUNCHER` on the main activity.
* `android.software.leanback`, `android.hardware.touchscreen` and `android.hardware.faketouch` with `required="false"`.
* `android:banner="@mipmap/banner"`: `mipmap-<density>/banner.png` from 160x90 (mdpi) to 640x360 (xxxhdpi), so 320x180 px at xhdpi, showing the logo and the app name only.
* A launcher icon of at least 160x160 px at xhdpi, opaque: the legacy `mipmap-<density>/ic_launcher.png` is 80dp, next to the adaptive icon.
* An icon that fills its square: the logo on the banner's gradient, edge to edge, in the adaptive icon, the legacy icon and the Play Console's 512x512 icon. 14.4.1's logo on a pale square was turned down with "Your icon does not fill the entire icon space".
* No `android:roundIcon`; Android TV's guidelines deprecate it.

Regenerate the banner and icons with `python store/google-play/build_store_assets.py`, never by hand; see [store/google-play/README.md](../../store/google-play/README.md). Sizes come from Google's [Android TV icon and banner guidelines](https://developer.android.com/design/ui/tv/guides/system/tv-app-icon-guidelines).

### Seeing it on a TV

To see the launcher tile before uploading, install the bundle on the `AndroidTV64` emulator (API 36, 1080p) the way Play would split it:

```bash
java -jar bundletool-all.jar build-apks --bundle <aab> --output out.apks --connected-device --device-id emulator-5554
java -jar bundletool-all.jar install-apks --apks out.apks --device-id emulator-5554
adb -s emulator-5554 shell am start -n com.google.android.tvlauncher/.appsview.AppsViewActivity
```

The TV launcher caches banners. After installing over an older version, run `adb shell am force-stop com.google.android.tvlauncher` to see the new one.
