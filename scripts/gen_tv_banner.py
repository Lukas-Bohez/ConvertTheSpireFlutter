import sys
import subprocess
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except Exception:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"]) 
    from PIL import Image, ImageDraw, ImageFont

out_dir = Path("android/app/src/main/res/drawable")
out_dir.mkdir(parents=True, exist_ok=True)
out_path = out_dir / "tv_banner.png"

img = Image.new('RGB', (320, 180), color=(15, 15, 25))
d = ImageDraw.Draw(img)
d.rectangle([(0,0),(320,4)], fill=(80,160,255))
try:
    # Try to use a default truetype font if available
    f = ImageFont.load_default()
except Exception:
    f = None
d.text((12, 75), 'BitPlayer', fill=(220,220,220), font=f)
d.text((12, 95), 'Torrent & Media', fill=(80,160,255), font=f)
img.save(out_path)
print("created", out_path)
