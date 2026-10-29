#!/usr/bin/env bash
# Installs what building the Linux app needs, on Ubuntu or Debian (Ubuntu
# 22.04 or later). Flutter and Rust (https://rustup.rs, for metadata_god)
# are installed separately.
#
#   bash scripts/linux_build_deps.sh
set -euo pipefail

SUDO=""
[ "$(id -u)" = 0 ] || SUDO=sudo

$SUDO apt-get update
# GitHub's Ubuntu 22.04 runners have LLVM's libunwind-14-dev, which conflicts
# with the libunwind-dev that GStreamer's headers need.
if [ "${GITHUB_ACTIONS:-}" = true ] && dpkg -s libunwind-14-dev >/dev/null 2>&1; then
  $SUDO apt-get remove -y libunwind-14-dev
fi
# The Flutter toolchain, then what the plugins build against: libmpv and
# epoxy (the player), libsecret (secure storage), the tray library,
# GStreamer (audioplayers), json-glib (ffmpeg_kit). The last line is for
# scripts/package_linux.sh.
$SUDO apt-get install -y --no-install-recommends \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libmpv-dev libepoxy-dev \
  libsecret-1-dev libjsoncpp-dev \
  libayatana-appindicator3-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  libjson-glib-dev \
  patchelf file curl desktop-file-utils
