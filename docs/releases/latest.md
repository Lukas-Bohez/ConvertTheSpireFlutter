# Release Notes - v13.0.8

## Low-End Stability & Playlist Reliability

## Fixes

* **Crash entering the Torrents tab on low-end PCs.** Concurrent first-opens of the vault database (app startup vs. the Torrents tab building instantly on entering Vault) could race two openDatabase calls against the same file and throw; the fix memoizes a single in-flight open Future and makes TorrentsScreen await vault bootstrap before its first DB access.
* **yt-dlp "auto repair failed" on slow machines.** The Windows binary-replace step in a self-update had no retry, so a transient lock on the just-exited yt-dlp.exe (antivirus scan, slow OS handle teardown) would hard-fail the download; the rename now retries with backoff, and a self-update failure falls back to one plain retry with the existing binary instead of failing immediately.
* **Android playlist import still returning 0 tracks on large playlists.** Added per-video diagnostic logging, raised the inter-page idle timeout, and added smarter retry.

## Build Notes

* GitHub release tag: v13.0.8
* Release page: [v13.0.8](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.8)
* flutter analyze and flutter test pass cleanly.

* GitHub release tag: `v13.0.7`
* Release page: [v13.0.7](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.7)
* `flutter analyze` passes cleanly.
* Play AAB not required for this hotfix (Play builds were unaffected).
