#!/usr/bin/env python3
"""The Google Play tour: screenshots and a recording of the Play build on an
Android phone, tablet, Chromebook-sized screen or TV (an emulator will do).

    python scripts/play_tour.py <demo media> <out folder>
        --form phone|tablet|chromebook|tv [--device <serial>] [--record]

<demo media> is what scripts/make_demo_media.py made. The tour is
integration_test/play_tour_test.dart; this script runs it, serves it the
demo media over `adb reverse`, and takes each screenshot it asks for with
adb (the app can't take its own of a video). With --record it also records
the screen: <out>/tour.mp4, and <out>/marks.json says when each feature
starts, as scripts/play_trailer.py reads them.

For the run, the screen is set to the size the Play listing takes: 1080x1920
for a phone, 2560x1440 for a tablet, 1920x1080 at desktop density for a
Chromebook (on a tablet emulator), and the clock and status bar are tidied
up. Both are put back at the end.

Only the Python standard library, adb and Flutter are needed. See
docs/publishing/store-trailer.md.
"""
import argparse
import json
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = 'com.torrentspire.ai'
PORT = 8765
# The screen the listing takes, and the density that gives the layout of
# that kind of device: None keeps what the device has.
FORMS = {
    'phone': ('1080x1920', None),
    'tablet': ('2560x1440', '320'),
    'chromebook': ('1920x1080', '160'),
    'tv': (None, None),
}
REMOTE_VIDEO = '/sdcard/play_tour.mp4'


class Device:
    def __init__(self, serial):
        self.serial = serial

    def adb(self, *args, check=True, **kw):
        cmd = ['adb'] + (['-s', self.serial] if self.serial else []) + list(args)
        return subprocess.run(cmd, check=check, capture_output=True, **kw)

    def shell(self, *args, check=True):
        return self.adb('shell', *args, check=check)

    def demo_mode(self, on):
        """A clean status bar: 10:00, full battery and signal, no icons."""
        if not on:
            self.shell('am', 'broadcast', '-a', 'com.android.systemui.demo',
                       '-e', 'command', 'exit', check=False)
            return
        self.shell('settings', 'put', 'global', 'sysui_demo_allowed', '1',
                   check=False)
        for extra in (['command', 'enter'],
                      ['command', 'clock', '-e', 'hhmm', '1000'],
                      ['command', 'battery', '-e', 'level', '100',
                       '-e', 'plugged', 'false'],
                      ['command', 'network', '-e', 'wifi', 'show',
                       '-e', 'level', '4'],
                      ['command', 'network', '-e', 'mobile', 'hide'],
                      ['command', 'notifications', '-e', 'visible', 'false']):
            self.shell('am', 'broadcast', '-a', 'com.android.systemui.demo',
                       '-e', *extra, check=False)


class Tour:
    def __init__(self, device, media, out):
        self.device = device
        self.media = media
        self.out = out
        self.marks = []
        self.recorder = None
        self.started = None

    def files(self):
        return sorted(p.name for p in self.media.iterdir()
                      if p.suffix.lower() in ('.mp3', '.mp4', '.srt', '.vtt', '.lrc'))

    def ready(self):
        for permission in ('POST_NOTIFICATIONS', 'READ_MEDIA_AUDIO',
                           'READ_MEDIA_VIDEO'):
            self.device.shell('pm', 'grant', PACKAGE,
                              f'android.permission.{permission}', check=False)
        self.device.demo_mode(True)

    def shot(self, name):
        png = self.device.adb('exec-out', 'screencap', '-p').stdout
        (self.out / f'{name}.png').write_bytes(png)
        print(f'  shot {name}')

    def record_start(self):
        cmd = ['adb'] + (['-s', self.device.serial] if self.device.serial
                         else [])
        self.recorder = subprocess.Popen(
            cmd + ['shell', 'screenrecord', '--bit-rate', '20000000',
                   REMOTE_VIDEO])
        # screenrecord's first frame comes a moment after it starts.
        time.sleep(0.8)
        self.started = time.monotonic()
        print('  recording')

    def mark(self, sid):
        if self.started is not None:
            t = round(time.monotonic() - self.started, 3)
            self.marks.append({'id': sid, 't': t})
            print(f'  {sid} at {t} s')

    def record_stop(self):
        if self.recorder is None:
            return
        self.device.shell('pkill', '-INT', 'screenrecord', check=False)
        try:
            self.recorder.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.recorder.kill()
        self.recorder = None
        time.sleep(1)
        self.device.adb('pull', REMOTE_VIDEO, str(self.out / 'tour.mp4'))
        self.device.shell('rm', REMOTE_VIDEO, check=False)
        print('  recording saved')


def handler_for(tour):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, body=b'ok', kind='text/plain'):
            self.send_response(200)
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = unquote(self.path)
            try:
                if path == '/media':
                    self.reply(json.dumps(tour.files()).encode(),
                               'application/json')
                elif path.startswith('/media/'):
                    name = Path(path[len('/media/'):]).name
                    self.reply((tour.media / name).read_bytes(),
                               'application/octet-stream')
                elif path == '/ready':
                    tour.ready()
                    self.reply()
                elif path.startswith('/shot/'):
                    tour.shot(Path(path).name)
                    self.reply()
                elif path.startswith('/mark/'):
                    tour.mark(Path(path).name)
                    self.reply()
                elif path == '/record/start':
                    tour.record_start()
                    self.reply()
                elif path == '/record/stop':
                    tour.record_stop()
                    self.reply()
                else:
                    self.send_error(404)
            except Exception as e:  # noqa: BLE001 - reported to the test
                self.send_error(500, str(e))
    return Handler


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('media')
    parser.add_argument('out')
    parser.add_argument('--form', choices=FORMS, default='phone')
    parser.add_argument('--device')
    parser.add_argument('--record', action='store_true')
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    device = Device(args.device)
    tour = Tour(device, Path(args.media), out)
    size, density = FORMS[args.form]
    if size:
        device.shell('wm', 'size', size)
    if density:
        device.shell('wm', 'density', density)
    device.adb('reverse', f'tcp:{PORT}', f'tcp:{PORT}')
    server = ThreadingHTTPServer(('127.0.0.1', PORT), handler_for(tour))
    threading.Thread(target=server.serve_forever, daemon=True).start()

    flutter = shutil.which('flutter') or 'flutter'
    cmd = [flutter, 'test', 'integration_test/play_tour_test.dart',
           '--flavor', 'play', '--dart-define=PLAY_STORE_BUILD=true',
           f'--dart-define=TOUR_HOST=http://127.0.0.1:{PORT}',
           f'--dart-define=TOUR_FORM={args.form}']
    if args.device:
        cmd += ['-d', args.device]
    if args.record:
        cmd.append('--dart-define=TOUR_RECORD=true')
    try:
        result = subprocess.run(cmd, cwd=ROOT)
    finally:
        tour.record_stop()
        server.shutdown()
        device.adb('reverse', '--remove', f'tcp:{PORT}', check=False)
        device.demo_mode(False)
        if size:
            device.shell('wm', 'size', 'reset', check=False)
        if density:
            device.shell('wm', 'density', 'reset', check=False)
        if tour.marks:
            (out / 'marks.json').write_text(json.dumps(tour.marks, indent=2),
                                            encoding='utf-8')
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
