#!/bin/bash
set -e
export HOME=/home/lukas
export PATH="$HOME/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
BUILD_DIR="$HOME/flutter_linux_build"
SRC=/mnt/c/development/ConversionFlutter/my_flutter_app

echo "=== Syncing source ==="
cd "$BUILD_DIR"
rsync -a --delete --exclude=build/ --exclude=.dart_tool/ --exclude=.pub-cache/ --exclude=releases/ --exclude=.git/ "$SRC/" .
echo "=== Sync done ==="

echo "=== pub get ==="
flutter pub get --no-example 2>&1 | tail -5
echo "=== pub get done ==="

echo "=== Building Linux release ==="
mkdir -p build/native_assets/linux
flutter build linux --release 2>&1 | tail -10
echo "=== Build done ==="

echo "=== Copying to releases ==="
RELEASE_DIR="$SRC/releases/linux"
mkdir -p "$RELEASE_DIR"
cp -r build/linux/x64/release/bundle/* "$RELEASE_DIR/"
ls -la "$RELEASE_DIR/convert_the_spire_reborn"
echo "=== LINUX BUILD COMPLETE ==="