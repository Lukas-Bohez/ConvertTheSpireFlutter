# Store trailer and screenshots

A store listing with a video sells better than screenshots alone: it is the
first thing on the Microsoft Store page, and Google Play shows it above the
screenshots. The trailer and the screenshots in `docs/screenshots/store/` are
recorded from the real app, so they are made again in a few minutes whenever
the app changes.

## What is in it

About 50 seconds at 1920×1080: a title card, then each feature with a
caption, then a closing card.

| Part | Caption |
|---|---|
| Home, a link pasted in | Download from 1,800+ sites as MP3, M4A or MP4 |
| The player and the library | One player for your music and videos |
| A video with its subtitles | Subtitles load by themselves |
| The large view | Watch big, without the clutter |
| Marking a part to loop | Loop just the best part |
| Speed 1.5× | Change the speed, set a sleep timer |
| A torrent seeding | A torrent client built in |
| The browser | A browser with a real ad blocker |
| Colours changing | Make it yours: 28 colours, light and dark |

There is no music: the stores play trailers muted, and music needs a licence.
The library in it is generated (made-up artists, FFmpeg's own pictures and
tones), so nothing in it belongs to anyone else.

## Making it

On Windows, with nothing else on the main display for a minute (the tour
fills it, 1920×1080 at 100% scaling):

```powershell
$ffmpeg = 'microsoft-upload\.tools\ffmpeg\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe'
$tmp = "$env:TEMP\store-tour"

# 1. The demo library (once; about 250 MB).
python scripts/make_demo_media.py "$tmp\media" --ffmpeg $ffmpeg

# 2. The tour: records the screen and takes the store screenshots.
flutter test -d windows integration_test/store_tour_test.dart `
  --dart-define=MS_STORE_BUILD=true --dart-define=TOUR_RECORD=true `
  --dart-define=DEMO_MEDIA="$tmp\media" --dart-define=TOUR_OUT="$tmp\out" `
  --dart-define=FFMPEG="$((Resolve-Path $ffmpeg).Path)"

# 3. The trailer and its thumbnail.
python scripts/store_trailer.py "$tmp\out" microsoft-upload\trailer\trailer.mp4 --ffmpeg $ffmpeg
```

The tour runs the app in a sandbox: settings in memory, its own data folder,
peer discovery off. It never touches the installed app's library, torrents or
settings. The screenshots land in `$tmp\out`; copy the good ones to
`docs/screenshots/store/`.

**Look at the recording before using it.** A notification that pops up while
it records ends up in the video: on the PC this was made on, Malwarebytes
reported the installed app's torrent connections. Close the installed app
first, or cut the trailer before the notification: `--stop-at 45.3` ends it
at that second of the recording (`--until speed` before that feature). To
find the second, `marks.json` in the tour folder says when each feature
starts.

## Uploading it

**Microsoft Store.** Partner Center → the app → the submission → Store
listings → English → **Trailers**: upload `trailer.mp4`, with
`trailer-thumbnail.png` (1920×1080) as its thumbnail and "Convert the Spire
Reborn in 50 seconds" as its title. The other languages can use the same
trailer. A trailer goes live with the next submission.

**Google Play** takes a YouTube link, not a file: Play Console → Grow →
Store presence → Main store listing → **Video**. Upload the Play trailer
(below) to YouTube (public or unlisted, ads off, not "made for kids"),
then paste its link.

## The Google Play trailer and screenshots

The Play version is BitPlayer, without the downloader, so it has its own
tour, of the Play build on Android emulators: a phone, a tablet (which
also plays the Chromebook, at desktop density) and an Android TV.

```powershell
$ffmpeg = 'microsoft-upload\.tools\ffmpeg\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe'
$tmp = "$env:TEMP\store-tour"

# One emulator at a time: three at once ran out of memory.
python scripts/play_tour.py "$tmp\media" "$tmp\play\phone" --form phone --device emulator-5554 --record
python scripts/play_tour.py "$tmp\media" "$tmp\play\tablet" --form tablet --device emulator-5556 --record
python scripts/play_tour.py "$tmp\media" "$tmp\play\chromebook" --form chromebook --device emulator-5556 --record
python scripts/play_tour.py "$tmp\media" "$tmp\play\tv" --form tv --device emulator-5558 --record

python scripts/play_trailer.py "$tmp\play\trailer.mp4" --ffmpeg $ffmpeg `
  --phone "$tmp\play\phone" --tablet "$tmp\play\tablet" --tv "$tmp\play\tv"
python scripts/play_feature_graphic.py "$tmp\play\phone\2-player.png" "$tmp\play\phone\3-video-subtitles.png"
```

The emulators used: a Pixel 6 (Android 13, Google APIs), a Pixel Tablet
(Android 13, Google APIs) and the Android TV 1080p image. `play_tour.py`
sets each screen to the size Play takes (a phone 1080x1920, a tablet
2560x1440, a Chromebook 1920x1080), tidies the status bar (10:00, full
battery) and puts both back afterwards. The test serves itself the demo
media from the computer over `adb reverse`; nothing is copied onto the
device. Copy the screenshots to `store/google-play/screenshots/<kind>/`.

The same YouTube link is good for the GitHub README and the website.
