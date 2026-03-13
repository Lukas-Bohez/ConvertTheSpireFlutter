#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer bundled libstdc++/libgcc so the binary works on older distros
# that don't have GLIBCXX_3.4.29 / CXXABI_1.3.13 (Ubuntu 20.04 etc.)
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:${LD_LIBRARY_PATH:-}"

# Check for libmpv — it is NOT bundled and must be installed by the user
if ! ldconfig -p | grep -q libmpv; then
  if command -v zenity &>/dev/null; then
    zenity --error \
      --title="Missing Dependency" \
      --text="libmpv is required but not installed.\n\nInstall it with:\n  sudo apt install libmpv-dev mpv\n(or equivalent for your distro)"
  elif command -v kdialog &>/dev/null; then
    kdialog --error "libmpv is required but not installed.\nInstall: sudo apt install libmpv-dev mpv"
  else
    echo "ERROR: libmpv is required. Install with: sudo apt install libmpv-dev mpv" >&2
  fi
  exit 1
fi

exec "$SCRIPT_DIR/convert_the_spire_reborn" "$@"