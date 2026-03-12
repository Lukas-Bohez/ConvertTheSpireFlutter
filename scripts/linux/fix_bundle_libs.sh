#!/usr/bin/env bash
# Copies built plugin .so files into the Linux release bundle lib directory.
# Usage: run from repository root: scripts/linux/fix_bundle_libs.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BUILD_BUNDLE="$ROOT_DIR/build/linux/x64/release/bundle"
PLUGINS_DIR="$ROOT_DIR/build/linux/x64/release/plugins"

if [ ! -d "$BUILD_BUNDLE/lib" ]; then
  echo "Bundle lib dir not found: $BUILD_BUNDLE/lib"
  exit 1
fi

echo "Copying plugin .so files from $PLUGINS_DIR to $BUILD_BUNDLE/lib"
shopt -s nullglob
count=0
for so in "$PLUGINS_DIR"/*/*.so; do
  echo " - copying $(basename "$so")"
  cp -f "$so" "$BUILD_BUNDLE/lib/"
  count=$((count+1))
done
shopt -u nullglob

echo "Copied $count plugin library files. Bundle lib now contains:"
ls -la "$BUILD_BUNDLE/lib"

exit 0
