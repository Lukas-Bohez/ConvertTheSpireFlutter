#!/bin/bash
set -euo pipefail

APP="${APP_NAME:-convert_the_spire_reborn}"
OUT="${OUTPUT_NAME:-ConvertTheSpireReborn}"
BUNDLE="$GITHUB_WORKSPACE/build/linux/x64/release/bundle"
APPDIR="$GITHUB_WORKSPACE/AppDir"

echo "Building AppImage for $APP..."

if [ ! -d "$BUNDLE" ]; then
    echo "ERROR: bundle missing at $BUNDLE"
    exit 1
fi

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib"
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"

# Collect and bundle .so dependencies (excluding ABI-gated system libs)
EXCLUDE='(libpthread|libc\.so|libdl\.so|libm\.so|librt\.so|ld-linux|ld-musl|libGL|libEGL|libvulkan|libdrm|libX|libxcb|libxkb)'
collect_libs() {
    ldd "$1" 2>/dev/null | awk '/=>/ { print $3 }' 
        | grep -Ev '(not found|^$)' | grep -Ev "$EXCLUDE" || true
}

ALL_LIBS=$(collect_libs "$APPDIR/usr/bin/$APP")
if [ -d "$BUNDLE/lib" ]; then
    while IFS= read -r so; do
        [ -f "$so" ] || continue
        MORE_LIBS=$(collect_libs "$so")
        ALL_LIBS=$(printf '%s
%s' "$ALL_LIBS" "$MORE_LIBS")
    done < <(find "$BUNDLE/lib" -name '*.so*' -type f)
fi

echo "$ALL_LIBS" | sort -u | while IFS= read -r lib; do
    if [ -f "$lib" ]; then
        dest="$APPDIR/usr/lib/$(basename "$lib")"
        if [ ! -f "$dest" ]; then
            cp -L "$lib" "$dest"
            echo "Bundled: $(basename "$lib")"
        fi
    fi
done

# Patch RPATHs
patchelf --set-rpath '$ORIGIN/../lib:$ORIGIN/lib' "$APPDIR/usr/bin/$APP"
find "$APPDIR/usr/lib" -name '*.so*' -type f -print0 
    | xargs -0 -I{} patchelf --set-rpath '$ORIGIN' {} 2>/dev/null || true

# Write AppRun script
cat > "$APPDIR/AppRun" <<EOF
#!/bin/sh
SELF=\$(readlink -f "\$0")
HERE=\$(dirname "\$SELF")
export LD_LIBRARY_PATH="\${HERE}/usr/lib:\${HERE}/usr/bin/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export XDG_DATA_DIRS="\${HERE}/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
exec "\${HERE}/usr/bin/$APP" "\$@"
EOF
chmod +x "$APPDIR/AppRun"

# Write .desktop file
cat > "$APPDIR/$APP.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Convert the Spire Reborn
Exec=$APP
Icon=$APP
Categories=AudioVideo;Audio;Video;Utility;
Comment=Download, convert, play and cast media
Terminal=false
EOF

# Icon
ICON="$GITHUB_WORKSPACE/assets/icons/favicon-192x192.png"
if [ -f "$ICON" ]; then
    cp "$ICON" "$APPDIR/$APP.png"
else
    # Fallback to a simple placeholder icon
    python3 -c "
data = bytes([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,
              0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
              0x08,0x06,0x00,0x00,0x00,0x1f,0x15,0xc4,0x89,0x00,0x00,0x00,
              0x0a,0x49,0x44,0x41,0x54,0x78,0x9c,0x62,0x00,0x01,0x00,0x00,
              0x05,0x00,0x01,0x0d,0x0a,0x2d,0xb4,0x00,0x00,0x00,0x00,0x49,
              0x45,0x4e,0x44,0xae,0x42,0x60,0x82])
open('${APPDIR}/${APP}.png', 'wb').write(data)
"
fi

# Download and run appimagetool
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
echo "Downloading appimagetool..."
curl -fsSL -o /tmp/appimagetool.AppImage "$APPIMAGETOOL_URL"
chmod +x /tmp/appimagetool.AppImage

echo "Running appimagetool..."
cd "$GITHUB_WORKSPACE"
ARCH=x86_64 /tmp/appimagetool.AppImage --no-appstream 
  "$APPDIR" "$GITHUB_WORKSPACE/${OUT}-linux.AppImage"

echo "AppImage build complete."
ls -lh "$GITHUB_WORKSPACE/${OUT}-linux.AppImage"
