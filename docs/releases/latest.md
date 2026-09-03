# Release Notes - v13.0.5

## yt-dlp / youtube_explode_dart Reliability Pass v2

## Highlights

* **Android playlist loading fixed.** Large YouTube playlists (e.g. 785 tracks) now load reliably. The app wires a JS-challenge solver (Deno) into youtube_explode_dart — the same runtime yt-dlp uses — so YouTube's bot check no longer silently starves the playlist stream.
* **CJK title matching improved.** Downloaded tracks with Japanese/Chinese titles no longer get marked as "missing" when re-scanned. Added character-bigram similarity as a fallback tier so titles without spaces between words match correctly.
* **Japanese author names display correctly.** Broadened filename artist parsing to recognize `/`, `_`, and `【】` tag prefixes (common in Japanese/VOCALOID uploads), and switched the local-library tag read to the same metadata package the rest of the codebase already trusts.
* **"Could not check for updates" no longer intermittent.** The update check is now cached for an hour and branches on GitHub's 403 rate-limit response with a clear message.
* **"yt-dlp missing" no longer shows during active downloads.** The status indicator now distinguishes "checking", "transient error", and "genuinely not configured".

## Build Notes

* GitHub release tag: `v13.0.5`
* Release page: [v13.0.5](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.5)
* `flutter analyze` and `flutter test --coverage` pass cleanly.
