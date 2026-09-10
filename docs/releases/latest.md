# Release Notes - v13.1.0

## Playlist parsing and Windows browser fixes

## Fixes

* **EU/UK playlists could load 0 tracks.** YouTube's cookie-consent wall now sends `SOCS=CAI` on playlist requests, so EEA users get the full playlist page (824-track fixture verified) instead of a consent interstitial with no `ytInitialData`.
* **Windows in-app browser could hang at first load.** The WebView2 init path no longer awaits its own readiness future (`_init` → `applySettings` → `_ensureReady` deadlock) — a re-entrancy guard fixes initialization on the first run.
* **Windows browser crash-recovery hardened.** A failed WebView2 init now retries with a fresh controller (never re-`initialize()`s the same instance, avoiding "Stream has already been listened to"), and persistent failures show an inline error with a Retry button.

## Improvements

* New deterministic crash-recovery tests (injected fake controller — no WebView2 runtime required) verify retry state and the absence of stream-listener collisions. EEA playlist + consent-interstitial fixtures added.

## Build Notes

* GitHub release tag: v13.1.0
* Release page: [v13.1.0](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.1.0)
* `flutter analyze` clean; all 71 tests pass; release workflow builds Windows, Linux, macOS, Android, and web artifacts.

