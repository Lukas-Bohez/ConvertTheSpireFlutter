#!/bin/bash
set -e
mkdir -p aab

echo "Building AAB (Play Store + Android TV)..."
flutter build appbundle --release --flavor play --build-number=700
cp build/app/outputs/bundle/playRelease/app-play-release.aab \
   aab/app-play-release-v700.aab

echo "Building fat universal APK (sideload)..."
flutter build apk --release --flavor play --no-split-per-abi --build-number=700
cp build/app/outputs/flutter-apk/app-play-release.apk \
   aab/app-play-universal-v700.apk

echo "Done. Outputs in aab/"
