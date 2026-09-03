# Release Notes — v13.0.5

## What's New
- **Android playlist loading fixed.** Large YouTube playlists (e.g. 785 tracks) now load reliably on Android. The app wires a JS-challenge solver (Deno) into youtube_explode_dart — the same runtime yt-dlp uses — so YouTube's bot check no longer silently starves the playlist stream.
- **CJK title matching improved.** Downloaded tracks with Japanese/Chinese titles no longer get marked as "missing" when re-scanned. Added character-bigram similarity as a fallback tier so titles without spaces between words match correctly.
- **Japanese author names display correctly.** Broadened filename artist parsing to recognize `/`, `_`, and `【】` tag prefixes (common in Japanese/VOCALOID uploads), and switched the local-library tag read to the same metadata package the rest of the codebase already trusts.
- **"Could not check for updates" no longer intermittent.** The update check is now cached for an hour and branches on GitHub's 403 rate-limit response with a clear message, so a burst of failed downloads can't exhaust the quota exactly when the self-heal path needs it most.
- **"yt-dlp missing" no longer shows during active downloads.** The status indicator now distinguishes "checking", "transient error", and "genuinely not configured" instead of collapsing straight to "not installed".

## Bug Fixes
- Deleted dead, unguarded yt-dlp update-polling code that was never called.
- Cinematic view removed (continues from v13.0.3).

See [CHANGELOG.md](CHANGELOG.md) for fuller details.
