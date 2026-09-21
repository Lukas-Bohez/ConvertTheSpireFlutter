"""Builds the Android TV promo banner (1920x1080) from REAL assets.

Inputs (all in the repo):
  - assets/icons/bitplayer-source-1024.png   the proper app logo
  - screenshots/media-player-audio-controls.webp  a real app screenshot

Outputs:
  - store/google-play/tv-promo-banner-1920x1080.png   (upload to Play Console)
  - docs/screenshots/banner.png                      (shown at the top of GitHub releases)

Run from the repo root:   python store/google-play/build_tv_banner.py
Needs Pillow (pip install pillow) and a Windows font (Segoe UI / Bahnschrift);
falls back to Pillow's default font elsewhere.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
W, H = 1920, 1080

LOGO = ROOT / "assets/icons/bitplayer-source-1024.png"
SHOT = ROOT / "screenshots/media-player-audio-controls.webp"
OUT_STORE = ROOT / "store/google-play/tv-promo-banner-1920x1080.png"
OUT_GITHUB = ROOT / "docs/screenshots/banner.png"

# Copy shown on the banner. Edit here, then re-run.
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


def font(names, size):
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except OSError:
            continue
    return ImageFont.load_default()


BOLD = ["bahnschrift.ttf", "segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"]
REG = ["segoeui.ttf", "SegUIVar.ttf", "arial.ttf", "DejaVuSans.ttf"]


def gradient():
    img = Image.new("RGB", (W, H))
    px = img.load()
    c0, c1 = (12, 20, 34), (14, 62, 52)  # dark navy -> deep teal
    for x in range(W):
        for y in range(H):
            t = min(1.0, (x / W) * 0.85 + (y / H) * 0.35)
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return img


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size[0], size[1]), radius, fill=255)
    return m


def main():
    bg = gradient().convert("RGBA")
    d = ImageDraw.Draw(bg)

    # --- left column ------------------------------------------------------
    logo = Image.open(LOGO).convert("RGBA").resize((230, 230), Image.LANCZOS)
    bg.alpha_composite(logo, (100, 90))
    d.text((360, 105), TITLE, font=font(BOLD, 100), fill="white")
    d.text((364, 232), SUBTITLE, font=font(REG, 40), fill=(150, 225, 205))

    d.text((100, 400), TAGLINE, font=font(BOLD, 56), fill="white")

    bf = font(REG, 44)
    y = 530
    for text in BULLETS:
        d.ellipse((104, y + 12, 128, y + 36), fill=(72, 214, 160))
        d.text((150, y), text, font=bf, fill=(232, 240, 240))
        y += 84

    # Android TV badge
    badge_font = font(BOLD, 38)
    tw = d.textlength(BADGE, font=badge_font)
    bw, bh = int(tw) + 70, 84
    badge = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    ImageDraw.Draw(badge).rounded_rectangle(
        (0, 0, bw - 1, bh - 1), 18, fill=(255, 255, 255, 22),
        outline=(120, 230, 190, 200), width=3)
    bg.alpha_composite(badge, (100, 900))
    d.text((135, 922), BADGE, font=badge_font, fill="white")

    # --- right: TV with the real screenshot -------------------------------
    shot = Image.open(SHOT).convert("RGB")
    sw = 930
    sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    pad = 16
    tv_w, tv_h = sw + pad * 2, sh + pad * 2
    tv_x, tv_y = 900, (H - tv_h) // 2 - 20

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (tv_x, tv_y + 30, tv_x + tv_w, tv_y + tv_h + 30), 26, fill=(0, 0, 0, 170))
    bg.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))

    frame = Image.new("RGBA", (tv_w, tv_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        (0, 0, tv_w - 1, tv_h - 1), 26, fill=(8, 10, 14, 255),
        outline=(60, 70, 80, 255), width=3)
    bg.alpha_composite(frame, (tv_x, tv_y))
    bg.paste(shot, (tv_x + pad, tv_y + pad), rounded_mask(shot.size, 14))

    # TV stand
    d.rounded_rectangle((tv_x + tv_w // 2 - 130, tv_y + tv_h + 6,
                         tv_x + tv_w // 2 + 130, tv_y + tv_h + 22), 8,
                        fill=(40, 48, 56))

    final = bg.convert("RGB")
    OUT_STORE.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT_STORE, optimize=True)
    OUT_GITHUB.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT_GITHUB, optimize=True)
    print("wrote", OUT_STORE)
    print("wrote", OUT_GITHUB)


if __name__ == "__main__":
    main()
