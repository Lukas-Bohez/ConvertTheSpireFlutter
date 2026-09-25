"""Android TV banner and launcher icon checks for the Play build.

Play's TV review has turned the app down twice: once for the banner and
icon sizes, once for an icon that "does not fill the entire icon space" (the
logo small in a wide margin). These checks catch both, on the built app:

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

# How much of the icon the logo must span, across and down. The rejected
# icon's logo spanned 68% of it; the current one spans 85%.
MIN_LOGO_SPAN = 0.8


def logo_span(im):
    """How much of [im] the logo spans, across and down, as a share of its
    size: the extent of what differs from the background (the top-left
    pixel) or is not see-through."""
    im = im.convert("RGBA")
    background = im.getpixel((0, 0))
    mask = Image.new("L", im.size, 0)
    src, dst = im.load(), mask.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = src[x, y]
            if background[3] == 0:
                differs = a > 40
            else:
                differs = max(abs(r - background[0]), abs(g - background[1]),
                              abs(b - background[2])) > 40
            if differs:
                dst[x, y] = 255
    box = mask.getbbox()
    if box is None:
        return 0.0, 0.0
    return (box[2] - box[0]) / im.width, (box[3] - box[1]) / im.height


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
            across, down = logo_span(im)
            check(min(across, down) >= MIN_LOGO_SPAN,
                  f"logo fills the icon: spans {across:.0%} x {down:.0%}, "
                  f"at least {MIN_LOGO_SPAN:.0%}")

    check(f"{res}mipmap-anydpi-v26/ic_launcher.xml" in names,
          "adaptive icon present")
    foreground = image(f"{res}mipmap-xhdpi-v4/ic_launcher_foreground.png")
    check(foreground is not None, "adaptive icon foreground present")
    if foreground is not None:
        # Launchers show the centre 72dp of the 108dp layer.
        visible = foreground.width * 72 / 108
        across, down = (s * foreground.width / visible
                        for s in logo_span(foreground))
        check(min(across, down) >= MIN_LOGO_SPAN,
              f"logo fills the adaptive icon: spans {across:.0%} x {down:.0%} "
              f"of what shows, at least {MIN_LOGO_SPAN:.0%}")
        check(max(across, down) <= 1.0,
              f"logo is not cut off in the adaptive icon: spans "
              f"{max(across, down):.0%} of what shows, at most 100%")


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
