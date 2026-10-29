#!/usr/bin/env bash
# Packages the Linux release after `flutter build linux --release`:
#
#   ConvertTheSpireReborn-linux-x64.tar.gz      extract, run ./convert_the_spire_reborn
#   ConvertTheSpireReborn-linux-x86_64.AppImage  one file: make it executable, run it
#
# Both carry libmpv (the player) and every library it needs that a standard
# desktop install does not have, so the app starts on Ubuntu 22.04 and later
# (and distributions of the same age) with nothing to install. The libraries
# come from the build machine: run this on the OLDEST system the release
# supports (Ubuntu 22.04), so they are never newer than what they run next to.
#
# Left out, because every desktop has them and they must match the system:
# glibc, libstdc++, the graphics drivers, GTK and the libraries under it, and
# a few more (see "Libraries" below). scripts/smoke_test_linux.sh starts the
# result on clean Ubuntu releases.
#
# Usage: scripts/package_linux.sh [output-dir]   (default: dist/)
# Needs: patchelf, file, curl (for the AppImage tool).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:-$ROOT/dist}" && cd "${1:-$ROOT/dist}" && pwd)"
APP=convert_the_spire_reborn
NAME=ConvertTheSpireReborn
APP_ID=com.example.convert_the_spire_reborn

case "$(uname -m)" in
  x86_64) FLUTTER_ARCH=x64; APPIMAGE_ARCH=x86_64 ;;
  aarch64) FLUTTER_ARCH=arm64; APPIMAGE_ARCH=aarch64 ;;
  *) echo "Unsupported machine: $(uname -m)" >&2; exit 1 ;;
esac
BUNDLE="$ROOT/build/linux/$FLUTTER_ARCH/release/bundle"
[ -x "$BUNDLE/$APP" ] || { echo "No release build at $BUNDLE: run flutter build linux --release first" >&2; exit 1; }
VERSION=$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/pubspec.yaml" | tr -d '\r' | cut -d+ -f1)

STAGE="$OUT/$NAME"
rm -rf "$STAGE"
cp -a "$BUNDLE" "$STAGE"

# --- Libraries -------------------------------------------------------------
#
# Every library the program and its libraries load comes along, except:
#
# 1. What GTK loads: libflutter_linux_gtk.so's dependencies. Every system
#    that runs the app has GTK 3, and these must be the system's own: an
#    older copy taken along would stand in for its newer one.
# 2. The AppImage project's exclude list: glibc, libstdc++, the graphics
#    drivers' libraries, X11 and the like. libjack is taken along after all:
#    libmpv needs it, and many desktops do not have it.
# 3. Libraries that talk to a part of the system and must match it (sound
#    servers, GStreamer and its plugins, TLS, the SVG library the icon
#    loaders use). Desktops all have them.
#
# The tray library, libsecret, libva, the Vulkan loader (it finds the
# system's drivers itself), the X11 extensions mpv uses and the like do come
# along: not every desktop has them, and nothing of the system's loads them
# in their place. scripts/smoke_test_linux.sh checks the result on
# clean Ubuntu releases that have only GTK, sound and graphics.

# From https://github.com/AppImageCommunity/pkg2appimage/blob/19e30b276ffedf4d3b4b56bc6320f463625a74f8/excludelist
EXCLUDE_LIST='
ld-linux.so.2 ld-linux-x86-64.so.2 ld-linux-aarch64.so.1 libanl.so.1
libBrokenLocale.so.1 libcidn.so.1 libc.so.6 libdl.so.2 libm.so.6
libmvec.so.1 libnss_compat.so.2 libnss_dns.so.2 libnss_files.so.2
libnss_hesiod.so.2 libnss_nisplus.so.2 libnss_nis.so.2 libpthread.so.0
libresolv.so.2 librt.so.1 libthread_db.so.1 libutil.so.1 libstdc++.so.6
libGL.so.1 libEGL.so.1 libGLdispatch.so.0 libGLX.so.0 libOpenGL.so.0
libdrm.so.2 libglapi.so.0 libgbm.so.1 libxcb.so.1 libX11.so.6
libX11-xcb.so.1 libwayland-client.so.0 libasound.so.2 libfontconfig.so.1
libfreetype.so.6 libharfbuzz.so.0 libcom_err.so.2 libexpat.so.1
libgcc_s.so.1 libgpg-error.so.0 libICE.so.6 libSM.so.6 libusb-1.0.so.0
libuuid.so.1 libz.so.1 libpipewire-0.3.so.0 libxcb-dri3.so.0
libxcb-dri2.so.0 libfribidi.so.0 libgmp.so.10
'
EXCLUDE_PATTERNS='
^libpulse\.so ^libpulse-simple\.so ^libpulsecommon-
^libgst[a-z]*-1\.0\.so ^liborc-0\.4\.so ^libssl\.so ^libcrypto\.so
^libgnutls\.so ^libnettle\.so ^libhogweed\.so ^libtasn1\.so ^libp11-kit\.so
^libidn2\.so ^libunistring\.so ^libxml2\.so ^librsvg-2\.so ^libdbus-1\.so
^libsystemd\.so ^libudev\.so ^libgcrypt\.so ^libkrb5 ^libk5crypto
^libgssapi_krb5 ^libkeyutils ^libcrypt\.so
'
GTK_LIBS=$(ldd "$STAGE/lib/libflutter_linux_gtk.so" | awk '/=> \// { print $1 }' | tr '\n' ' ')

excluded() {
  local name="$1"
  case " $(echo $EXCLUDE_LIST) $GTK_LIBS " in *" $name "*) return 0 ;; esac
  local pattern
  for pattern in $EXCLUDE_PATTERNS; do
    [[ "$name" =~ $pattern ]] && return 0
  done
  return 1
}

# Everything the program and its libraries load, with where the build
# machine has it (ldd lists the whole tree).
needed() {
  {
    ldd "$STAGE/$APP"
    find "$STAGE/lib" -maxdepth 1 -name '*.so*' -type f ! -name libapp.so -print0 \
      | xargs -0 -n1 ldd 2>/dev/null
  } | awk '/=> \// { print $1, $3 }' | sort -u
}

echo "== Taking libraries along"
added=0
while read -r soname path; do
  [ -e "$STAGE/lib/$soname" ] && continue
  excluded "$soname" && continue
  cp -L "$path" "$STAGE/lib/$soname"
  echo "   $soname"
  added=$((added + 1))
done < <(needed)
echo "   $added libraries"

# The program finds them in lib/, and each library its own in the same
# folder. libapp.so is the compiled Dart code: no dependencies, left as it is.
patchelf --set-rpath '$ORIGIN/lib' "$STAGE/$APP"
find "$STAGE/lib" -maxdepth 1 -name '*.so*' -type f ! -name libapp.so -print0 \
  | while IFS= read -r -d '' so; do
      if [[ "$(file -b "$so")" == ELF* ]]; then
        chmod u+w "$so"
        patchelf --set-rpath '$ORIGIN' "$so"
      fi
    done

# Nothing may be missing here. Whether the left-out libraries are on other
# systems is what the smoke test checks.
missing=$(cd "$STAGE" && { ldd "./$APP"; find lib -maxdepth 1 -name '*.so*' -type f ! -name libapp.so -print0 | xargs -0 -n1 ldd 2>/dev/null; } | grep 'not found' | sort -u || true)
if [ -n "$missing" ]; then
  echo "Missing libraries:" >&2
  echo "$missing" >&2
  exit 1
fi

# --- Icon and menu entry -----------------------------------------------------

cp "$ROOT/assets/icons/app_logo_384.png" "$STAGE/$APP_ID.png"
cat > "$STAGE/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Convert the Spire Reborn
GenericName=Media player and downloader
Comment=Download, convert, play and cast music and videos
Exec=$APP %U
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Player;
MimeType=x-scheme-handler/magnet;application/x-bittorrent;audio/mpeg;audio/mp4;audio/x-m4a;audio/flac;audio/x-flac;audio/wav;audio/x-wav;audio/ogg;audio/x-vorbis+ogg;audio/opus;audio/x-opus+ogg;audio/aac;audio/x-ms-wma;video/mp4;video/x-matroska;video/x-msvideo;video/webm;video/quicktime;video/x-ms-wmv;video/x-flv;video/x-m4v;
StartupWMClass=$APP_ID
StartupNotify=true
X-AppImage-Version=$VERSION
EOF
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$STAGE/$APP_ID.desktop"
fi

# --- tar.gz ----------------------------------------------------------------

TARBALL="$OUT/$NAME-linux-$FLUTTER_ARCH.tar.gz"
tar -C "$OUT" -czf "$TARBALL" "$NAME"
echo "== $(du -h "$TARBALL" | cut -f1)  $TARBALL"

# --- AppImage --------------------------------------------------------------

APPDIR="$OUT/AppDir"
rm -rf "$APPDIR"
cp -a "$STAGE" "$APPDIR"
ln -s "$APP" "$APPDIR/AppRun"
ln -s "$APP_ID.png" "$APPDIR/.DirIcon"

TOOLS="$OUT/.tools"
mkdir -p "$TOOLS"
TOOL="$TOOLS/appimagetool-$APPIMAGE_ARCH.AppImage"
RUNTIME="$TOOLS/runtime-$APPIMAGE_ARCH"
# Fixed versions. The runtime is the static one: the AppImage then runs
# without libfuse2, which Ubuntu 22.04 and later do not install.
[ -f "$TOOL" ] || curl -fsSL -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-$APPIMAGE_ARCH.AppImage"
[ -f "$RUNTIME" ] || curl -fsSL -o "$RUNTIME" \
  "https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-$APPIMAGE_ARCH"
chmod +x "$TOOL"

APPIMAGE="$OUT/$NAME-linux-$APPIMAGE_ARCH.AppImage"
rm -f "$APPIMAGE"
# Extracted, so the build machine needs no FUSE either.
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=$APPIMAGE_ARCH "$TOOL" --no-appstream \
  --runtime-file "$RUNTIME" "$APPDIR" "$APPIMAGE"
chmod +x "$APPIMAGE"
rm -rf "$APPDIR"
echo "== $(du -h "$APPIMAGE" | cut -f1)  $APPIMAGE"
