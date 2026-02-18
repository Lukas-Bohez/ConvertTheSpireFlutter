#!/bin/bash
set -e

export PATH=/opt/flutter/bin:$PATH
export FLUTTER_ROOT=/opt/flutter

# Convert Windows path to WSL path
PROJECT_DIR=$(wslpath 'C:\development\ConversionFlutter\my_flutter_app')

cd "$PROJECT_DIR"

echo "=== Running flutter pub get ==="
flutter pub get --no-example

echo "=== Building Linux release ==="
flutter build linux --release

echo "=== Copying to releases ==="
mkdir -p "$PROJECT_DIR/releases/linux"
cp -r "$PROJECT_DIR/build/linux/x64/release/bundle/"* "$PROJECT_DIR/releases/linux/"

echo "=== Linux build complete ==="
ls -la "$PROJECT_DIR/releases/linux/"
