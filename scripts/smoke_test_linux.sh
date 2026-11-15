#!/usr/bin/env bash
# Starts the packaged Linux app on a clean Ubuntu or CachyOS container and checks it is
# still running after half a minute.
#
# The container gets the part of a desktop install the packages count on
# (GTK, sound, PipeWire, GStreamer, OpenGL and OpenGL ES, librsvg, libusb) and
# nothing else: no libmpv, no FFmpeg, no tray library, libsecret or libva.
# LD_BIND_NOW makes a library that is missing a function fail at start
# rather than later.
#
# Usage: scripts/smoke_test_linux.sh <docker-image> <dist-dir>
#   e.g. scripts/smoke_test_linux.sh ubuntu:24.04 dist
set -euo pipefail

IMAGE="${1:?container image, e.g. ubuntu:22.04 or cachyos/distrobox:latest}"
DIST="$(cd "${2:?folder with the packages}" && pwd)"
TARBALL=$(cd "$DIST" && ls ConvertTheSpireReborn-linux-*.tar.gz | head -1)
APPIMAGE=$(cd "$DIST" && ls ConvertTheSpireReborn-linux-*.AppImage | head -1)

docker run --rm -v "$DIST:/dist:ro" -e TARBALL="$TARBALL" -e APPIMAGE="$APPIMAGE" \
  "$IMAGE" bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
. /etc/os-release
if command -v pacman >/dev/null; then
  # Package hooks cannot create a network namespace inside a default Docker
  # container. The container itself is disposable.
  sed -i "/^\[options\]/a DisableSandboxNetwork" /etc/pacman.conf
  pacman -Syu --needed --noconfirm gtk3 gst-plugins-base-libs alsa-lib \
    libpulse pipewire librsvg libusb mesa dbus ttf-dejavu xorg-server-xvfb xorg-xauth \
    ca-certificates >/dev/null
else
  apt-get update -qq
  # Ubuntu 24.04 renamed some of these (libasound2t64, libgtk-3-0t64).
  packages=()
  for p in libgtk-3-0 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
           libasound2 libpulse0 libpipewire-0.3-0 librsvg2-2 libusb-1.0-0 \
           libgl1 libegl1 libgles2 libgl1-mesa-dri dbus fonts-dejavu-core xvfb xauth \
           ca-certificates; do
    policy=$(apt-cache policy "${p}t64")
    if [[ "$policy" == *"Candidate: "[0-9]* ]]; then
      packages+=("${p}t64")
    else
      packages+=("$p")
    fi
  done
  apt-get install -y -qq --no-install-recommends "${packages[@]}" >/dev/null
fi
echo "== $PRETTY_NAME"

run() {
  local label="$1"; shift
  export HOME=$(mktemp -d) LD_BIND_NOW=1
  export XDG_RUNTIME_DIR="$HOME/runtime"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
  mkdir -p "$HOME/Documents" "$HOME/.config"
  printf "XDG_DOCUMENTS_DIR=\"%s/Documents\"\n" "$HOME" > "$HOME/.config/user-dirs.dirs"
  dbus-run-session -- xvfb-run -a -s "-screen 0 1280x800x24" "$@" >"$HOME/app.log" 2>&1 &
  local pid=$!
  sleep 30
  if kill -0 "$pid" 2>/dev/null; then
    echo "OK: $label still running after 30 s"
    kill "$pid"; wait "$pid" 2>/dev/null || true
  else
    echo "FAILED: $label stopped"; cat "$HOME/app.log"; exit 1
  fi
  if grep -E "error while loading shared libraries|symbol lookup error|Segmentation fault|undefined symbol|Failed to initialize MediaKit" "$HOME/app.log"; then
    echo "FAILED: $label"; exit 1
  fi
}

mkdir /opt/app
tar -xzf "/dist/$TARBALL" -C /opt/app
missing=$(cd /opt/app/ConvertTheSpireReborn && { ldd ./convert_the_spire_reborn; for f in lib/*.so*; do [ "$f" = lib/libapp.so ] || ldd "$f"; done; } | grep "not found" | sort -u || true)
if [ -n "$missing" ]; then echo "FAILED: missing libraries"; echo "$missing"; exit 1; fi
run "$TARBALL" /opt/app/ConvertTheSpireReborn/convert_the_spire_reborn

cp "/dist/$APPIMAGE" /opt/app.AppImage
chmod +x /opt/app.AppImage
# No FUSE in a container: the AppImage unpacks itself instead.
export APPIMAGE_EXTRACT_AND_RUN=1
run "$APPIMAGE" /opt/app.AppImage
'
