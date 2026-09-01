#!/bin/bash
set -e

# Version comes from pubspec.yaml ONLY. Never pass --build-number here and
# never hand-edit android/local.properties -- Flutter regenerates
# flutter.versionCode/flutter.versionName from pubspec.yaml's `version:`
# line on every build, so anything else is silently discarded.
VERSION=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '\r' | head -n1)
echo "Building version $VERSION (from pubspec.yaml)"

mkdir -p aab

echo "Building AAB (Play Store + Android TV)..."
flutter build appbundle --release --flavor play --no-tree-shake-icons \
  --dart-define=PLAY_STORE_BUILD=true --dart-define=GITHUB_RELEASE=false
cp build/app/outputs/bundle/playRelease/app-play-release.aab \
  "aab/bitplayer-v${VERSION}-play-release.aab"

echo "Building fat universal APK (full sideload)..."
flutter build apk --release --flavor full --no-tree-shake-icons \
  --dart-define=PLAY_STORE_BUILD=false --dart-define=GITHUB_RELEASE=true
cp build/app/outputs/flutter-apk/app-full-release.apk \
  "aab/ConvertTheSpireReborn-v${VERSION}-full-universal.apk"

echo "Done. Outputs in aab/:"
ls -la aab/*.aab aab/*.apk 2>/dev/null
