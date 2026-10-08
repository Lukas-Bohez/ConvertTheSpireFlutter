#!/usr/bin/env python3
"""The Google Play feature graphic (1024x500), from the Play tour's phone
screenshots.

    python scripts/play_feature_graphic.py <phone screenshot> <phone screenshot>
        [<out.png>]

The app's logo, name and one line on its colours at the left, the two
screenshots in phones at the right. Play shows the graphic above the
listing and may crop its edges, so nothing that matters is near them.
Writes store/google-play/feature-graphic-1024x500.png by default.

Needs Pillow (pip install pillow). Uses the Windows fonts (Segoe UI).
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / 'assets' / 'icons' / 'bitplayer-source-1024.png'
OUT = ROOT / 'store' / 'google-play' / 'feature-graphic-1024x500.png'
W, H = 1024, 500
TITLE = 'BitPlayer'
LINE = 'Your music and videos,\non every screen'
COLOURS = [(11, 37, 69), (21, 96, 122), (31, 158, 122)]


def font(name, size):
    for path in (f'C:/Windows/Fonts/{name}', f'/usr/share/fonts/truetype/{name}'):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def gradient():
    img = Image.new('RGB', (W, H))
    px = img.load()
    for x in range(W):
        for y in range(H):
            t = (x / W) * 0.75 + (y / H) * 0.25
            a, b, u = ((COLOURS[0], COLOURS[1], t / 0.5) if t < 0.5
                       else (COLOURS[1], COLOURS[2], (t - 0.5) / 0.5))
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * u) for i in range(3))
    return img


def phone(shot, height):
    """[shot] in a dark rounded phone body, with a soft shadow."""
    screen_h = height - 16
    screen = Image.open(shot).convert('RGB')
    screen = screen.resize((round(screen.width * screen_h / screen.height),
                            screen_h), Image.LANCZOS)
    body = Image.new('RGBA', (screen.width + 16, height), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, body.width - 1, height - 1], radius=30, fill=(14, 17, 22, 255),
        outline=(70, 78, 92, 255), width=2)
    mask = Image.new('L', screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, screen.width - 1, screen.height - 1], radius=24, fill=255)
    body.paste(screen, (8, 8), mask)
    shadow = Image.new('RGBA', (body.width + 60, body.height + 60), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [30, 36, body.width + 30, body.height + 36], radius=30,
        fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    shadow.alpha_composite(body, (30, 30))
    return shadow


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out = Path(sys.argv[3]) if len(sys.argv) > 3 else OUT
    img = gradient().convert('RGBA')

    logo = Image.open(LOGO).convert('RGBA').resize((120, 120), Image.LANCZOS)
    img.alpha_composite(logo, (70, 92))
    draw = ImageDraw.Draw(img)
    draw.text((66, 222), TITLE, font=font('segoeuib.ttf', 72), fill='white')
    draw.multiline_text((70, 318), LINE, font=font('segoeui.ttf', 32),
                        fill=(255, 255, 255, 225), spacing=8)

    back = phone(sys.argv[2], 400).rotate(6, resample=Image.BICUBIC,
                                          expand=True)
    front = phone(sys.argv[1], 430).rotate(-4, resample=Image.BICUBIC,
                                           expand=True)
    img.alpha_composite(back, (W - back.width - 20, 18))
    img.alpha_composite(front, (W - back.width - front.width + 150, 6))
    out.parent.mkdir(parents=True, exist_ok=True)
    img.convert('RGB').save(out, optimize=True)
    print(f'{out}: {W}x{H}')


if __name__ == '__main__':
    main()
