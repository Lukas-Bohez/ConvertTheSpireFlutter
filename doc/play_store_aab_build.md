# Play Store AAB Build Guide

This guide documents how the current Play Store Android App Bundle was produced, so the build can be repeated without guessing.

## What this build does

The Play build is the `play` flavor, compiled with `PLAY_STORE_BUILD=true`. That flag is what enables the Play-store-specific app behavior in Dart code.

Relevant files:

- `lib/src/config/build_flags.dart` controls Play-only feature gating and branding.
- `lib/src/config/full_mode_access.dart` switches the app into limited Play mode when `PLAY_STORE_BUILD=true`.
- `android/app/build.gradle.kts` defines the `play` flavor, version code/name, and the base package name `com.torrentspire.ai`.
- `android/app/src/main/AndroidManifest.xml` and `android/app/src/play/AndroidManifest.xml` provide the Play-friendly manifest setup, including TV support and touchscreen override.

## Exact build command

The bundle was built from the workspace root with:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
flutter build appbundle --flavor play --release --dart-define=PLAY_STORE_BUILD=true
```

## What the command produces

Flutter writes the Play bundle here:

`build/app/outputs/bundle/playRelease/app-play-release.aab`

For delivery and review, the file was copied into the `aab` folder after removing older bundles so there is no confusion about which artifact is current.

Current artifact name:

`aab/app-play-release.aab`

## How the Play build works

1. `--flavor play` selects the Play Store flavor in Gradle.
2. `--release` makes Flutter produce a signed release bundle.
3. `--dart-define=PLAY_STORE_BUILD=true` activates the Play-store code paths in Dart.
4. `PLAY_STORE_BUILD=true` makes the app hide or disable features that are not allowed for the Play Store version, such as the YouTube conversion flow.
5. The Android manifest and flavor manifests ensure the bundle keeps TV support, a launcher icon, and a touchscreen override for Android TV.

## Current version used for this bundle

- `pubspec.yaml`: `10.5.6+1056`
- `android/app/build.gradle.kts`: `versionCode = 1056`, `versionName = "10.5.6"`

## Verification steps

After building, verify the bundle before uploading:

1. Confirm the packaged manifest package name is `com.torrentspire.ai`.
2. Confirm the manifest still includes TV support entries such as `LEANBACK_LAUNCHER`, `android.software.leanback`, and `tv_banner`.
3. Confirm the Play manifest override keeps `android.hardware.touchscreen` set to `required="false"`.
4. Confirm the `aab` folder contains only the final bundle you want to upload.

## Short explanation for a teacher

This app is built as a Flutter Android App Bundle for Google Play using the `play` flavor. The build uses a special Dart flag, `PLAY_STORE_BUILD=true`, so the app can hide non-Play features and behave like the Play Store version. The final output is a release `.aab` file that Google Play can sign and distribute to devices automatically.

## Useful automation scripts

- `scripts/build_play_release.ps1` runs a Play bundle build and logs the output.
- `scripts/build_play_aab_signed.ps1` performs the stricter signing workflow and copies the final AAB to `aab/ConvertTheSpireReborn.aab`.
- `build_release.sh` shows the Linux shell version of the same general workflow.
