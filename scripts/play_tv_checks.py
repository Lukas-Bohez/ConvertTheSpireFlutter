"""Android TV banner and launcher icon checks for the Play build.

Play's TV review has turned the app down twice: once for the banner and
icon sizes, once for an icon that "does not fill the entire icon space" (a
round logo on a pale square). These checks catch both, on the built app:

  - scripts/verify_play_aab.py runs them on the release AAB before upload;
  - CI runs this file on the Play flavor's debug APK for every change:

        python scripts/play_tv_checks.py build/app/outputs/flutter-apk/app-play-debug.apk

The APK check also reads the manifest with aapt2 (from ANDROID_HOME or
ANDROID_SDK_ROOT, or --aapt2): banner, icon and the Android TV launcher
entry. Needs Pillow. Exits non-zero when any check fails.
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from PIL import Image

# Google's Android TV sizes: the banner is 160x90 dp, the icon 80 dp.
BANNER_SIZES = {"mdpi": (160, 90), "hdpi": (240, 135), "xhdpi": (320, 180),
                "xxhdpi": (480, 270), "xxxhdpi": (640, 360)}
ICON_SIZES = {"ldpi": 60, "mdpi": 80, "hdpi": 120, "xhdpi": 160,
              "xxhdpi": 240, "xxxhdpi": 320}

# Share of an icon's outer ring that may be near-white. The rejected icon
# had a pale margin all the way round (1.0); the current one has none.
MAX_PALE_BORDER = 0.2


def pale_border_share(im):
    """Share of the pixels in the outer 6% ring of [im] that are near-white."""
    im = im.convert("RGB")
    w, h = im.size
    ring = max(1, round(min(w, h) * 0.06))
    px = im.load()
    pale = total = 0
    for y in range(h):
        for x in range(w):
            if ring <= x < w - ring and ring <= y < h - ring:
                continue
            total += 1
            if min(px[x, y]) > 225:
                pale += 1
    return pale / total


def check_tv_graphics(z, res, check):
    """Runs the banner and icon checks on the zip [z] (APK or AAB), whose
    resources are under [res] ("res/" in an APK, "base/res/" in an AAB)."""
    names = set(z.namelist())

    def image(path):
        return Image.open(io.BytesIO(z.read(path))) if path in names else None

    check(not any(re.match(rf"{re.escape(res)}drawable[^/]*/banner\.png$", n)
                  for n in names),
          "no leftover drawable banner")
    for density, size in BANNER_SIZES.items():
        im = image(f"{res}mipmap-{density}-v4/banner.png")
        got = im.size if im else None
        check(got == size, f"banner {density}: {got}, want {size}")
        if im is not None:
            opaque = im.convert("RGBA").getchannel("A").getextrema()[0] == 255
            check(opaque, f"banner {density} opaque")

    for density, n in ICON_SIZES.items():
        im = image(f"{res}mipmap-{density}-v4/ic_launcher.png")
        if im is None:
            check(False, f"icon {density}: missing")
            continue
        im = im.convert("RGBA")
        opaque = im.getchannel("A").getextrema()[0] == 255
        check(im.size == (n, n) and opaque,
              f"icon {density}: {im.size}, opaque={opaque}, want ({n}, {n}) opaque")
        if density == "xhdpi":
            pale = pale_border_share(im)
            check(pale <= MAX_PALE_BORDER,
                  f"icon fills its square: {pale:.0%} of its edge is pale, "
                  f"at most {MAX_PALE_BORDER:.0%}")

    check(f"{res}mipmap-anydpi-v26/ic_launcher.xml" in names,
          "adaptive icon present")
    background = image(f"{res}mipmap-xhdpi-v4/ic_launcher_background.png")
    check(background is not None, "adaptive icon background is an image")
    if background is not None:
        pale = pale_border_share(background)
        check(pale <= MAX_PALE_BORDER,
              f"adaptive icon background is not pale: {pale:.0%} of its edge is")


def find_aapt2(explicit):
    if explicit:
        return explicit
    for var in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk = os.environ.get(var)
        if not sdk:
            continue
        tools = sorted(Path(sdk, "build-tools").glob("*/aapt2*"),
                       key=lambda p: [int(x) if x.isdigit() else x
                                      for x in re.split(r"[.\-]", p.parent.name)])
        if tools:
            return str(tools[-1])
    return shutil.which("aapt2")


def check_apk_manifest(apk, aapt2, check):
    out = subprocess.run([aapt2, "dump", "badging", str(apk)],
                         capture_output=True, text=True, check=True).stdout
    app = re.search(r"^application: .*$", out, re.M)
    app = app.group(0) if app else ""
    check("banner='" in app, "manifest has android:banner")
    check("icon='" in app, "manifest has android:icon")
    check(re.search(r"^leanback-launchable-activity:", out, re.M) is not None,
          "an activity is in the Android TV launcher")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("apk")
    ap.add_argument("--aapt2", help="path to aapt2; found in the Android SDK otherwise")
    args = ap.parse_args()

    failures = []

    def check(ok, label):
        print(("PASS  " if ok else "FAIL  ") + label)
        if not ok:
            failures.append(label)

    with zipfile.ZipFile(args.apk) as z:
        check_tv_graphics(z, "res/", check)
    aapt2 = find_aapt2(args.aapt2)
    if aapt2:
        check_apk_manifest(args.apk, aapt2, check)
    else:
        check(False, "aapt2 found, to read the manifest")

    print("ALL CHECKS PASSED" if not failures else f"{len(failures)} CHECK(S) FAILED")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
