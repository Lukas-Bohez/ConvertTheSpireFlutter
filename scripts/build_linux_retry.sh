#!/usr/bin/env bash
set -e
export PATH="$HOME/flutter/bin:$PATH"
mkdir -p "$HOME/flutter_linux_build/build/native_assets/linux"
cd "$HOME/flutter_linux_build"
flutter build linux --release
echo "=== Linux build complete ==="
cp -r build/linux/x64/release/bundle/* /mnt/c/development/ConversionFlutter/my_flutter_app/releases/linux/
ls -la /mnt/c/development/ConversionFlutter/my_flutter_app/releases/linux/