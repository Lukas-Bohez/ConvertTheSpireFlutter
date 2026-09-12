# Convert the Spire Reborn v13.2.1

## yt-dlp SABR/player_client fix, browser tab thumbnails, decode fix, live Missing tab

### Fixed

- **YouTube downloads failing with "the page needs to be reloaded" — root cause found and fixed.** The app was forcing `--extractor-args youtube:player_client=tv,web` on every download under the belief that the tv client avoids YouTube's SABR-only streaming experiment. Live verification (2026-09, yt-dlp 2026.08.19, Deno 2.9.6) proved it now *causes* the failure it was meant to prevent: the tv player response returns UNPLAYABLE, and the web client's https formats are skipped as "missing a URL" (YouTube is forcing SABR streaming for that client, yt-dlp#12482). The override is removed; downloads now use yt-dlp's default client order. Verified via bisection on the affected Windows machine and independently confirmed against yt-dlp#12482 and an Arch Linux forum thread — the `tv` client specifically is affected, not just `web`.
- **Browser tab-switcher screenshot thumbnails stretched to 16:9 at decode time.** The tab-switcher's `Image.memory` and `Image.file` in `browser_screen.dart` passed paired `cacheWidth: 640, cacheHeight: 360` decode hints. A browser page's rendered viewport has no guaranteed aspect, so non-16:9 pages were pre-stretched at decode time. Dropped `cacheWidth`, kept `cacheHeight: 360` (aspect-preserving).
- **Thumbnail stretching in the now-playing hero card and the mini-player bar.** All thumbnail sites passed paired `cacheWidth`+`cacheHeight` decode hints sized to the display box. `instantiateImageCodec` scales to exactly those dimensions without preserving the source image's own aspect, so square or portrait thumbnails were pre-stretched at decode time. Decode hints are now height-only (aspect-preserving) at every site.
- **Playlist "Missing" tab going stale after downloading missing tracks.** `Download Selected` only queues downloads and returns immediately, and nothing ever re-ran the folder compare afterwards. The playlist screen now listens to `AppController` and moves tracks Missing → Matched in memory immediately when a queue item reaches `completed`.
- **Misleading "self-update failed" error** from yt-dlp reload-error recovery. The catch block wrapped both the self-update call and the post-update retried download, hiding the fact that a current yt-dlp still can't extract the video. The two outcomes are now reported distinctly.

### Build Notes

- `flutter analyze` clean; all 79 tests pass.
- Release workflow builds Windows, Linux, macOS, and Android artifacts.
