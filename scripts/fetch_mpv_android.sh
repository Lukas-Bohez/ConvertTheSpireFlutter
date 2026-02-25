#!/usr/bin/env bash
# Helper script to download prebuilt libmpv binaries for Android and place
# them under android/app/src/main/jniLibs so that media_kit can load them.
#
# Usage:
#   chmod +x scripts/fetch_mpv_android.sh
#   ./scripts/fetch_mpv_android.sh
#
# The script grabs the latest "media_kit_test_android-<abi>.apk" from the
# media_kit GitHub releases page, extracts the .so files, and copies them to
# the appropriate jniLibs folder.
#
# You may need 'curl', 'unzip' and 'apktool' (or just unzip) installed.
#
set -euo pipefail

RELEASE_URL_BASE="https://github.com/media-kit/media-kit/releases/download/media_kit-v1.1.10"
ABIS=("android-arm64-v8a" "android-armeabi-v7a")

DEST="android/app/src/main/jniLibs"
mkdir -p "${DEST}"

echo "Fetching libmpv for ABIs: ${ABIS[*]}"

for abi in "${ABIS[@]}"; do
  apkname="media_kit_test_${abi}.apk"
  echo "Downloading ${apkname}..."
  curl -L -o "${apkname}" "${RELEASE_URL_BASE}/${apkname}"

  # the APK is just a zip; extract libmpv.so
  tmpdir=$(mktemp -d)
  unzip -q "${apkname}" -d "${tmpdir}"
  sofile=$(find "${tmpdir}" -name libmpv.so | head -n1)
  if [ -z "${sofile}" ]; then
    echo "ERROR: libmpv.so not found inside ${apkname}" >&2
    exit 1
  fi

  mkdir -p "${DEST}/${abi.replace("android-","")}" || true
  cp "${sofile}" "${DEST}/${abi.replace("android-","")}/libmpv.so"
  echo "Copied libmpv.so for ${abi}"

  rm -rf "${tmpdir}"
  rm "${apkname}"
done

echo "Done.  Check android/app/src/main/jniLibs/"