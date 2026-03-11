#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for libmpv
if ! ldconfig -p | grep -q libmpv; then
  if command -v zenity &>/dev/null; then
    zenity --error --text="libmpv is required but not installed.\n\nInstall it with:\n  sudo apt install libmpv-dev mpv\n(or equivalent for your distro)" --title="Missing Dependency"
  elif command -v kdialog &>/dev/null; then
    kdialog --error "libmpv is required but not installed.\nInstall: sudo apt install libmpv-dev mpv"
  else
    echo "ERROR: libmpv is required. Install with: sudo apt install libmpv-dev mpv" >&2
  fi
  exit 1
fi

exec "$SCRIPT_DIR/convert_the_spire_reborn" "$@"
