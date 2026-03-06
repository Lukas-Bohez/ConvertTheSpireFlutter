#!/bin/bash
set -e
export PATH="$HOME/flutter/bin:$PATH"
BUILD_DIR="$HOME/flutter_linux_build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
rsync -a \
  --exclude='build/' \
  --exclude='.dart_tool/' \
  --exclude='.pub-cache/' \
  --exclude='releases/' \
  --exclude='.git/' \
  --exclude='*.log' \
  --exclude='android/.gradle/' \
  /mnt/c/development/ConversionFlutter/my_flutter_app/ "$BUILD_DIR/"
cd "$BUILD_DIR"
flutter pub get --no-example
flutter build linux --release
RELEASE_DIR="/mnt/c/development/ConversionFlutter/my_flutter_app/releases/linux"
mkdir -p "$RELEASE_DIR"
cp -r build/linux/x64/release/bundle/* "$RELEASE_DIR/"
echo "=== Linux build complete ==="
ls -la "$RELEASE_DIR/"
