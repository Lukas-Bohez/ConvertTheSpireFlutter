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
    tv-promo-banner-1920x1080.png     promo image (Play Console only)
    tv-screenshot-1-1920x1080.png     Play Console TV screenshots
    tv-screenshot-2-1920x1080.png
  docs/screenshots/banner.png         same promo image (kept for reference;
                                      GitHub releases do not show a banner)
  android/app/src/main/play_tv_assets/  copies of the three TV images above
  android/app/src/play/res/             launcher icons (adaptive foreground, white
                                        background colour, legacy) and the in-app
                                        Android TV banner (android:banner)

The in-app TV banner and launcher icons follow Google's Android TV sizes
(developer.android.com/design/ui/tv/guides/system/tv-app-icon-guidelines):
banner 320x180 px and icon 160x160 px at xhdpi, in mipmap-<density>/. Play
review rejects the app ("no full-size app banner and/or icon") without them,
and also when the logo sits small in the icon with a wide margin around it
("Your icon does not fill the entire icon space"): it is as large as the icon
allows, on white.
"""
import math
import random
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

# How much of the icon the logo takes up: the diameter of the smallest circle
# around the whole logo (music note included), as a share of the icon's side.
# Play's TV review turned down the logo sitting small in a wide margin ("Your
# icon does not fill the entire icon space"), so it is as large as it goes
# without being cut off.
ICON_LOGO = 0.96
# Adaptive icon: 108dp layers, of which Android shows the centre 72dp; the
# logo takes 69dp of it, so a round mask does not shave the music note.
ADAPTIVE_LOGO_DP = 69
# The logo was drawn for white: its white centre and edges belong on white,
# and on Android the icon looked wrong on anything else.
ICON_BG = (255, 255, 255)
ICON_BG_HEX = "#FFFFFF"

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


def trim_white_edge(im):
    """The logo was cut out of a white background with about 3 px of that
    white left around it, a light outline on the dark icon and banner. Pulls
    the edge in by those 3 px (of 1024), which leaves the logo's own dark rim."""
    im = im.copy()
    im.putalpha(im.getchannel("A").filter(ImageFilter.MinFilter(7)))
    return im


def logo_content():
    """The logo cropped to its visible content (drops the transparent margin)."""
    if "c" not in _LOGO_CACHE:
        im = trim_white_edge(Image.open(LOGO).convert("RGBA"))
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


def _circle_through(p, q, s):
    (ax, ay), (bx, by), (cx, cy) = p, q, s
    d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    if abs(d) < 1e-9:  # in a line: the widest pair spans the circle
        a, b = max(((p, q), (p, s), (q, s)), key=lambda t: math.dist(*t))
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), math.dist(a, b) / 2
    ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay)
          + (cx * cx + cy * cy) * (ay - by)) / d
    uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx)
          + (cx * cx + cy * cy) * (bx - ax)) / d
    return (ux, uy), math.dist((ux, uy), p)


def logo_circle():
    """Centre and radius of the smallest circle around the logo's content.

    The logo is round with the music note sticking out at the top right, so
    centring its bounding box would push the note out of a round icon mask."""
    if "circle" not in _LOGO_CACHE:
        mask = logo_content().getchannel("A").point(lambda v: 255 if v > 40 else 0)
        w, h = mask.size
        px = mask.load()
        pts = []
        for y in range(h):
            xs = [x for x in range(w) if px[x, y]]
            if xs:
                pts += [(xs[0], y), (xs[-1] + 1, y), (xs[0], y + 1), (xs[-1] + 1, y + 1)]
        # Welzl's incremental algorithm; a fixed shuffle keeps it fast and the
        # output the same on every run.
        random.Random(0).shuffle(pts)
        c, r = pts[0], 0.0
        for i, p in enumerate(pts):
            if math.dist(p, c) <= r + 1e-7:
                continue
            c, r = p, 0.0
            for j in range(i):
                q = pts[j]
                if math.dist(q, c) <= r + 1e-7:
                    continue
                c, r = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2), math.dist(p, q) / 2
                for k in range(j):
                    if math.dist(pts[k], c) > r + 1e-7:
                        c, r = _circle_through(p, q, pts[k])
        _LOGO_CACHE["circle"] = (c[0], c[1], r)
    return _LOGO_CACHE["circle"]


def paste_logo_round(canvas, diameter):
    """Logo scaled and centred so all of it lies in a centred circle of
    `diameter` px."""
    c = logo_content()
    cx, cy, r = logo_circle()
    s = diameter / (2 * r)
    layer = c.resize((round(c.width * s), round(c.height * s)), Image.LANCZOS)
    canvas.alpha_composite(layer, (round(canvas.width / 2 - cx * s),
                                   round(canvas.height / 2 - cy * s)))


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


def launcher_banner(w, h):
    """In-app Android TV banner: logo + app name, centred and well inside the
    edges, since the launcher rounds and zooms the tile. No tagline: it is
    unreadable at this size, and Google's banner rules ask for the name only."""
    bg = gradient(w, h)
    d = ImageDraw.Draw(bg)
    s = h / 360.0
    logo_px, font_px, gap = 190 * s, 92 * s, 30 * s
    title_font = font(BOLD, round(font_px))
    text_w = d.textlength(TITLE, font=title_font)
    # Keep the whole group within the middle 78% of the width.
    fit = min(1.0, (w * 0.78) / (logo_px + gap + text_w))
    if fit < 1.0:
        logo_px, font_px, gap = logo_px * fit, font_px * fit, gap * fit
        title_font = font(BOLD, round(font_px))
        text_w = d.textlength(TITLE, font=title_font)
    logo = logo_fit(round(logo_px))
    x0 = (w - (logo.width + gap + text_w)) / 2
    paste_center(bg, logo, x0 + logo.width / 2, h / 2)
    # Centre the capital height on the logo, so the descender of "y" does not
    # push the name up.
    _, cap_top, _, cap_bottom = title_font.getbbox("B")
    d.text((x0 + logo.width + gap, h / 2 - (cap_top + cap_bottom) / 2), TITLE,
           font=title_font, fill="white")
    return bg.convert("RGB")


def store_icon(size):
    """Opaque square icon, the logo on white (Play Console 512x512, and the
    legacy launcher icon)."""
    im = Image.new("RGBA", (size, size), ICON_BG + (255,))
    paste_logo_round(im, size * ICON_LOGO)
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

        # Adaptive icon: 108dp layers, white behind (a colour, below) and the
        # logo in front, in the centre ADAPTIVE_LOGO_DP.
        layer = round(108 * scale)
        (d_dir / "ic_launcher_background.png").unlink(missing_ok=True)
        fg = Image.new("RGBA", (layer, layer), (0, 0, 0, 0))
        paste_logo_round(fg, layer * ADAPTIVE_LOGO_DP / 108)
        fg.save(d_dir / "ic_launcher_foreground.png", optimize=True)

        # Legacy icon, at the Android TV size of 80dp (160x160 px at xhdpi)
        # rather than the phone's 48dp: Android TV requires at least that.
        # Opaque edge to edge, so it is a full-size icon with no see-through
        # corners; launchers apply their own shape.
        store_icon(round(80 * scale)).save(d_dir / "ic_launcher.png", optimize=True)

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
    # android:roundIcon is not used (Android TV's guidelines deprecate it in
    # favour of the adaptive icon above).
    (any_dir / "ic_launcher_round.xml").unlink(missing_ok=True)
    colors = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        f'    <color name="ic_launcher_background">{ICON_BG_HEX}</color>\n'
        '</resources>\n'
    )
    (PLAY_RES / "values").mkdir(parents=True, exist_ok=True)
    (PLAY_RES / "values/colors.xml").write_text(colors, encoding="utf-8")


BANNER_SIZES = {"mdpi": (160, 90), "hdpi": (240, 135), "xhdpi": (320, 180),
                "xxhdpi": (480, 270), "xxxhdpi": (640, 360)}


def android_tv_banner():
    """android:banner = @mipmap/banner: 160x90dp, i.e. 320x180 px at xhdpi."""
    for res in (PLAY_RES, MAIN_RES):
        # play/ overrides main/, but the GitHub (full) flavor uses main/.
        for density, (w, h) in BANNER_SIZES.items():
            out = res / f"mipmap-{density}"
            out.mkdir(parents=True, exist_ok=True)
            launcher_banner(w, h).save(out / "banner.png", optimize=True)
        # The banner used to be a drawable twice this size; a stale copy
        # would be a second, conflicting banner resource.
        for sub in ("drawable", "drawable-xhdpi"):
            (res / sub / "banner.png").unlink(missing_ok=True)


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
