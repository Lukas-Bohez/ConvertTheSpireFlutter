# Release Notes - v13.1.0

## Highlights

- **Fixed: playlists loading 0 tracks in the EU/UK.** YouTube serves a
  "before you continue" cookie-consent interstitial page — with no
  `ytInitialData` — to requests made from EEA-geolocated IPs that don't
  carry the current consent cookie. The app now sends `SOCS=CAI`
  ("accept all") on both the initial playlist GET and the pagination
  `browse` POST, so the full playlist page is received instead of the
  consent shell. **Verified:** an 824-track EEA fixture now parses all
  824 entries (previously 0), and the consent-interstitial page (no
  `ytInitialData`) degrades to zero videos with no crash.
- **Fixed: Windows in-app browser could hang at first load.** The WebView2
  init path re-entered its own readiness future (`_init` → `applySettings`
  → `_ensureReady` awaited the in-flight `_init` future), deadlocking the
  browser screen the first time it initialized. A re-entrancy guard now
  lets the post-init setup proceed once the controller reports
  initialized. **Verified:** new deterministic unit test that would
  previously time out now passes in ~2s.
- **Hardened: Windows browser WebView2 crash-recovery.** If controller
  creation fails (missing runtime, first-run profile setup, GPU issue),
  the adapter now discards the failed controller and retries with a
  **brand-new instance** — never re-calling `initialize()` on the same
  one, which `webview_windows` 0.4.0 rejects with "Bad state: Stream has
  already been listened to". On persistent failure the browser shows an
  inline error with a Retry button. **Verified:** new crash-recovery tests
  deliberately fail the first `initialize()` (via an injected fake
  controller), confirm a fresh controller is minted per retry
  (`_initState == true` after recovery), and confirm repeated failures
  never produce a stream-listener collision.

## Under the hood

- The Windows browser adapter now takes an optional `controllerFactory`
  injection point, letting the crash-recovery path be tested with a
  deterministic fake — no WebView2 runtime needed, so the tests run on
  every CI platform.
- New tests: `test/browser_webview_windows_test.dart`
  (crash-recovery + retry), plus the 824-track EEA fixture and consent
  interstitial cases in `test/services/playlist_service_test.dart`.
- `flutter analyze` clean; **all 71 tests pass**.