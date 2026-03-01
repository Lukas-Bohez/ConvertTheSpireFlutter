#!/bin/bash
# Build Linux release using WSL
# Usage: Run from WSL:  bash scripts/build_linux_wsl.sh
#   Or from PowerShell: wsl -e bash scripts/build_linux_wsl.sh
set -e

# Locate Flutter SDK
if [ -d "$HOME/flutter/bin" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
elif [ -d "/opt/flutter/bin" ]; then
  export PATH="/opt/flutter/bin:$PATH"
fi

# Determine project directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# If running on /mnt/ (NTFS), copy to native FS to avoid symlink issues
if echo "$PROJECT_DIR" | grep -q '^/mnt/'; then
  BUILD_DIR="$HOME/flutter_linux_build"
  echo "=== Detected NTFS mount — copying to native filesystem ==="
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  rsync -a \
    --exclude='build/' \
    --exclude='.dart_tool/' \
    --exclude='.pub-cache/' \
    --exclude='releases/' \
    --exclude='.git/' \
    --exclude='*.log' \
    "$PROJECT_DIR/" "$BUILD_DIR/"
  RELEASE_DIR="$PROJECT_DIR/releases/linux"
  cd "$BUILD_DIR"
else
  RELEASE_DIR="$PROJECT_DIR/releases/linux"
  cd "$PROJECT_DIR"
fi

echo "=== Installing dependencies ==="
flutter pub get --no-example

echo "=== Analyzing ==="
flutter analyze || true

echo "=== Building Linux release ==="
flutter build linux --release

echo "=== Copying to releases ==="
mkdir -p "$RELEASE_DIR"
cp -r build/linux/x64/release/bundle/* "$RELEASE_DIR/"

echo "=== Linux build complete ==="
ls -la "$RELEASE_DIR/"
