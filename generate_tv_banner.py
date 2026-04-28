from PIL import Image, ImageDraw, ImageFont
import os

# Create directories if needed
os.makedirs("android/app/src/main/res/drawable", exist_ok=True)

# Create 320x180 image with dark background
img = Image.new('RGB', (320, 180), color=(20, 20, 30))
draw = ImageDraw.Draw(img)

# Add accent bar
draw.rectangle([(0, 0), (320, 4)], fill=(100, 180, 255))

# Add text
try:
    font = ImageFont.load_default()
    draw.text((10, 80), "BitPlayer", fill=(200, 200, 200), font=font)
    draw.text((10, 100), "Android TV", fill=(100, 180, 255), font=font)
except:
    pass

# Save
img.save("android/app/src/main/res/drawable/tv_banner.png", "PNG")
print("✓ Created tv_banner.png (320x180 px)")
