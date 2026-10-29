#!/usr/bin/env bash
# Builds the Linux packages from Windows, in WSL (Ubuntu):
#
#   wsl -d Ubuntu -- bash scripts/build_linux_wsl.sh
#
# The project is copied into the WSL home first: building on /mnt/c is slow
# and Flutter's plugin links do not work there. The tar.gz and AppImage come
# back to dist/ in the project.
#
# Once per WSL install: bash scripts/linux_build_deps.sh (needs sudo), Rust
# from https://rustup.rs and Flutter in ~/flutter (the version in
# .github/workflows/release.yml).
#
# The release packages are built by the release workflow on Ubuntu 22.04.
# Packages built here take their libraries from this WSL's Ubuntu and need
# a system at least as new.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$HOME/convert-the-spire-linux-build"
export PATH="$HOME/flutter/bin:$HOME/.cargo/bin:$PATH"

# A Windows Flutter on the PATH (/mnt/c/...) cannot build for Linux.
case "$(command -v flutter || true)" in
  /mnt/*|"") echo "Install Flutter for Linux in ~/flutter first." >&2; exit 1 ;;
esac

mkdir -p "$WORK"
rsync -a --delete \
  --exclude '/build/' --exclude '.dart_tool/' --exclude '/dist/' \
  --exclude '/upload/' --exclude '/logs/' --exclude '/coverage/' \
  --exclude '/android/.gradle/' --exclude '/.git/' \
  --exclude '/linux/flutter/ephemeral/' --exclude '/windows/flutter/ephemeral/' \
  --exclude '/macos/Flutter/ephemeral/' \
  "$PROJECT/" "$WORK/"

cd "$WORK"
flutter pub get
flutter build linux --release --no-tree-shake-icons
bash scripts/package_linux.sh "$WORK/dist"

mkdir -p "$PROJECT/dist"
cp "$WORK"/dist/*.tar.gz "$WORK"/dist/*.AppImage "$PROJECT/dist/"
ls -lh "$PROJECT/dist"
