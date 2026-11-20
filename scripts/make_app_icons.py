"""The app icon, drawn from its geometry: a play button riding two waves on a
blue-to-green tile.

One description of the shapes below makes both the SVG (Linux / Flathub) and
every PNG and ICO the platforms need, so they cannot drift apart. The PNGs are
drawn with Pillow at 4x and scaled down, so no SVG renderer is needed.

Run from the repo root:  python scripts/make_app_icons.py  (needs Pillow)

Writes:
  assets/icons/app-icon.svg              the icon (Linux, Flathub, source)
  assets/icons/bitplayer-source-1024.png the icon as a 1024 PNG; the store
                                         banners use it (build_store_assets.py)
  assets/icons/app_icon_fixed.png        MSIX logo (pubspec msix_config) and
                                         the Windows store tiles made from it
  assets/icons/app_logo_384.png          in-app logo, Linux package icon
  assets/icons/favicon-192x192.png       tray icon on Linux / macOS
  assets/icons/app_icon.ico              tray icon on Windows
  windows/runner/resources/app_icon.ico  the Windows .exe icon
  assets/icons/linux/<n>x<n>/...png      hicolor PNGs for the Linux packages
  assets/icons/full-bleed-1024.png       square icon, edge to edge: the Play
                                         Console icon (build_store_assets.py)
  android/app/src/{main,play,full}/res/  launcher icons (adaptive + legacy)
  web/icons/*, web/favicon.png
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "assets" / "icons"

APP_ID = "io.github.Lukas_Bohez.ConvertTheSpireFlutter"

# --------------------------------------------------------------------------
# The design, on a 512 x 512 canvas. Shapes inside the tile are given in tile
# units (0..1 across the tile), so the same picture fills a rounded tile, a
# full-bleed square or an Android adaptive layer.
# --------------------------------------------------------------------------
GRADIENT = [(0.0, "#1F5BD8"), (0.55, "#1497B8"), (1.0, "#25C48C")]
# Arrow and wave colour on the white play button: the middle of the gradient.
ACCENT = "#1677C8"

# The tile's share of the canvas. Flathub asks that an icon not fill the
# whole canvas (GNOME's grid puts a square shape at about 3/4 of it); Windows
# icons fill more of theirs.
FOOTPRINT_LINUX = 0.80
FOOTPRINT_WINDOWS = 0.90
CORNER = 0.24  # corner radius, as a share of the tile's side

# Play button: a triangle with round corners (the points are the centres of
# the corner circles).
PLAY = [(0.384, 0.278), (0.384, 0.648), (0.704, 0.463)]
PLAY_ROUND = 0.051

# Download arrow cut into the play button, pointing down.
ARROW_X = 0.488
ARROW_TOP = 0.350
ARROW_TIP = 0.565
ARROW_STEM = 0.048  # stem width
ARROW_HEAD_W = 0.165
ARROW_HEAD_H = 0.095

# Two waves along the bottom: start point, then cubic segments
# (control 1, control 2, end), in tile units; filled down to the bottom edge.
WAVES = [
    (0.14, (0.0, 0.741), [((0.208, 0.644), (0.370, 0.843), (0.602, 0.745)),
                          ((0.833, 0.648), (0.903, 0.648), (1.02, 0.708))]),
    (0.12, (0.0, 0.843), [((0.231, 0.759), (0.417, 0.940), (0.648, 0.843)),
                          ((0.880, 0.745), (0.926, 0.787), (1.02, 0.815))]),
]


def _hex(c: str) -> tuple[int, int, int]:
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _cubic(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(1, n + 1):
        t = i / n
        a = (1 - t) ** 3
        b = 3 * (1 - t) ** 2 * t
        c = 3 * (1 - t) * t ** 2
        d = t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
                    a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def _wave_polygon(start, segs):
    pts = [start]
    cur = start
    for c1, c2, end in segs:
        pts += _cubic(cur, c1, c2, end)
        cur = end
    # Run on flat past both sides and well below, for layers that bleed past
    # the tile (Android's adaptive background); the tile clips them anyway.
    return [(-0.6, start[1])] + pts + [(1.6, cur[1]), (1.6, 1.6), (-0.6, 1.6)]


def _arrow_polygon():
    s, hw, hh = ARROW_STEM / 2, ARROW_HEAD_W / 2, ARROW_HEAD_H
    x, top, tip = ARROW_X, ARROW_TOP, ARROW_TIP
    neck = tip - hh
    return [(x - s, top), (x + s, top), (x + s, neck), (x + hw, neck),
            (x, tip), (x - hw, neck), (x - s, neck)]


# --------------------------------------------------------------------------
# Raster drawing
# --------------------------------------------------------------------------
SUPER = 4


def _gradient(size: int) -> Image.Image:
    """The tile gradient, top-left to bottom-right, over a size x size box."""
    across = Image.linear_gradient("L").rotate(90).resize((size, size))
    down = Image.linear_gradient("L").resize((size, size))
    t = ImageChops.add(across, down, scale=2)
    stops = [(o, _hex(c)) for o, c in GRADIENT]
    palette = []
    for i in range(256):
        x = i / 255
        for (o0, c0), (o1, c1) in zip(stops, stops[1:]):
            if o0 <= x <= o1:
                k = (x - o0) / (o1 - o0)
                palette += [round(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)]
                break
    indexed = Image.frombytes("P", t.size, t.tobytes())
    indexed.putpalette(palette)
    return indexed.convert("RGBA")


def _rounded_play_mask(draw: ImageDraw.ImageDraw, to_px, r_px, fill=255):
    pts = [to_px(p) for p in PLAY]
    draw.polygon(pts, fill=fill)
    for i, a in enumerate(pts):
        b = pts[(i + 1) % 3]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln * r_px, dx / ln * r_px
        draw.polygon([(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
                      (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)], fill=fill)
        draw.ellipse((a[0] - r_px, a[1] - r_px, a[0] + r_px, a[1] + r_px), fill=fill)


def render(size: int, *, footprint: float | None, background=True,
           foreground=True, glyph_scale: float = 1.0,
           bleed: bool = False) -> Image.Image:
    """The icon at size x size px.

    footprint: the tile's share of the canvas, or None for a full-bleed square
    (no rounded tile: the store or the launcher applies its own shape).
    background / foreground: the tile with its waves / the play button.
    glyph_scale: the play button's size relative to the tile.
    bleed: the tile's picture runs on to the canvas edges instead of stopping
    at its rounded corners (Android's adaptive layers, of which the launcher
    shows the middle and cuts its own shape).
    """
    big = size * SUPER
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if footprint is None:
        x0, side = 0.0, float(big)
    else:
        side = big * footprint
        x0 = (big - side) / 2

    def tile_px(p):
        return (x0 + p[0] * side, x0 + p[1] * side)

    def glyph_px(p):
        cx = 0.5 + (p[0] - 0.5) * glyph_scale
        cy = 0.5 + (p[1] - 0.5) * glyph_scale
        return tile_px((cx, cy))

    if background:
        tile_mask = Image.new("L", (big, big), 0)
        md = ImageDraw.Draw(tile_mask)
        if footprint is None or bleed:
            md.rectangle((0, 0, big, big), fill=255)
        else:
            md.rounded_rectangle((x0, x0, x0 + side, x0 + side),
                                 radius=side * CORNER, fill=255)
        grad = _gradient(big)
        waves = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        for opacity, start, segs in WAVES:
            layer = Image.new("L", (big, big), 0)
            ImageDraw.Draw(layer).polygon(
                [tile_px(p) for p in _wave_polygon(start, segs)], fill=255)
            white = Image.new("RGBA", (big, big), (255, 255, 255, 0))
            white.putalpha(layer.point(lambda v, o=opacity: round(v * o)))
            waves = Image.alpha_composite(waves, white)
        tile = Image.alpha_composite(grad, waves)
        tile.putalpha(tile_mask)
        canvas = Image.alpha_composite(canvas, tile)

    if foreground:
        play = Image.new("L", (big, big), 0)
        _rounded_play_mask(ImageDraw.Draw(play), glyph_px,
                           PLAY_ROUND * side * glyph_scale)
        arrow = Image.new("L", (big, big), 0)
        # Below 32 px the arrow is a smudge; the button alone reads better.
        if size * glyph_scale * (footprint or 1) >= 28:
            ImageDraw.Draw(arrow).polygon(
                [glyph_px(p) for p in _arrow_polygon()], fill=255)
        white = Image.new("RGBA", (big, big), (255, 255, 255, 255))
        white.putalpha(play)
        canvas = Image.alpha_composite(canvas, white)
        accent = Image.new("RGBA", (big, big), _hex(ACCENT) + (255,))
        accent.putalpha(arrow)
        canvas = Image.alpha_composite(canvas, accent)

    return canvas.resize((size, size), Image.LANCZOS)


# --------------------------------------------------------------------------
# SVG (same shapes)
# --------------------------------------------------------------------------
def svg(footprint: float = FOOTPRINT_LINUX) -> str:
    side = 512 * footprint
    x0 = (512 - side) / 2

    def p(pt):
        return f"{x0 + pt[0] * side:.2f} {x0 + pt[1] * side:.2f}"

    def wave_d(start, segs):
        d = f"M{p((-0.05, start[1]))} L{p(start)}"
        for c1, c2, end in segs:
            d += f" C{p(c1)} {p(c2)} {p(end)}"
        last = segs[-1][2]
        d += f" L{p((1.05, last[1]))} L{p((1.05, 1.05))} L{p((-0.05, 1.05))} Z"
        return d

    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in GRADIENT)
    r = side * CORNER
    waves = "".join(f'<path d="{wave_d(s, segs)}" fill="#fff" fill-opacity="{o}"/>'
                    for o, s, segs in WAVES)
    play = " ".join(("M" if i == 0 else "L") + p(pt) for i, pt in enumerate(PLAY)) + " Z"
    arrow = " ".join(("M" if i == 0 else "L") + p(pt)
                     for i, pt in enumerate(_arrow_polygon())) + " Z"
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="g" x1="{x0:.2f}" y1="{x0:.2f}" x2="{x0 + side:.2f}" y2="{x0 + side:.2f}" gradientUnits="userSpaceOnUse">{stops}</linearGradient>
    <clipPath id="t"><rect x="{x0:.2f}" y="{x0:.2f}" width="{side:.2f}" height="{side:.2f}" rx="{r:.2f}"/></clipPath>
  </defs>
  <rect x="{x0:.2f}" y="{x0:.2f}" width="{side:.2f}" height="{side:.2f}" rx="{r:.2f}" fill="url(#g)"/>
  <g clip-path="url(#t)">{waves}</g>
  <path d="{play}" fill="#fff" stroke="#fff" stroke-width="{2 * PLAY_ROUND * side:.2f}" stroke-linejoin="round"/>
  <path d="{arrow}" fill="{ACCENT}"/>
</svg>
'''


# --------------------------------------------------------------------------
def _save(img: Image.Image, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


DENSITIES = {"ldpi": 0.75, "mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0,
             "xxhdpi": 3.0, "xxxhdpi": 4.0}
# Android shows the middle 72dp of the 108dp adaptive layers (and a round
# mask the middle 66dp): the tile's picture is laid out on those 72dp and
# runs on past them.
ADAPTIVE_VISIBLE = 72 / 108


def android_launcher_icons(res: Path):
    """Launcher icons for one flavor's res/ folder: the adaptive icon (the
    waves on the gradient behind, the play button in front) and the legacy
    icon, full-bleed and opaque at the Android TV size of 80dp (160 px at
    xhdpi), so it fills the whole icon space as Play's TV review wants."""
    for name, scale in DENSITIES.items():
        out = res / f"mipmap-{name}"
        layer = round(108 * scale)
        _save(render(layer, footprint=ADAPTIVE_VISIBLE, foreground=False,
                     bleed=True), out / "ic_launcher_background.png")
        _save(render(layer, footprint=ADAPTIVE_VISIBLE, background=False),
              out / "ic_launcher_foreground.png")
        _save(render(round(80 * scale), footprint=None).convert("RGB"),
              out / "ic_launcher.png")
    any_dir = res / "mipmap-anydpi-v26"
    any_dir.mkdir(parents=True, exist_ok=True)
    (any_dir / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n', encoding="utf-8", newline="\n")
    (any_dir / "ic_launcher_round.xml").unlink(missing_ok=True)
    # The old white background, as a colour or a drawable.
    (res / "drawable/ic_launcher_background.xml").unlink(missing_ok=True)
    colors = res / "values/colors.xml"
    if colors.exists():
        text = colors.read_text(encoding="utf-8")
        if text.count("<color") == 1 and 'name="ic_launcher_background"' in text:
            colors.unlink()


def main():
    (ICONS / "app-icon.svg").write_text(svg(), encoding="utf-8", newline="\n")
    print("wrote assets/icons/app-icon.svg")

    linux = render(1024, footprint=FOOTPRINT_LINUX)
    windows = render(1024, footprint=FOOTPRINT_WINDOWS)

    _save(windows, ICONS / "bitplayer-source-1024.png")
    _save(windows.resize((512, 512), Image.LANCZOS), ICONS / "app_icon_fixed.png")
    _save(linux.resize((384, 384), Image.LANCZOS), ICONS / "app_logo_384.png")
    _save(windows.resize((192, 192), Image.LANCZOS), ICONS / "favicon-192x192.png")

    # Small sizes drawn at their own size, so the edges stay crisp.
    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    ico_images = [render(s, footprint=FOOTPRINT_WINDOWS) for s in ico_sizes]
    for path in (ICONS / "app_icon.ico",
                 ROOT / "windows/runner/resources/app_icon.ico"):
        ico_images[-1].save(path, sizes=[(s, s) for s in ico_sizes],
                            append_images=ico_images[:-1])
        print("wrote", path.relative_to(ROOT))

    for s in (16, 24, 32, 48, 64, 128, 256, 512):
        _save(render(s, footprint=FOOTPRINT_LINUX),
              ICONS / "linux" / f"{s}x{s}" / f"{APP_ID}.png")

    _save(render(1024, footprint=None), ICONS / "full-bleed-1024.png")
    for flavor in ("main", "play", "full"):
        android_launcher_icons(ROOT / "android/app/src" / flavor / "res")

    web = ROOT / "web"
    full = render(512, footprint=None)
    _save(windows.resize((192, 192), Image.LANCZOS), web / "icons/Icon-192.png")
    _save(windows.resize((512, 512), Image.LANCZOS), web / "icons/Icon-512.png")
    _save(full.resize((192, 192), Image.LANCZOS), web / "icons/Icon-maskable-192.png")
    _save(full, web / "icons/Icon-maskable-512.png")
    _save(render(32, footprint=FOOTPRINT_WINDOWS), web / "favicon.png")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        out = Path(sys.argv[2])
        render(512, footprint=FOOTPRINT_LINUX).save(out / "preview-linux.png")
        render(512, footprint=None).save(out / "preview-full.png")
        sheet = Image.new("RGBA", (16 + 24 + 32 + 48 + 64 + 6 * 8, 80), (240, 240, 240, 255))
        x = 8
        for s in (16, 24, 32, 48, 64):
            sheet.alpha_composite(render(s, footprint=FOOTPRINT_WINDOWS), (x, 8))
            x += s + 8
        sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(out / "preview-small.png")
        dark = Image.new("RGBA", (512, 512), (36, 36, 36, 255))
        dark.alpha_composite(render(512, footprint=FOOTPRINT_LINUX))
        dark.save(out / "preview-dark.png")
        print("previews in", out)
    else:
        main()
