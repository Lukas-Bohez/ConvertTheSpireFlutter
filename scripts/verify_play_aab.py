"""Checks a Play Store AAB before it is uploaded.

Run from the repo root:

    python scripts/verify_play_aab.py aab/ConvertTheSpireReborn-v14.5.0+1298-play.aab \
        --previous path/to/the-last-accepted-upload.aab

It checks what Play review and the upload itself have rejected before:
  - version matches pubspec.yaml, package and label are the Play ones
  - Android TV: LEANBACK_LAUNCHER, leanback/touchscreen not required,
    android:banner = @mipmap/banner at 160x90 to 640x360 (320x180 at xhdpi),
    launcher icon 160x160 at xhdpi, opaque and filling its square ("no
    full-size app banner and/or icon"); see play_tv_checks.py
  - the bundled CHANGELOG.md has this version, so What's new shows it
  - with --previous: signed with the same key as that earlier upload

Needs Pillow and Java. bundletool is found through --bundletool, the
BUNDLETOOL_JAR environment variable, or downloaded once with
`gh release download --repo google/bundletool --pattern "bundletool-all-*.jar"`.
Exits non-zero when any check fails.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from play_tv_checks import check_tv_graphics

ROOT = Path(__file__).resolve().parents[1]
ANDROID_STUDIO_JBR = Path(r"C:\Program Files\Android\Android Studio\jbr")

failures = 0


def check(ok, label):
    global failures
    print(("PASS  " if ok else "FAIL  ") + label)
    if not ok:
        failures += 1


def tool(name):
    """A JDK tool from JAVA_HOME, Android Studio's JBR, or the PATH."""
    exe = name + (".exe" if os.name == "nt" else "")
    for home in (os.environ.get("JAVA_HOME"), ANDROID_STUDIO_JBR):
        if home and (Path(home) / "bin" / exe).exists():
            return str(Path(home) / "bin" / exe)
    found = shutil.which(name)
    if not found:
        sys.exit(f"{name} not found: set JAVA_HOME")
    return found


def find_bundletool(arg):
    for candidate in (arg, os.environ.get("BUNDLETOOL_JAR")):
        if candidate and Path(candidate).exists():
            return candidate
    jars = sorted(ROOT.glob("bundletool-all-*.jar")) + sorted(Path.cwd().glob("bundletool-all-*.jar"))
    if jars:
        return str(jars[-1])
    sys.exit("bundletool not found: pass --bundletool or set BUNDLETOOL_JAR")


def signer_sha256(aab):
    out = subprocess.run([tool("keytool"), "-printcert", "-jarfile", str(aab)],
                         capture_output=True, text=True).stdout
    m = re.search(r"SHA256:\s*([0-9A-F:]+)", out)
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("aab")
    ap.add_argument("--previous", help="an AAB Play already accepted, to compare signing keys")
    ap.add_argument("--bundletool", help="path to bundletool-all-*.jar")
    args = ap.parse_args()
    aab = Path(args.aab)

    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    name, code = re.search(r"^version:\s*([\d.]+)\+(\d+)", pubspec, re.M).groups()

    manifest = subprocess.run(
        [tool("java"), "-jar", find_bundletool(args.bundletool), "dump", "manifest",
         "--bundle", str(aab)], capture_output=True, text=True, check=True).stdout
    app = re.search(r"<application[^>]*>", manifest).group(0)

    def attr(tag, key):
        m = re.search(rf'{key}="([^"]*)"', tag)
        return m.group(1) if m else None

    def feature_not_required(feature):
        return any(attr(t, "android:name") == feature and attr(t, "android:required") == "false"
                   for t in re.findall(r"<uses-feature[^>]*>", manifest))

    check(attr(manifest, "android:versionCode") == code
          and attr(manifest, "android:versionName") == name,
          f"version {name}+{code} (pubspec.yaml)")
    check(attr(manifest, "package") == "com.torrentspire.ai", "package com.torrentspire.ai")
    check(attr(app, "android:label") == "BitPlayer", "label BitPlayer")
    check(attr(app, "android:banner") == "@mipmap/banner", "android:banner = @mipmap/banner")
    check(attr(app, "android:icon") == "@mipmap/ic_launcher", "android:icon = @mipmap/ic_launcher")
    check(attr(app, "android:roundIcon") is None, "no android:roundIcon")
    check("android.intent.category.LEANBACK_LAUNCHER" in manifest, "LEANBACK_LAUNCHER activity")
    check(feature_not_required("android.software.leanback"), "leanback not required")
    check(feature_not_required("android.hardware.touchscreen"), "touchscreen not required")

    with zipfile.ZipFile(aab) as z:
        check_tv_graphics(z, "base/res/", check)
        changelog = z.read("base/assets/flutter_assets/CHANGELOG.md").decode("utf-8")
        check(f"## {name}+{code}" in changelog, f"bundled CHANGELOG.md has {name}+{code}")

    signer = signer_sha256(aab)
    print(f"      signer SHA-256: {signer}")
    check(signer is not None, "AAB is signed")
    if args.previous:
        previous = signer_sha256(args.previous)
        check(signer == previous, f"same signing key as {Path(args.previous).name}")

    print("ALL CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
