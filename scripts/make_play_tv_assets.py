from PIL import Image, ImageDraw
from pathlib import Path

out = Path('android/app/src/main/play_tv_assets')
out.mkdir(parents=True, exist_ok=True)

icon_path = Path('aab/unnamed.png')
icon = Image.open(icon_path).convert('RGBA') if icon_path.exists() else None

banner = Image.new('RGB', (1280, 720), (18, 24, 34))
d = ImageDraw.Draw(banner)
for i in range(0, 1280, 8):
    c = 24 + int(40 * i / 1280)
    d.line([(i, 0), (i, 720)], fill=(16, c, 40), width=8)
if icon:
    icon2 = icon.resize((320, 320))
    banner.paste(icon2, (70, 200), icon2)
d.text((430, 240), 'BitPlayer', fill=(230, 245, 255))
d.text((430, 310), 'Torrent & Media for Android TV', fill=(170, 220, 255))
banner.save(out / 'tv_banner_1280x720.png')

for idx, title in enumerate(['Search, Download, and Play', 'Background Audio + TV Remote Friendly']):
    img = Image.new('RGB', (1920, 1080), (14, 20, 28))
    draw = ImageDraw.Draw(img)
    for y in range(1080):
        t = int(30 + 60 * (y / 1080))
        draw.line([(0, y), (1920, y)], fill=(10, t, 45))
    if icon:
        icon3 = icon.resize((380, 380))
        img.paste(icon3, (130, 350), icon3)
    draw.text((620, 390), 'BitPlayer', fill=(240, 250, 255))
    draw.text((620, 470), title, fill=(170, 220, 255))
    draw.text((620, 540), 'Optimized for TV playback and torrent media workflows', fill=(160, 200, 230))
    img.save(out / f'tv_screenshot_{idx+1}_1920x1080.png')

print('Created assets in', out)
for p in out.iterdir():
    print('-', p.name)
