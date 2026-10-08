#!/usr/bin/env python3
"""The demo library the store tour plays: generated, so no one holds the
rights to any of it.

    python scripts/make_demo_media.py <folder> [--ffmpeg <ffmpeg.exe>]

Eight songs by made-up artists (soft chords, a gradient for cover art) and
four videos from FFmpeg's own generators (two Mandelbrot zooms, Conway's
Game of Life, an aurora of gradients), with subtitles for one of them.
About 250 MB. See docs/publishing/store-trailer.md.
"""
import argparse
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SONGS = [
    # file/title, artist, album, cover colours, seconds, chord (Hz)
    ('Neon Rain', 'Night Signals', 'Afterglow', '0xff6a00', '0xee0979', 201, (220, 277.18, 329.63)),
    ('Midnight Drive', 'Night Signals', 'Afterglow', '0x7f00ff', '0xe100ff', 167, (196, 246.94, 293.66)),
    ('Paper Planes', 'Juniper Avenue', 'Weekend Sky', '0x00c6ff', '0x0072ff', 235, (261.63, 329.63, 392)),
    ('Slow Sunrise', 'Juniper Avenue', 'Weekend Sky', '0xf7971e', '0xffd200', 218, (174.61, 220, 261.63)),
    ('Northern Coast', 'Lumen Harbor', 'Tides', '0x11998e', '0x38ef7d', 252, (146.83, 185, 220)),
    ('City Lights', 'Lumen Harbor', 'Tides', '0xfc466b', '0x3f5efb', 184, (233.08, 293.66, 349.23)),
    ('Glass Garden', 'Mira Vale', 'Bloom', '0xa8ff78', '0x78ffd6', 196, (293.66, 369.99, 440)),
    ('Echo Valley', 'Mira Vale', 'Bloom', '0x3a1c71', '0xffaf7b', 241, (164.81, 207.65, 246.94)),
]

VIDEOS = [
    ('Fractal Dreams', 'mandelbrot=s=1280x720:rate=30:maxiter=2000,format=yuv420p'),
    ('Ocean Glow', 'mandelbrot=s=1280x720:rate=30:end_pts=900:'
                   'outer=normalized_iteration_count,hue=h=200:s=1.3,format=yuv420p'),
    ('City of Cells', 'life=s=1280x720:mold=10:r=30:ratio=0.1:'
                      'death_color=#C83232:life_color=#00ff99'),
    ('Aurora Drift', 'gradients=s=640x360:c0=0x0b0f2b:c1=0x1fd1a5:c2=0x6a3cff:'
                     'c3=0x0b0f2b:c4=0x00b3ff:n=5:speed=0.006:r=30,gblur=sigma=30,'
                     'scale=1280:720,format=yuv420p'),
]

SUBTITLES = """1
00:00:01,000 --> 00:00:04,500
Subtitles load by themselves
when an .srt file sits next to the video.

2
00:00:05,000 --> 00:00:09,000
Turn them on or off with one tap,
or pick another file.

3
00:00:09,500 --> 00:00:14,000
They work for songs too.

4
00:00:14,500 --> 00:00:30,000
Deeper and deeper into the Mandelbrot set.
"""


def run(ffmpeg, args):
    subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', *args],
                   check=True)


def song(ffmpeg, folder, spec):
    title, artist, album, c0, c1, seconds, (a, b, c) = spec
    cover = folder / f'cover_{title}.png'
    run(ffmpeg, ['-f', 'lavfi', '-i',
                 f'gradients=s=600x600:c0={c0}:c1={c1}:x0=0:y0=0:x1=600:y1=600'
                 ':d=1:speed=0', '-frames:v', '1', str(cover)])
    tone = (f'aevalsrc=0.15*sin(2*PI*{a}*t)*(0.6+0.4*sin(2*PI*0.25*t))'
            f'+0.1*sin(2*PI*{b}*t)+0.08*sin(2*PI*{c}*t):s=44100:d={seconds}')
    run(ffmpeg, ['-f', 'lavfi', '-i', tone, '-i', str(cover),
                 '-map', '0:a', '-map', '1:v', '-c:a', 'libmp3lame', '-b:a', '96k',
                 '-c:v', 'mjpeg', '-disposition:v', 'attached_pic',
                 '-id3v2_version', '3', '-metadata', f'title={title}',
                 '-metadata', f'artist={artist}', '-metadata', f'album={album}',
                 '-metadata', 'genre=Electronic', str(folder / f'{title}.mp3')])
    cover.unlink()


def video(ffmpeg, folder, spec):
    title, source = spec
    run(ffmpeg, ['-f', 'lavfi', '-i', source, '-f', 'lavfi', '-i',
                 'aevalsrc=0.08*sin(2*PI*196*t)+0.06*sin(2*PI*246.94*t):s=44100',
                 '-t', '75', '-map', '0:v', '-map', '1:a',
                 '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '26',
                 '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '96k',
                 '-metadata', f'title={title}', '-metadata', 'artist=Studio Prism',
                 str(folder / f'{title}.mp4')])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('folder')
    parser.add_argument('--ffmpeg', default='ffmpeg')
    args = parser.parse_args()
    folder = Path(args.folder)
    folder.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        jobs = [pool.submit(song, args.ffmpeg, folder, s) for s in SONGS]
        jobs += [pool.submit(video, args.ffmpeg, folder, v) for v in VIDEOS]
        for job in jobs:
            job.result()
    (folder / 'Fractal Dreams.srt').write_text(SUBTITLES, encoding='utf-8')
    print(f'{len(SONGS)} songs and {len(VIDEOS)} videos in {folder}')


if __name__ == '__main__':
    main()
