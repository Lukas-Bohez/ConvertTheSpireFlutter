# Crash Diagnosis Inventory

This is the read-only inventory for the long-running crash investigation. It records confirmed resource leaks, memory-pressure candidates, and places that were checked and appear to be cleaned up correctly. No fixes are applied here.

## Phase 1 - Confirmed lifecycle leaks

- `lib/src/vault/services/torrent_service.dart`
  - `StreamController<List<TorrentViewState>>.broadcast()` is created for `_torrentStatesController`, but no matching `close()` or `dispose()` was found.
  - Impact: long-lived broadcast controller remains open for the app lifetime.

- `lib/src/vault/services/torrent_engine_service.dart`
  - `StreamController<TorrentEngineStatus>.broadcast()` is created for `_statusController`, but no matching `close()` or `dispose()` was found.
  - Impact: long-lived broadcast controller remains open for the app lifetime.
  - Important exception: the torrent timers themselves are cleaned up in `_cleanup(torrentId)` via `cancel()` on every tracked timer map, so the timers are not the confirmed leak here.

- `lib/src/services/yt_dlp_updater.dart`
  - `final client = http.Client();` is created in `downloadAndReplace(...)` and no `client.close()` was found in the method.
  - Impact: one HTTP client / socket pool can stay alive after each update attempt.

## Phase 1 status - addressed in current pass

- `lib/src/state/app_controller.dart`
  - Shutdown now calls `TorrentService.instance.dispose()` and `TorrentEngineService.instance.dispose()`.

- `lib/src/vault/services/torrent_service.dart`
  - Added `dispose()` to close `_torrentStatesController`.

- `lib/src/vault/services/torrent_engine_service.dart`
  - Added `dispose()` to cancel all tracked timers and close `_statusController`.

- `lib/src/services/yt_dlp_updater.dart`
  - `downloadAndReplace(...)` now closes its `http.Client` in `finally`.

## Phase 2 - Memory-pressure candidates

- `lib/main.dart`
  - No explicit `PaintingBinding.instance.imageCache.maximumSize` or `maximumSizeBytes` cap was found.
  - Impact: image decoding/cache growth is left at Flutter defaults.

- `lib/src/screens/search_screen.dart`
  - Search result thumbnails use `Image.network(...)` without explicit cache sizing hints.

- `lib/src/screens/home_screen.dart`
  - Thumbnails also use `Image.network(...)` without explicit cache sizing hints.

- `lib/src/screens/browser/new_tab_page.dart`
  - Favicons use `Image.network(...)` without explicit cache sizing hints.

- `lib/src/screens/browser/history_screen.dart`
  - Favicons use `Image.network(...)` without explicit cache sizing hints.

- `lib/src/screens/browser/favourites_screen.dart`
  - Favicons use `Image.network(...)` without explicit cache sizing hints.

- `lib/src/vault/screens/torrents_screen.dart`
  - The torrents dashboard still builds its active-download rows from in-memory lists rather than a paged data source.
  - `GridView.builder` is used for the wide layout, but the overall source collections remain fully materialized in memory.

- `lib/src/screens/player.dart`
  - `library` is kept as a full in-memory list of `MediaItem`s.
  - Good news: the historical selection list is already capped at 50 entries, so the history side of this path is bounded.

## Phase 3 - Native/plugin lifecycle review

- `lib/src/screens/player.dart`
  - `Player`, `VideoController`, `AudioPlayer`, stream subscriptions, and the position UI controller all have explicit cleanup paths.
  - No confirmed leak here from the inspected code.

- `lib/src/services/preview_player_service.dart`
  - Preview `AudioPlayer` instances are stopped and disposed in `stopPreview()` and `dispose()`.
  - No confirmed leak here.

- `lib/src/services/dlna_discovery_service.dart`
  - Socket subscription and timeout timer are canceled / closed during discovery cleanup.
  - No confirmed leak here.

- `lib/src/vault/screens/browser_screen.dart`
  - Windows WebView controller is explicitly disposed in `dispose()`.
  - No confirmed leak here.

- `lib/src/screens/browser_screen.dart`
  - App shutdown path calls `disposeAllWebViewControllers()`, but the method currently stops loading and navigates to `about:blank` rather than performing a full controller disposal.
  - This is a follow-up candidate, not yet a confirmed leak.

- `lib/src/services/installer_service.dart`, `lib/src/services/download_service.dart`, `lib/src/services/yt_dlp_service.dart`
  - HTTP clients are explicitly closed in the inspected paths.
  - No confirmed leak here.

- `lib/src/vault/services/search_service.dart`
  - `_resultsController.close()` is called in `dispose()`.
  - No confirmed leak here.

## Notes

- `lib/src/vault/services/torrent_engine_service.dart` does have per-torrent timer cleanup, so the confirmed issue there is the unclosed broadcast controller, not the timer maps.
- `lib/src/vault/services/sound_service.dart` keeps a static `AudioPlayer` for the app lifetime. That looks intentional, but it is still a persistent native handle and should be revisited if shutdown cleanup becomes a goal.