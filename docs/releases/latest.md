# Release Notes - v14.0.0

## Reliable play stats, simpler video playback, real volume leveling, and a friendlier error experience

### Fixed

* **Play counts and time played now stay in sync.** Listening time was added as the track's *absolute* position on every app-lifecycle/select event (so it double counted), while the play count was only recorded after several awaited steps that could be skipped. Time is now committed as a delta since the last commit (also saved every 30 s and on track completion), the play count is refreshed in the UI immediately, and per-track stats are re-baselined on each new play.
* **Videos no longer restart from the start after you leave the app.** Videos are now treated differently from songs: the glitchy video-to-audio "background mode" hand-off has been removed. A video simply pauses when the app goes to the background (Android) and keeps its position; on desktop, losing window focus no longer touches playback.
* **Browser "Clear browsing data" now really clears everything.** It previously wiped history only and needed an open page; quick-access links (recent sites) were never cleared. Both are cleared now, and the new-tab page refreshes right away.
* **Browser Refresh button** now performs a real reload and refreshes the quick-access tiles on the new-tab page (it used to do nothing there).

### Improved

* **Volume leveling (new, on by default).** Every track/video is measured once (FFmpeg `volumedetect`, cached) and played at a common target loudness, so a very quiet track and a very loud one sound equally loud. Toggle it with the equaliser icon in the player toolbar.
* **Errors are impossible to miss.** Error messages now have a red border, a bug icon, a longer display time and a light-hearted headline above the real message.
* **Releases now include screenshots and a README link** automatically (appended by the release workflow).

### Removed

* **Linux builds are discontinued.** The release workflow no longer builds or publishes Linux artifacts.

### Build Notes

* Android Play AAB built with `--flavor play` (version 14.0.0+1288).
* Release workflow builds Windows, macOS, and Android artifacts.
* GitHub release tag: v14.0.0
* Release page: [v14.0.0](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.0.0)
