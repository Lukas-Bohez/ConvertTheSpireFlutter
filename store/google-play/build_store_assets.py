"""Builds every store / launcher graphic from the REAL logo and REAL screenshots.

Single source of truth:
  - assets/icons/bitplayer-source-1024.png        the proper app logo
  - screenshots/*.webp                            real app screenshots

Run from the repo root:   python store/google-play/build_store_assets.py
Needs Pillow (pip install pillow). Uses Windows fonts (Bahnschrift / Segoe UI)
and falls back to other fonts elsewhere.

What it writes
  store/google-play/
    app-icon-512.png                  Play Console "App icon" (512x512, opaque)
    tv-banner-1280x720.png            Play Console "TV banner"
    tv-promo-banner-1920x1080.png     promo image (also used on GitHub releases)
    tv-screenshot-1-1920x1080.png     Play Console TV screenshots
    tv-screenshot-2-1920x1080.png
  docs/screenshots/banner.png         same promo image, shown on GitHub releases
  android/app/src/main/play_tv_assets/  copies of the three TV images above
  android/app/src/play/res/             launcher icons (adaptive fg + legacy),
                                        icon background colour, and the in-app
                                        Android TV banner (android:banner)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "store/google-play"
PLAY_RES = ROOT / "android/app/src/play/res"
MAIN_RES = ROOT / "android/app/src/main/res"
TV_ASSETS = ROOT / "android/app/src/main/play_tv_assets"

LOGO = ROOT / "assets/icons/bitplayer-source-1024.png"
SHOT_DIR = ROOT / "screenshots"

# --------------------------------------------------------------------------
# Copy shown on the graphics. Edit here, then re-run.
# --------------------------------------------------------------------------
TITLE = "BitPlayer"
SUBTITLE = "Torrent & Media Player"
TAGLINE = "Stream. Download. Enjoy."
BULLETS = [
    "Download torrents",
    "Powerful media player",
    "Cast to the big screen",
    "Secure & private",
]
BADGE = "Designed for Android TV"

# Launcher icon background (opaque, so the icon never has see-through parts).
ICON_BG = (244, 249, 255)  # #F4F9FF
ICON_BG_HEX = "#F4F9FF"

BOLD = ["bahnschrift.ttf", "segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"]
REG = ["segoeui.ttf", "SegUIVar.ttf", "arial.ttf", "DejaVuSans.ttf"]


def font(names, size):
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default()


# --------------------------------------------------------------------------
# Logo helpers
# --------------------------------------------------------------------------
_LOGO_CACHE = {}


def logo_content():
    """The logo cropped to its visible content (drops the transparent margin)."""
    if "c" not in _LOGO_CACHE:
        im = Image.open(LOGO).convert("RGBA")
        bbox = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
        _LOGO_CACHE["c"] = im.crop(bbox)
    return _LOGO_CACHE["c"]


def logo_fit(box):
    """Logo scaled so its content fits inside a box x box square."""
    c = logo_content()
    s = box / max(c.size)
    return c.resize((max(1, round(c.width * s)), max(1, round(c.height * s))),
                    Image.LANCZOS)


def paste_center(canvas, layer, cx, cy):
    canvas.alpha_composite(layer, (round(cx - layer.width / 2),
                                   round(cy - layer.height / 2)))


# --------------------------------------------------------------------------
# Generic drawing helpers
# --------------------------------------------------------------------------
def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    c0, c1 = (12, 20, 34), (14, 62, 52)  # dark navy -> deep teal
    for x in range(w):
        for y in range(h):
            t = min(1.0, (x / w) * 0.85 + (y / h) * 0.35)
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return img.convert("RGBA")


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1),
                                        radius, fill=255)
    return m


def shot_image(name):
    return Image.open(SHOT_DIR / name).convert("RGB")


def draw_tv(bg, shot, x, y, width):
    """Draws a TV/monitor frame with `shot` scaled to `width` at (x, y)."""
    sh = round(shot.height * width / shot.width)
    shot = shot.resize((width, sh), Image.LANCZOS)
    pad = 16
    tv_w, tv_h = width + pad * 2, sh + pad * 2
    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, y + 30, x + tv_w, y + tv_h + 30), 26, fill=(0, 0, 0, 170))
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    frame = Image.new("RGBA", (tv_w, tv_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        (0, 0, tv_w - 1, tv_h - 1), 26, fill=(8, 10, 14, 255),
        outline=(60, 70, 80, 255), width=3)
    bg.alpha_composite(frame, (x, y))
    bg.paste(shot, (x + pad, y + pad), rounded_mask(shot.size, 14))
    d = ImageDraw.Draw(bg)
    d.rounded_rectangle((x + tv_w // 2 - 130, y + tv_h + 6,
                         x + tv_w // 2 + 130, y + tv_h + 22), 8, fill=(40, 48, 56))
    return tv_h


# --------------------------------------------------------------------------
# Store graphics
# --------------------------------------------------------------------------
def promo_banner():
    W, H = 1920, 1080
    bg = gradient(W, H)
    d = ImageDraw.Draw(bg)
    bg.alpha_composite(logo_fit(215), (100, 95))
    d.text((360, 105), TITLE, font=font(BOLD, 100), fill="white")
    d.text((364, 232), SUBTITLE, font=font(REG, 40), fill=(150, 225, 205))
    d.text((100, 400), TAGLINE, font=font(BOLD, 56), fill="white")
    bf = font(REG, 44)
    y = 530
    for text in BULLETS:
        d.ellipse((104, y + 12, 128, y + 36), fill=(72, 214, 160))
        d.text((150, y), text, font=bf, fill=(232, 240, 240))
        y += 84
    badge_font = font(BOLD, 38)
    tw = d.textlength(BADGE, font=badge_font)
    bw, bh = int(tw) + 70, 84
    badge = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    ImageDraw.Draw(badge).rounded_rectangle(
        (0, 0, bw - 1, bh - 1), 18, fill=(255, 255, 255, 22),
        outline=(120, 230, 190, 200), width=3)
    bg.alpha_composite(badge, (100, 900))
    d.text((135, 922), BADGE, font=badge_font, fill="white")

    shot = shot_image("media-player-audio-controls.webp")
    tv_h = round(shot.height * 930 / shot.width) + 32
    draw_tv(bg, shot, 900, (H - tv_h) // 2 - 20, 930)
    return bg.convert("RGB")


def screenshot_slide(shot_name, caption):
    """1920x1080 Play TV screenshot: caption + logo over a real screenshot."""
    W, H = 1920, 1080
    bg = gradient(W, H)
    d = ImageDraw.Draw(bg)
    bg.alpha_composite(logo_fit(96), (90, 40))
    d.text((210, 46), TITLE, font=font(BOLD, 56), fill="white")
    cap_font = font(REG, 44)
    tw = d.textlength(caption, font=cap_font)
    d.text((W - 90 - tw, 62), caption, font=cap_font, fill=(150, 225, 205))
    shot = shot_image(shot_name)
    width = 1560
    tv_h = round(shot.height * width / shot.width) + 32
    draw_tv(bg, shot, (W - width - 32) // 2, 170 + (H - 170 - tv_h) // 2 - 40, width)
    return bg.convert("RGB")


def tv_banner(w, h):
    """Android TV banner: logo + app name on the brand gradient."""
    bg = gradient(w, h)
    d = ImageDraw.Draw(bg)
    s = h / 360.0
    logo = logo_fit(round(230 * s))
    x0 = round(34 * s)
    paste_center(bg, logo, x0 + logo.width / 2, h / 2)
    tx = x0 + logo.width + round(26 * s)
    d.text((tx, round(96 * s)), TITLE, font=font(BOLD, round(74 * s)), fill="white")
    d.text((tx + round(3 * s), round(196 * s)), SUBTITLE,
           font=font(REG, round(27 * s)), fill=(150, 225, 205))
    return bg.convert("RGB")


def store_icon(size):
    """Opaque square icon (Play Console 512x512)."""
    im = Image.new("RGBA", (size, size), ICON_BG + (255,))
    paste_center(im, logo_fit(round(size * 0.74)), size / 2, size / 2)
    return im.convert("RGB")


# --------------------------------------------------------------------------
# Android launcher icons (play flavor)
# --------------------------------------------------------------------------
DENSITIES = {"ldpi": 0.75, "mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0,
             "xxhdpi": 3.0, "xxxhdpi": 4.0}


def launcher_icons():
    for name, scale in DENSITIES.items():
        d_dir = PLAY_RES / f"mipmap-{name}"
        d_dir.mkdir(parents=True, exist_ok=True)

        # Adaptive layers are 108dp. Only the centre 66dp (61%) is guaranteed to
        # be visible, so the whole logo (note included) is kept inside ~58%.
        fg_size = round(108 * scale)
        fg = Image.new("RGBA", (fg_size, fg_size), (0, 0, 0, 0))
        paste_center(fg, logo_fit(round(fg_size * 0.58)), fg_size / 2, fg_size / 2)
        fg.save(d_dir / "ic_launcher_foreground.png", optimize=True)

        # Legacy (pre-Android 8) icon: opaque rounded square, no see-through bits.
        size = round(48 * scale)
        legacy = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        tile = Image.new("RGBA", (size, size), ICON_BG + (255,))
        legacy.paste(tile, (0, 0), rounded_mask((size, size), round(size * 0.22)))
        paste_center(legacy, logo_fit(round(size * 0.72)), size / 2, size / 2)
        legacy.save(d_dir / "ic_launcher.png", optimize=True)

    any_dir = PLAY_RES / "mipmap-anydpi-v26"
    any_dir.mkdir(parents=True, exist_ok=True)
    xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    (any_dir / "ic_launcher.xml").write_text(xml, encoding="utf-8")
    (any_dir / "ic_launcher_round.xml").write_text(xml, encoding="utf-8")

    colors = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <color name="ic_launcher_background">{ICON_BG_HEX}</color>\n'
        '</resources>\n'
    )
    (PLAY_RES / "values").mkdir(parents=True, exist_ok=True)
    (PLAY_RES / "values/colors.xml").write_text(colors, encoding="utf-8")


def android_tv_banner():
    """android:banner drawable (320x180dp). 640x360 for xhdpi, 320x180 default."""
    for sub, (w, h) in {"drawable-xhdpi": (640, 360), "drawable": (320, 180)}.items():
        img = tv_banner(w, h)
        # play/ overrides main/, but the GitHub (full) flavor uses main/.
        for res in (PLAY_RES, MAIN_RES):
            out = res / sub
            out.mkdir(parents=True, exist_ok=True)
            img.save(out / "banner.png", optimize=True)


# --------------------------------------------------------------------------
def save(img, *paths):
    for p in paths:
        p.parent.mkdir(parents=True, exist_ok=True)
        img.save(p, optimize=True)
        print("wrote", p.relative_to(ROOT))


def main():
    promo = promo_banner()
    save(promo, STORE / "tv-promo-banner-1920x1080.png",
         ROOT / "docs/screenshots/banner.png")
    save(tv_banner(1280, 720), STORE / "tv-banner-1280x720.png",
         TV_ASSETS / "tv_banner_1280x720.png")
    s1 = screenshot_slide("search-and-download-songs.webp",
                          "Search & download songs")
    s2 = screenshot_slide("match-playlists-to-folders.webp",
                          "Match playlists to your folders")
    save(s1, STORE / "tv-screenshot-1-1920x1080.png",
         TV_ASSETS / "tv_screenshot_1_1920x1080.png")
    save(s2, STORE / "tv-screenshot-2-1920x1080.png",
         TV_ASSETS / "tv_screenshot_2_1920x1080.png")
    save(store_icon(512), STORE / "app-icon-512.png")
    launcher_icons()
    android_tv_banner()
    print("wrote launcher icons + TV banner under", PLAY_RES.relative_to(ROOT))


if __name__ == "__main__":
    main()
