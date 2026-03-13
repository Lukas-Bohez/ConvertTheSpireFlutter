#!/bin/sh
set -eu
echo "==== System info ===="
uname -a || true
if command -v lsb_release >/dev/null 2>&1; then
  lsb_release -a || true
fi

echo "\n==== libstdc++ available via ldconfig ===="
ldconfig -p | grep libstdc++ || true

echo "\n==== Inspect common libstdc++.so.6 locations ===="
for p in /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /lib/x86_64-linux-gnu/libstdc++.so.6 /usr/local/lib64/libstdc++.so.6; do
  if [ -e "$p" ]; then
    echo "-- $p --"
    strings "$p" 2>/dev/null | grep GLIBCXX_3.4 || true
  else
    echo "(not found) $p"
  fi
done

echo "\n==== Find other libstdc++.so.6 (may take a moment) ===="
find /usr -maxdepth 4 -type f -name 'libstdc++.so.6' -exec sh -c 'echo "== {} =="; strings {} 2>/dev/null | grep GLIBCXX_3.4 || true' \; 2>/dev/null || true

PLUGIN_PATH="/home/lukas/Documenten/lib/libmedia_kit_video_plugin.so"
echo "\n==== Plugin file info ===="
if [ -e "$PLUGIN_PATH" ]; then
  ls -l "$PLUGIN_PATH" || true
  file "$PLUGIN_PATH" || true
  echo "\n==== ldd $PLUGIN_PATH ===="
  ldd "$PLUGIN_PATH" || true
  echo "\n==== readelf -Ws (symbols, may be large) ===="
  if command -v readelf >/dev/null 2>&1; then
    readelf -Ws "$PLUGIN_PATH" | head -n 200 || true
  fi
else
  echo "Plugin not found at $PLUGIN_PATH"
fi

echo "\n==== Environment ===="
env | sort

echo "\n==== Done ===="
