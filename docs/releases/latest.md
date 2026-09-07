# Release Notes - v13.0.12

## QA Fixes & Stability

## Fixes

* **Windows startup crash fixed.** Removed the `WebViewEnvironment.create()` call that crashed on some machines (notably lower-end CPUs); the WebView EJS solver now initializes lazily with memoized, always-reset futures so a silent init failure can't wedge the app.
* **Share button shares the actual media file** instead of just an app link and the song title, with a text fallback for streamed files not on disk.
* **Session logs now actually get written on normal close.** Two competing window-close paths raced each other; they're consolidated into a single path so log flushing always runs before exit.
* **Consistent button sizing app-wide** via unified `ButtonStyle` themes (filled/outlined/elevated) — fixes the mismatched "Add Magnet" button and similar inconsistencies.
* **Mobile now-playing row overflow fixed.** The share icon no longer overlaps the AUDIO badge on phones; the row clips cleanly and icon buttons were compacted.
* **yt-dlp diagnostics added** for the Deno JS-runtime fallback (silent-failure path now logs), to pin down the low-end-only "page needs to be reloaded" failures.

## Build Notes

* GitHub release tag: v13.0.12
* Release page: [v13.0.12](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.12)
* flutter analyze passes cleanly.
