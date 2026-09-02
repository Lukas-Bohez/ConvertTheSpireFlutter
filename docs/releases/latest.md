# Release Notes - v13.0.4

## yt-dlp "page needs to be reloaded" Fix

## Highlights

* **Downloads self-heal when YouTube changes its player/extractor.** When a download fails with "The page needs to be reloaded", `UNPLAYABLE`, or bot/age-check errors, the app now auto-updates the yt-dlp binary (throttled to once per 2 hours per session) and retries the download once. YouTube-side nsig/SABR changes are patched on stable yt-dlp releases within days, so a refresh routinely restores downloads that a pinned binary was failing.
* **A JavaScript runtime is now bundled for yt-dlp.** Modern yt-dlp needs an external JS interpreter to evaluate YouTube's signature code; without one it emits "page needs to be reloaded" / UNPLAYABLE errors. The app detects a system Deno/Node install or lazily downloads a standalone Deno binary into the app support dir and passes it to yt-dlp via `--js-runtimes deno:...`.
* **Cinematic view removed** (from v13.0.3). The player now uses the standard fullscreen album/song view instead of the ambient shader.

## Build Notes

* GitHub release tag: `v13.0.4`
* Release page: [v13.0.4](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.4)
* `flutter analyze` and `flutter test --coverage` pass cleanly.
