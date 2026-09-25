"""Android launcher icons for the GitHub (full) flavor.

The orb from assets/icons/app_icon.ico, the Windows app icon, on white:

  - adaptive icon: the orb in the centre 66dp of the 108dp foreground layer,
    over the white background in res/drawable/ic_launcher_background.xml.
    66dp is the part no launcher shape cuts into; the orb's stepped pixel
    outline would stick out of a round mask any closer to the edge. Android
    shows only the centre 72dp; the orb used to be 101dp wide, so its edge
    was cut off all round and what was left was blown up.
  - legacy icon: the orb on white at 90% of the icon, 80dp (160x160 px at
    xhdpi), the size Android TV asks for; the GitHub APK runs on TVs too.

Run from the repo root:  python scripts/generate_full_icons.py  (needs Pillow)
"""
from pathlib import Path

from PIL import Image

DENSITIES = {"ldpi": 0.75, "mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0,
             "xxhdpi": 3.0, "xxxhdpi": 4.0}
ADAPTIVE_ORB_DP = 66
LEGACY_ORB = 0.9


def orb():
    """The orb, from the largest image in the .ico, cropped to its content."""
    root = Path(__file__).resolve().parents[1]
    ico = Image.open(root / "assets" / "icons" / "app_icon.ico")
    ico.size = max(ico.info["sizes"])
    img = ico.convert("RGBA")
    return img.crop(img.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox())


def fitted(img, box):
    """[img] scaled to fit a [box] x [box] square, keeping its shape."""
    s = box / max(img.size)
    return img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))),
                      Image.Resampling.LANCZOS)


def centred(canvas, img):
    canvas.alpha_composite(img, ((canvas.width - img.width) // 2,
                                 (canvas.height - img.height) // 2))
    return canvas


def main():
    root = Path(__file__).resolve().parents[1]
    full_res = root / "android" / "app" / "src" / "full" / "res"
    source = orb()
    for name, scale in DENSITIES.items():
        out_dir = full_res / f"mipmap-{name}"
        out_dir.mkdir(parents=True, exist_ok=True)

        layer = round(108 * scale)
        fg = Image.new("RGBA", (layer, layer), (0, 0, 0, 0))
        centred(fg, fitted(source, round(ADAPTIVE_ORB_DP * scale)))
        fg.save(out_dir / "ic_launcher_foreground.png", optimize=True)

        size = round(80 * scale)
        legacy = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        centred(legacy, fitted(source, round(size * LEGACY_ORB)))
        legacy.convert("RGB").save(out_dir / "ic_launcher.png", optimize=True)

    print("Generated full flavor icon assets.")


if __name__ == "__main__":
    main()
