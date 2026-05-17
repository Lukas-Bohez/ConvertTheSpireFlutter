from pathlib import Path

from PIL import Image


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    src = root / "assets" / "icons" / "app_icon.ico"
    img = Image.open(src).convert("RGBA")
    alpha_bbox = img.getchannel("A").getbbox()
    if alpha_bbox is not None:
        img = img.crop(alpha_bbox)

    legacy_sizes = {
        "mipmap-ldpi": 36,
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    foreground_sizes = {
        "mipmap-mdpi": 108,
        "mipmap-hdpi": 162,
        "mipmap-xhdpi": 216,
        "mipmap-xxhdpi": 324,
        "mipmap-xxxhdpi": 432,
    }

    full_res = root / "android" / "app" / "src" / "full" / "res"

    for bucket, size in legacy_sizes.items():
        out_dir = full_res / bucket
        out_dir.mkdir(parents=True, exist_ok=True)
        canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        icon_size = int(size * 0.78)
        icon = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        x = (size - icon_size) // 2
        y = (size - icon_size) // 2
        canvas.alpha_composite(icon, (x, y))
        canvas.save(out_dir / "ic_launcher.png")

    for bucket, size in foreground_sizes.items():
        out_dir = full_res / bucket
        out_dir.mkdir(parents=True, exist_ok=True)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        icon_size = int(size * 0.94)
        icon = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        x = (size - icon_size) // 2
        y = (size - icon_size) // 2
        canvas.alpha_composite(icon, (x, y))
        canvas.save(out_dir / "ic_launcher_foreground.png")

    print("Generated full flavor icon assets.")


if __name__ == "__main__":
    main()
