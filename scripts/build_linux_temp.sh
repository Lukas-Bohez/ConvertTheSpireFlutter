#!/usr/bin/env bash
set -e
SRC="/mnt/c/development/ConversionFlutter/my_flutter_app"
DEST="$HOME/flutter_linux_build"
mkdir -p "$DEST"
rsync -a --delete --exclude='.dart_tool' --exclude='build/windows' --exclude='build/app' --exclude='.gradle' --exclude='android/.gradle/' "$SRC/" "$DEST/"
cd "$DEST"
export PATH="$HOME/flutter/bin:$PATH"
flutter build linux --release
echo "=== Linux build complete ==="
cp -r build/linux/x64/release/bundle/* "$SRC/releases/linux/"
ls -la "$SRC/releases/linux/"