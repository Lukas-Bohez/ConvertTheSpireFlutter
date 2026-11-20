"""Microsoft Store listing images, from the app icon.

Partner Center > the app > Store listing > Store logos:
  box-art-1x1-2160.png      1:1 box art (2160x2160; 1080x1080 is the minimum)
  poster-art-2x3-1440x2160.png  2:3 poster art (1440x2160; 720x1080 minimum)
  app-tile-icon-300.png     app tile icon (300x300, see-through corners)

Run from the repo root after scripts/make_app_icons.py:
    python store/microsoft-store/build_store_images.py
Uses the same fonts and dark gradient as the Play graphics.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "store/google-play"))
from build_store_assets import BOLD, REG, font, gradient  # noqa: E402

OUT = ROOT / "store/microsoft-store"
LOGO = ROOT / "assets/icons/bitplayer-source-1024.png"
TITLE = "Convert the Spire Reborn"
SUBTITLE = "Music & video player and downloader"


def logo(size):
    im = Image.open(LOGO).convert("RGBA")
    box = im.getchannel("A").getbbox()
    return im.crop(box).resize((size, size), Image.LANCZOS)


def card(w, h, logo_share, title_px, sub_px):
    """The logo above the name, centred on the brand gradient."""
    bg = gradient(w, h)
    d = ImageDraw.Draw(bg)
    side = round(min(w, h) * logo_share)
    title_font = font(BOLD, title_px)
    sub_font = font(REG, sub_px)
    title_w = d.textlength(TITLE, font=title_font)
    if title_w > w * 0.86:  # wrap the name onto two lines
        lines = ["Convert the Spire", "Reborn"]
    else:
        lines = [TITLE]
    line_h = round(title_px * 1.15)
    gap = round(title_px * 0.6)
    total = side + gap + line_h * len(lines) + round(sub_px * 1.6)
    y = (h - total) / 2
    bg.alpha_composite(logo(side), (round((w - side) / 2), round(y)))
    y += side + gap
    for line in lines:
        lw = d.textlength(line, font=title_font)
        d.text(((w - lw) / 2, y), line, font=title_font, fill="white")
        y += line_h
    sw = d.textlength(SUBTITLE, font=sub_font)
    d.text(((w - sw) / 2, y + sub_px * 0.4), SUBTITLE, font=sub_font,
           fill=(150, 225, 205))
    return bg.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    outputs = {
        "box-art-1x1-2160.png": card(2160, 2160, 0.42, 150, 76),
        "poster-art-2x3-1440x2160.png": card(1440, 2160, 0.55, 124, 62),
        "app-tile-icon-300.png": Image.open(LOGO).convert("RGBA").resize(
            (300, 300), Image.LANCZOS),
    }
    for name, img in outputs.items():
        img.save(OUT / name, optimize=True)
        print("wrote", (OUT / name).relative_to(ROOT), img.size)


if __name__ == "__main__":
    main()
