#!/usr/bin/env python3
"""The Google Play trailer, from the Play tour's recordings.

    python scripts/play_trailer.py <trailer.mp4> --phone <tour folder>
        [--tablet <tour folder>] [--tv <tour folder>] [--ffmpeg <ffmpeg.exe>]

Each tour folder is what scripts/play_tour.py wrote with --record: tour.mp4
and marks.json, where each feature starts. The trailer is a title card,
the features (a phone's in a phone frame with its caption beside it, a
tablet's and a TV's across the whole picture with the caption in a band),
and a closing card, cross-faded: 1920x1080, 30 fps, H.264, with a silent
sound track, as YouTube takes it (Play shows a YouTube video). A 1920x1080
thumbnail is written next to it (<trailer>.png).

Needs FFmpeg and Pillow (pip install pillow). See
docs/publishing/store-trailer.md.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / 'assets' / 'icons' / 'bitplayer-source-1024.png'
FONT_BOLD = 'C\\:/Windows/Fonts/segoeuib.ttf'
FONT = 'C\\:/Windows/Fonts/segoeui.ttf'
FADE = 0.4
# Longest a feature stays on screen.
MAX_SECONDS = 6.0

# (recording, feature, caption, small line under it)
PLAN = [
    ('phone', 'player', 'One player for your\nmusic and videos', 'Phones'),
    ('phone', 'video', 'Subtitles load\nby themselves', 'For songs too'),
    ('phone', 'loop', 'Loop just\nthe best part', 'One part or several'),
    ('tablet', 'large', 'Watch big, without the clutter', 'Tablets and Chromebooks'),
    ('tablet', 'torrents', 'A torrent client built in', None),
    ('tv', 'player', 'On your TV, with the remote', 'Android TV'),
    ('tv', 'video', 'Subtitles on the big screen', 'Android TV'),
    ('tablet', 'colours', 'Make it yours: 28 colours, light and dark', None),
]
TITLE = 'BitPlayer'
TAGLINE = 'Your music and videos, on every screen'
CLOSING = ['Free on Google Play', 'Phones  ·  Tablets  ·  Chromebooks  ·  Android TV']
BACKGROUND = ('gradients=s=1920x1080:c0=0x0b2545:c1=0x15607a:c2=0x1f9e7a:'
              'n=3:x0=0:y0=0:x1=1920:y1=1080:speed=0.004:r=30')
# The phone on screen: its picture's size and where it goes.
PHONE_H = 940
PHONE_W = round(PHONE_H * 9 / 16)
PHONE_X, PHONE_Y = 250, (1080 - PHONE_H) // 2
BEZEL = 16


def run(ffmpeg, args):
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', *args],
                   check=True)


def text_file(folder, name, text):
    path = Path(folder) / f'{name}.txt'
    path.write_text(text, encoding='utf-8')
    # drawtext's own escaping for a path: a colon needs a backslash.
    return str(path).replace('\\', '/').replace(':', '\\:')


def encode_args(out):
    return ['-c:v', 'libx264', '-preset', 'slow', '-crf', '18',
            '-pix_fmt', 'yuv420p', '-r', '30', str(out)]


def duration(ffmpeg, path):
    probe = Path(ffmpeg).with_name('ffprobe.exe')
    if not probe.exists():
        probe = Path(ffmpeg).with_name('ffprobe')
    out = subprocess.run([str(probe), '-v', 'error', '-show_entries',
                          'format=duration', '-of', 'csv=p=0', str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def phone_masks(tmp):
    """The screen's rounded corners (an alpha mask) and the phone around
    it (a dark rounded body with a soft shadow)."""
    mask = Image.new('L', (PHONE_W, PHONE_H), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, PHONE_W - 1, PHONE_H - 1], radius=44, fill=255)
    mask_path = Path(tmp) / 'screen_mask.png'
    mask.save(mask_path)
    body = Image.new('RGBA', (PHONE_W + 2 * BEZEL, PHONE_H + 2 * BEZEL),
                     (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, body.width - 1, body.height - 1], radius=44 + BEZEL,
        fill=(14, 17, 22, 255), outline=(70, 78, 92, 255), width=3)
    body_path = Path(tmp) / 'phone_body.png'
    body.save(body_path)
    return mask_path, body_path


def card(ffmpeg, tmp, out, seconds, lines, icon_size, icon_y):
    """A card on the app's colours: its icon and [lines] of text."""
    draws = []
    for i, (text, size, y, font, alpha) in enumerate(lines):
        f = text_file(tmp, f'{Path(out).stem}_{i}', text)
        draws.append(f"drawtext=fontfile='{font}':textfile='{f}':fontsize={size}"
                     f":fontcolor=white@{alpha}:x=(w-text_w)/2:y={y}")
    tile = Image.new('RGBA', (icon_size, icon_size), (0, 0, 0, 0))
    mask = Image.new('L', (icon_size, icon_size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, icon_size - 1, icon_size - 1], radius=round(icon_size * 0.22),
        fill=255)
    white = Image.new('RGBA', (icon_size, icon_size), (255, 255, 255, 255))
    logo = Image.open(ICON).convert('RGBA').resize((icon_size, icon_size))
    white.alpha_composite(logo)
    tile.paste(white, (0, 0), mask)
    tile_path = Path(tmp) / f'{Path(out).stem}_icon.png'
    tile.save(tile_path)
    graph = (f'[0:v][1:v]overlay=(W-w)/2:{icon_y},' + ','.join(draws))
    run(ffmpeg, ['-f', 'lavfi', '-t', str(seconds), '-i', BACKGROUND,
                 '-i', str(tile_path), '-filter_complex', graph,
                 '-t', str(seconds), *encode_args(out)])


def phone_clip(ffmpeg, tmp, tour, out, start, end, caption, sub, masks):
    """The phone recording in a phone, its caption beside it."""
    mask_path, body_path = masks
    f = text_file(tmp, Path(out).stem, caption)
    alpha = "if(lt(t,0.25),0,if(lt(t,0.6),(t-0.25)/0.35,1))"
    text_x = PHONE_X + PHONE_W + 2 * BEZEL + 150
    draws = [f"drawtext=fontfile='{FONT_BOLD}':textfile='{f}':fontsize=76"
             f":line_spacing=18:fontcolor=white:alpha='{alpha}'"
             f":x={text_x}:y=(h-text_h)/2-30"]
    if sub:
        g = text_file(tmp, Path(out).stem + '_sub', sub)
        draws.append(f"drawtext=fontfile='{FONT}':textfile='{g}':fontsize=40"
                     f":fontcolor=white@0.8:alpha='{alpha}'"
                     f":x={text_x}:y=(h/2)+150")
    seconds = end - start
    graph = (f'[1:v]scale={PHONE_W}:{PHONE_H},format=rgba[s];'
             f'[s][2:v]alphamerge[screen];'
             f'[0:v][3:v]overlay={PHONE_X - BEZEL}:{PHONE_Y - BEZEL}[b];'
             f'[b][screen]overlay={PHONE_X}:{PHONE_Y},' + ','.join(draws))
    run(ffmpeg, ['-f', 'lavfi', '-t', f'{seconds:.3f}', '-i', BACKGROUND,
                 '-ss', f'{start:.3f}', '-t', f'{seconds:.3f}', '-i', str(tour),
                 '-loop', '1', '-i', str(mask_path),
                 '-loop', '1', '-i', str(body_path),
                 '-filter_complex', graph, '-t', f'{seconds:.3f}', '-an',
                 *encode_args(out)])


def wide_clip(ffmpeg, tmp, tour, out, start, end, caption, sub):
    """A tablet or TV recording across the picture, its caption in a band."""
    f = text_file(tmp, Path(out).stem, caption)
    alpha = "if(lt(t,0.25),0,if(lt(t,0.6),(t-0.25)/0.35,1))"
    draws = [f"drawtext=fontfile='{FONT_BOLD}':textfile='{f}':fontsize=56"
             f":fontcolor=white:alpha='{alpha}':box=1:boxcolor=0x0b2545@0.82"
             f":boxborderw=28:x=(w-text_w)/2:y=h-text_h-110"]
    if sub:
        g = text_file(tmp, Path(out).stem + '_sub', sub)
        draws.append(f"drawtext=fontfile='{FONT}':textfile='{g}':fontsize=34"
                     f":fontcolor=white:alpha='{alpha}':box=1"
                     f":boxcolor=0x1f9e7a@0.9:boxborderw=14:x=60:y=60")
    run(ffmpeg, ['-ss', f'{start:.3f}', '-to', f'{end:.3f}', '-i', str(tour),
                 '-vf', 'scale=1920:1080:force_original_aspect_ratio=decrease,'
                 'pad=1920:1080:(ow-iw)/2:(oh-ih)/2,' + ','.join(draws),
                 '-an', *encode_args(out)])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('out')
    parser.add_argument('--phone', required=True)
    parser.add_argument('--tablet')
    parser.add_argument('--tv')
    parser.add_argument('--ffmpeg', default='ffmpeg')
    args = parser.parse_args()
    tours = {k: Path(v) for k, v in
             (('phone', args.phone), ('tablet', args.tablet), ('tv', args.tv))
             if v}
    marks = {k: json.loads((v / 'marks.json').read_text(encoding='utf-8'))
             for k, v in tours.items()}

    def span(kind, feature):
        ms = marks[kind]
        for here, after in zip(ms, ms[1:]):
            if here['id'] == feature:
                # A moment past the cut: the page is still settling then.
                start = here['t'] + 0.15
                return start, min(after['t'] + FADE, start + MAX_SECONDS)
        return None

    with tempfile.TemporaryDirectory() as tmp:
        parts = []
        intro = Path(tmp) / 'intro.mp4'
        card(args.ffmpeg, tmp, intro, 3.0, [
            (TITLE, 96, 640, FONT_BOLD, 1),
            (TAGLINE, 44, 770, FONT, 0.88),
        ], 340, 230)
        parts.append(intro)
        masks = phone_masks(tmp)
        for i, (kind, feature, caption, sub) in enumerate(PLAN):
            if kind not in tours:
                continue
            where = span(kind, feature)
            if where is None:
                continue
            out = Path(tmp) / f'{i:02d}_{kind}_{feature}.mp4'
            if kind == 'phone':
                phone_clip(args.ffmpeg, tmp, tours[kind] / 'tour.mp4', out,
                           *where, caption, sub, masks)
            else:
                wide_clip(args.ffmpeg, tmp, tours[kind] / 'tour.mp4', out,
                          *where, caption.replace('\n', ' '), sub)
            parts.append(out)
        outro = Path(tmp) / 'outro.mp4'
        card(args.ffmpeg, tmp, outro, 3.5, [
            (CLOSING[0], 80, 560, FONT_BOLD, 1),
            (CLOSING[1], 42, 690, FONT, 0.9),
        ], 240, 230)
        parts.append(outro)

        # Cross-fade one into the next.
        inputs, graph, offset, last = [], [], 0.0, '[0:v]'
        for p in parts:
            inputs += ['-i', str(p)]
        for i in range(1, len(parts)):
            offset += duration(args.ffmpeg, parts[i - 1]) - FADE
            label = f'[x{i}]'
            graph.append(f'{last}[{i}:v]xfade=transition=fade:duration={FADE}'
                         f':offset={offset:.3f}{label}')
            last = label
        total = offset + duration(args.ffmpeg, parts[-1])
        graph.append(f'{last}fade=t=in:st=0:d=0.5,'
                     f'fade=t=out:st={total - 0.6:.3f}:d=0.6[v]')
        run(args.ffmpeg, [*inputs, '-f', 'lavfi', '-t', f'{total:.3f}', '-i',
                          'anullsrc=r=48000:cl=stereo',
                          '-filter_complex', ';'.join(graph),
                          '-map', '[v]', '-map', f'{len(parts)}:a',
                          '-c:a', 'aac', '-b:a', '128k', '-shortest',
                          '-movflags', '+faststart', *encode_args(args.out)])
        thumb = Path(args.out).with_suffix('.png')
        run(args.ffmpeg, ['-ss', '1.6', '-i', str(intro), '-frames:v', '1',
                          str(thumb)])
    print(f'{args.out}: {total:.1f} s, {len(parts) - 2} features; {thumb}')


if __name__ == '__main__':
    main()
