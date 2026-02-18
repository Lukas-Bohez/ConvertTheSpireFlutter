#!/bin/bash
set -e

echo "=== Removing old Flutter SDK ==="
rm -rf /opt/flutter

echo "=== Downloading Flutter 3.41.0 ==="
curl -sL https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.0-stable.tar.xz | tar xJ -C /opt

echo "=== Configuring ==="
git config --global --add safe.directory /opt/flutter
export PATH=/opt/flutter/bin:$PATH
flutter --disable-analytics 2>/dev/null || true
flutter config --no-cli-animations 2>/dev/null || true

echo "=== Flutter version ==="
flutter --version
