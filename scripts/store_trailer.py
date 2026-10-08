#!/usr/bin/env python3
"""The store trailer, from a recording of the store tour.

    python scripts/store_trailer.py <tour folder> <trailer.mp4>
        [--ffmpeg <ffmpeg.exe>] [--until <segment id>] [--stop-at <s>]

<tour folder> is what integration_test/store_tour_test.dart wrote with
TOUR_RECORD=true: tour.mp4 and marks.json, where each feature starts. The
trailer is a title card, each feature with its caption, and a closing card,
cross-faded: 1920x1080, 30 fps, H.264, with a silent sound track, as the
Microsoft Store and YouTube take it. A 1920x1080 thumbnail is written next
to it (<trailer>.png). --until stops before that segment, and --stop-at at
that second of the recording: to leave out the end of a recording that
something (a notification) spoiled.

Only the Python standard library and FFmpeg are needed. See
docs/publishing/store-trailer.md.
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / 'assets' / 'icons' / 'app_icon_fixed.png'
FONT_BOLD = 'C\\:/Windows/Fonts/segoeuib.ttf'
FONT = 'C\\:/Windows/Fonts/segoeui.ttf'
FADE = 0.4

CAPTIONS = {
    'home': 'Download from 1,800+ sites as MP3, M4A or MP4',
    'player': 'One player for your music and videos',
    'video': 'Subtitles load by themselves',
    'large': 'Watch big, without the clutter',
    'loop': 'Loop just the best part',
    'speed': 'Change the speed, set a sleep timer',
    'torrents': 'A torrent client built in',
    'browser': 'A browser with a real ad blocker',
    'colours': 'Make it yours: 28 colours, light and dark',
}
# Features whose bottom has what the video is about (the loop editor, a
# video's subtitles): their caption goes at the top.
CAPTION_AT_TOP = {'large', 'loop'}
TITLE = 'Convert the Spire Reborn'
TAGLINE = 'Music, videos, downloads and torrents in one free app'
CLOSING = ['Free. No ads. No account.', 'Windows and Android',
           'Microsoft Store  ·  GitHub  ·  quizthespire.com']
BACKGROUND = ('gradients=s=1920x1080:c0=0x0b2545:c1=0x15607a:c2=0x1f9e7a:'
              'n=3:x0=0:y0=0:x1=1920:y1=1080:speed=0.004:r=30')


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


def card(ffmpeg, tmp, out, seconds, lines, icon_size, icon_y):
    """A card on the app's colours: its icon and [lines] of text."""
    draws = []
    for i, (text, size, y, font, alpha) in enumerate(lines):
        f = text_file(tmp, f'{Path(out).stem}_{i}', text)
        draws.append(f"drawtext=fontfile='{font}':textfile='{f}':fontsize={size}"
                     f":fontcolor=white@{alpha}:x=(w-text_w)/2:y={y}")
    # The icon's file is a white square: rounded into an app tile.
    r = round(icon_size * 0.22)
    corner = ' + '.join(
        f'{cx}*{cy}*gt(hypot({dx},{dy}),{r})' for cx, cy, dx, dy in [
            (f'lt(X,{r})', f'lt(Y,{r})', f'{r}-X', f'{r}-Y'),
            (f'gt(X,W-{r})', f'lt(Y,{r})', f'X-W+{r}', f'{r}-Y'),
            (f'lt(X,{r})', f'gt(Y,H-{r})', f'{r}-X', f'Y-H+{r}'),
            (f'gt(X,W-{r})', f'gt(Y,H-{r})', f'X-W+{r}', f'Y-H+{r}'),
        ])
    graph = (f'[1:v]scale={icon_size}:{icon_size},format=rgba,'
             f"geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*(1-({corner}))'[icon];"
             f'[0:v][icon]overlay=(W-w)/2:{icon_y},' + ','.join(draws))
    run(ffmpeg, ['-f', 'lavfi', '-t', str(seconds), '-i', BACKGROUND,
                 '-i', str(ICON), '-filter_complex', graph,
                 '-t', str(seconds), *encode_args(out)])


def clip(ffmpeg, tmp, tour, out, start, end, caption, name, top=False):
    """[start, end] of the recording, with [caption] in a band at the
    bottom (or [top]) that fades in."""
    f = text_file(tmp, name, caption)
    alpha = "if(lt(t,0.25),0,if(lt(t,0.6),(t-0.25)/0.35,1))"
    y = '110' if top else 'h-text_h-110'
    draw = (f"drawtext=fontfile='{FONT_BOLD}':textfile='{f}':fontsize=56"
            f":fontcolor=white:alpha='{alpha}':box=1:boxcolor=0x0b2545@0.82"
            f":boxborderw=28:x=(w-text_w)/2:y={y}")
    run(ffmpeg, ['-ss', f'{start:.3f}', '-to', f'{end:.3f}', '-i', str(tour),
                 '-vf', f'scale=1920:1080,{draw}', '-an', *encode_args(out)])


def duration(ffmpeg, path):
    probe = Path(ffmpeg).with_name('ffprobe.exe')
    if not probe.exists():
        probe = Path(ffmpeg).with_name('ffprobe')
    out = subprocess.run([str(probe), '-v', 'error', '-show_entries',
                          'format=duration', '-of', 'csv=p=0', str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tour')
    parser.add_argument('out')
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--until')
    parser.add_argument('--stop-at', type=float)
    args = parser.parse_args()

    tour_dir = Path(args.tour)
    marks = json.loads((tour_dir / 'marks.json').read_text(encoding='utf-8'))
    segments = []
    for here, after in zip(marks, marks[1:]):
        if here['id'] == args.until:
            break
        end = after['t'] + FADE
        if args.stop_at is not None:
            if here['t'] >= args.stop_at - 1:
                break
            end = min(end, args.stop_at)
        if here['id'] in CAPTIONS:
            segments.append((here['id'], here['t'], end))

    with tempfile.TemporaryDirectory() as tmp:
        parts = []
        intro = Path(tmp) / 'intro.mp4'
        card(args.ffmpeg, tmp, intro, 3.0, [
            (TITLE, 92, 640, FONT_BOLD, 1),
            (TAGLINE, 42, 770, FONT, 0.88),
        ], 340, 230)
        parts.append(intro)
        for i, (sid, start, end) in enumerate(segments):
            out = Path(tmp) / f'{i:02d}_{sid}.mp4'
            # A moment past the cut: the page is still settling then.
            clip(args.ffmpeg, tmp, tour_dir / 'tour.mp4', out, start + 0.15,
                 end, CAPTIONS[sid], sid, top=sid in CAPTION_AT_TOP)
            parts.append(out)
        outro = Path(tmp) / 'outro.mp4'
        card(args.ffmpeg, tmp, outro, 3.5, [
            (CLOSING[0], 76, 560, FONT_BOLD, 1),
            (CLOSING[1], 44, 680, FONT, 0.9),
            (CLOSING[2], 38, 760, FONT, 0.8),
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
    print(f'{args.out}: {total:.1f} s, {len(segments)} features; {thumb}')


if __name__ == '__main__':
    main()
