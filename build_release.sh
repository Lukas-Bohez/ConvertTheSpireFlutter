#!/bin/bash
set -e
mkdir -p aab

echo "Building AAB (Play Store + Android TV)..."
flutter build appbundle --release --flavor play --build-number=701 \
  --dart-define=PLAY_STORE_BUILD=true
cp build/app/outputs/bundle/playRelease/app-play-release.aab \
  aab/app-play-release-v701.aab

echo "Building fat universal APK (full sideload)..."
flutter build apk --release --flavor full --build-number=701 \
  --dart-define=PLAY_STORE_BUILD=false
cp build/app/outputs/flutter-apk/app-full-release.apk \
  aab/app-full-universal-v701.apk

echo "Done. Outputs in aab/"
