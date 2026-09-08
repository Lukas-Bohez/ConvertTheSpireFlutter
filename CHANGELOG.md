# Changelog

## 13.0.13+1276 窶・Low-End CPU Stability Fixes

### Fixed
- **metadata_god / flutter_rust_bridge codegen mismatch (library refresh crash).** metadata_god 1.1.0's shipped Rust library was built with frb codegen 2.11.1 while pub resolved frb runtime 2.12.0, so every library refresh / folder pick threw `ZONE ERROR: Bad state: metadata_god's codegen version (2.11.1) should be the same as runtime version (2.12.0)`. `flutter_rust_bridge` is now pinned to 2.11.1 as a direct dependency.
- **Deno provisioning could never succeed (yt-dlp "page needs to be reloaded").** `DenoRuntimeService.resolveOrDownload()` computed the destination as `deno-x86_64-pc-windows-msvc` (no `.exe`) while the official Windows zip extracts `deno.exe`, so download+extract succeeded but lookup failed and the whole zip was re-downloaded on every attempt. The provisioned-binary lookup now checks `deno.exe` / `deno` / `$destBase.exe` / `destBase` before and after extraction, and all outcomes (success and each failure mode) are surfaced via `SessionLogService.markOnce` keys (`deno-ok`, `deno-not_on_path`, `deno-download_failed_http_*`, `deno-verify_failed_*`, `deno-binary_not_found`, …).
- **Burst-pause log spam.** `downloadAll()` workers each logged "Pausing downloads — YouTube may be rate-limiting…" every 15 s for the whole pause (a 7-minute pause with 3 workers ≈ 84 identical entries). Pause/resume is now logged once per pause window with a single worker, and a "Burst pause over — resuming downloads" line follows.
- **Add Magnet button sizing.** The torrents empty state's `Add Magnet` button (kept as the emphasized primary `FilledButton.icon` action) is height-pinned via the unified button theme's `maximumSize`, fixing the mismatched/overflowing appearance.

## 13.0.12+1275 — Single Close Path & Ship Fixes

### Changed
- **Window-close handling consolidated into a single path.** `TrayService` no longer reacts to `onWindowClose` — `_MyAppState` in `app.dart` is the sole close path. This eliminates the v13.0.11 race at its root (previously `onTrayQuit`'s `exit(0)` could kill the process before app.dart's slower teardown flushed the session log; now there is only one teardown sequence). Geometry is saved explicitly on close, the tray icon is destroyed on quit so it doesn't linger, and a failed hide-to-tray now falls through to full teardown instead of leaving the window stuck open.

## 13.0.11+1274 — QA Fixes & yt-dlp Diagnostics

### Fixed
- **Share button now shares the actual audio file.** Was `Share.share(text)`, which only ever shared an app-store link and the song title. Now shares the real file via `SharePlus.instance.share(ShareParams(files: [XFile(item.path)]))` (matching the pattern in `home_screen.dart`), falling back to a text-only share only if the file isn't on disk (e.g. streamed).
- **Missing session logs on normal close — found the actual cause.** Two independent `WindowListener`s (`app.dart` and `TrayService`) both fire `onWindowClose`. `TrayService`'s `onTrayQuit` calls `exit(0)` immediately, which kills the process before `app.dart`'s slower `onWindowClose` (which poll for WebView2 teardown before flushing) ever reaches its flush line. Fixed by flushing the session log first in the `onTrayQuit` path, so whichever path wins the race, the log is already on disk.
- **Inconsistent button sizing — unified at the theme level.** No `FilledButtonTheme`/`OutlinedButtonTheme`/`ElevatedButtonTheme` existed, so different button types fell back to Material 3's per-type defaults (not guaranteed identical once icons are involved). One shared `_unifiedButtonStyle` applied to all three in both light and dark themes fixes it everywhere at once.
- **Mobile share-icon-over-badge glitch.** The now-playing card's track-info `Row` overflows on real phone widths; `Row`'s default `clipBehavior: Clip.none` paints overflowing children at their out-of-bounds position, landing the share icon on top of the type badge. Wrapped the `Row` in `ClipRect(clipBehavior: Clip.hardEdge)` (clean crop instead of overlap) and added `visualDensity: VisualDensity.compact` on the three icon buttons (share/favourite/dislike) to shrink their footprint.

### Added
- **Deno binary verification.** `DenoRuntimeService.resolveOrDownload()` now runs `deno --version` on every resolved binary (cached, system-found, and newly-downloaded) instead of only checking file existence. Logs which failure mode a low-end PC hits — "not found", "download failed (HTTP N)", or "exists but won't run" — so the next round can fix the specific cause rather than guessing.
- **yt-dlp Deno-unavailable warning.** When the Deno JS runtime can't be resolved (the silent failure path), a debugPrint now fires pointing to the deno-runtime logs, making "page needs to be reloaded" failures debuggable.

### Internal
- Node.js detection path (`_tryApplyNodeRuntime`) now logs when Node isn't found, so the Deno fallback is observable rather than silent.



### Fixed
- **Windows startup crash on older CPUs (root cause found via crash dumps).** `flutter_inappwebview`'s Windows plugin ships a binary containing BMI2 instructions (confirmed: `EXCEPTION_ILLEGAL_INSTRUCTION` at a fixed offset in `flutter_inappwebview_windows_plugin.dll`), and the app eagerly created a `WebViewEnvironment` at startup, crashing pre-2013/2015 CPUs instantly. The in-app browser on Windows now runs on WebView2 (`webview_windows`) via a platform adapter; `flutter_inappwebview` remains for Android/iOS only. Android behaviour is unchanged.
- **Headless WebView JS solver race.** `WebViewEJSSolver._ensureReady()` now memoizes its initialization as a single in-flight Future (same pattern as the v13.0.8 database fix), so concurrent YouTube metadata calls can't race two headless WebView inits.

### Changed
- **All player thumbnails are 16:9** (same width as before, height derived from it): track-list rows were square, library grid cards filled the whole card; both are now 16:9, with the grid card shape retuned to match.

### Added
- **Session diagnostics for slow starts.** Timestamped startup breadcrumbs (flavor init, permissions, ads, media kit, window ready, first frame) are written to `session_log_<timestamp>.log` in the documents folder on every normal app close - not only on crashes - so slow-start reports come with real phase timings. Crash/error paths now flush the same log.

## 13.0.8+1271 — Low-End Stability & Playlist Reliability

### Fixed
- **Crash entering Torrents tab on low-end PCs.** Memoized the vault DB open as a single in-flight Future so concurrent first callers don't race two opens; `TorrentsScreen` now awaits `VaultBootstrap.ensureInitialized()` before its first DB access.
- **yt-dlp self-update hard-failing on slow machines.** The Windows binary-replace in `updateYtDlp` now retries with backoff on transient file locks; a self-update failure falls back to one plain retry with the existing binary before surfacing an error.
- **Android playlist import returning 0 of ~790.** Added per-video logging, raised the inter-page idle timeout to 180s, and retry stops when an attempt makes no net progress.

### Internal
- CI release workflow verifies the built APK is not debug-signed and hard-fails if signing secrets are absent.

## 13.0.6+1269 — Reliability Pass v2 Completion + Monetization Wiring

### Fixed
- **Android playlist loading** — headless WebView JS challenge solver (`WebViewEJSSolver`) replaces Deno on mobile; Deno stays desktop-only.
- **Orphaned downloads on cancel** — cancelling no longer leaves behind the intermediate `.mp4`/`.webm` yt-dlp was writing; cleanup now scans for all files sharing the output stem.
- **Reload errors during update cooldown** — a "page needs to be reloaded" failure now gets a plain retry even while the 2-hour self-update cooldown is active, instead of failing with zero retries.
- **Reload-error bursts** — 3+ reload errors within 5 minutes are treated as a YouTube-side throttle: the queue pauses for 7 minutes with a visible message instead of hammering into it.
- **AdMob** — native ads are now theme-aware; new placements in Watched Playlists and the Support screen.
- **Torrent background survival** — the Android torrent service runs in foreground mode so the OS won't kill it in the background.

### Added
- **Vault** — database encryption key is now provisioned via `flutter_secure_storage` and wired into both bootstrap paths.
- **Ollama (Android)** — clearer connectivity UX: desktop-only buttons hidden, network panel with `OLLAMA_HOST=0.0.0.0` guidance, actionable error messages.
- **Play build** — "Advanced build on GitHub" link added to the Support screen.
- **Motion tokens** adopted across onboarding; shared `EmptyState` widget reused in the vault torrents screen.

## 13.0.5+1268 — yt-dlp / youtube_explode_dart Reliability Pass v2

### Added
- **DenoRuntimeService** — shared Deno provisioning for both yt-dlp's `--js-runtimes` and youtube_explode_dart's `DenoEJSSolver`, so a single provisioned binary serves both.
- **Bigram similarity fallback** in `_titlesMatch` for CJK and other non-space-delimited scripts.

### Fixed
- **Android playlist loading** — wired `DenoEJSSolver` into the `YoutubeExplode` instance serving playlist loads; raised inactivity timeout 25s → 60s and made the retry loop continuation-aware.
- **CJK title matching** — character-bigram Dice-coefficient fallback so Japanese/Chinese titles no longer lose all matching tolerance.
- **Japanese author names** — broadened `_artistFromFilename` to recognize `/`, `_`, `／`, and `【】` tag prefixes; switched local-library tag read from `audio_metadata_reader` to `MetadataGod` for consistency.
- **"Could not check for updates"** — cached the latest-release check for an hour (SharedPreferences) and branched on HTTP 403 with a rate-limit-specific message.
- **"yt-dlp missing" during downloads** — status indicator now distinguishes checking / transient error / genuinely not configured.
- **Dead code** — deleted `yt_dlp_updater.dart` and `yt_dlp_update_controller.dart` (never called).

## 13.0.4+1267 — yt-dlp "page needs to be reloaded" Fix

### Fixed
- **Self-updating yt-dlp on "page needs to be reloaded" / UNPLAYABLE failures.** When a download fails with YouTube's "The page needs to be reloaded", `UNPLAYABLE`, or bot/age-check errors, the app now automatically updates the yt-dlp binary (throttled to once per 2 hours per session) and retries the download once. YouTube-side extractor/player (nsig/SABR) changes are patched on stable releases within days, so a refresh routinely restores downloads that a pinned binary was failing.
- **Bundled a JavaScript runtime (Deno) for yt-dlp.** Modern yt-dlp needs an external JS interpreter to evaluate YouTube's signature code; without one it emits "page needs to be reloaded" / UNPLAYABLE errors. The app now detects a system Deno/Node install or lazily downloads a standalone Deno binary (into the app support dir) and passes it to yt-dlp via `--js-runtimes deno:...`.
- **Kept the existing non-fatal fallback updater** (best-effort on boot) and made the download-path auto-update cooldown-aware so a failed burst doesn't hammer the GitHub API.

### Notes
- Also includes the v13.0.3 changes: cinematic view (and its ambient shader) fully removed.

## 13.0.3+1266 — Remove Cinematic View

### Removed
- **Cinematic view and all related code removed.** Deleted the ambient shader, the cinematic view screen, the ambient-scene widget, and the cinematic thumbnail renderer. The player now opens the standard fullscreen album/song view instead of the ambient shader. Removing it simplifies the player and avoids GPU/driver-specific rendering artifacts on a range of desktop hardware.

## 13.0.2+1265 — DLL Linking & Download Fix Release

### Fixed
- **Windows launch crash**: Removed the `SetDllDirectoryW`-based DLL subfolder mechanism that moved plugin DLLs into `dlls/` at packaging time. The Windows loader loads the executable's direct import dependencies before `wWinMain` runs, so `SetDllDirectoryW` — called inside `wWinMain` — could not resolve DLLs the loader needed during process startup, preventing the app from launching. All plugin DLLs now ship flat in the release root directory.
- **YouTube `androidVr` PO-token regression**: Replaced `androidVr` with `tv` in every youtube_explode_dart client list and in the yt-dlp `--extractor-args` passed to yt-dlp. YouTube now requires a GVS PO token for `androidVr` on anything above 360p, which was silently blocking HD downloads on all platforms. The `tv` client returns playable streams without PO tokens and works on desktop, Android, and iOS.
- **Windows release packaging**: Removed the `organize_dlls.ps1` invocation from the CI release workflow so DLLs are never moved into a subfolder that the Windows loader can't see at startup.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 13.0.1 — Regression Fix Release

### Fixed
- **Cinematic view** rebuilt with a new deterministic ambient shader and a non-blurred transport overlay. This fixes the solid white/grey layer that appeared when the controls faded in, the black top bar, and the overly flickering starfield.
- **Windows playback failures** caused by the YouTube `androidVr` client being selected on desktop. The fallback client list now avoids `androidVr` on Windows and prefers `tv`/`safari`/`ios`/`web` instead.
- **Windows release clutter:** plugin DLLs are now moved into a `dlls/` subfolder next to the executable, while the executable and its direct runtime dependencies remain in the root.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 13.0.0 — Linux Download Fix & Target API 36

### Fixed
- Linux and macOS builds now download the correct self-contained yt-dlp binary instead of a variant that silently required a system Python 3.11+ interpreter. This was the cause of "can't download playlists" and similar reports from Linux Mint users.
- `targetSdkVersion` raised to 36 (Android 16) for Play Store compliance.
- `build_release.sh` no longer hardcodes a stale version/build number; it now reads the version from `pubspec.yaml` like every other part of the build does, and sets the `GITHUB_RELEASE` build flag correctly for both flavors.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 10.7.1 — Fixed Windows Crash

### Highlights
- Fixed a crash where the Windows exe would not launch properly.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 5.2.0 — Bug Fix & Stability Release

### Fixed
- Android Share button now works with content:// URIs
- "Open Folder" button visible on Android queue items
- Browser shows WebView2 download link on older Windows PCs
- Linux AppImage for better compatibility on older distros

### Notes
- Bumped version to 5.2.0; see [docs/releases/latest.md](docs/releases/latest.md) for the current release notes.

## 5.0.0 — Production Polish Release

### New Features
- **Chromecast & AirPlay discovery** — mDNS-based scanning discovers Google Cast and AirPlay devices alongside DLNA renderers
- **Desktop window management** — window size, position, and geometry persist across sessions; minimum size enforced
- **Desktop media keys** — play/pause, next, previous, and Ctrl+Space shortcuts via CallbackShortcuts
- **Directory watcher** — media library auto-refreshes when files are added or removed on desktop
- **Download progress banner** — Android foreground notification shows remaining downloads during batch operations
- **Browser tab** — re-added as a first-class quick-link entry
- **HiAnime extraction** — difficult-site headers, cookies, and force-generic-extractor retry for yt-dlp

### Improvements
- **Virtualised player lists** — All and Favourites tabs use `ListView.builder` for large libraries
- **SafeArea audit** — all major screens respect system insets (notch, status bar, nav bar)
- **Accessibility** — player controls now have Semantics labels and Tooltips
- **Centralised strings** — `Strings` constants class for UI text
- **Code quality** — null-safe Range header parsing, race-condition-safe local media server, kIsWeb guards
- **Mobile nav labels** — shortened to fit 5-tab layout ("Search+", "Import")
- **URL bar** — single-line with ellipsis overflow, tap navigates to tab switcher
- **Miner auto-resume** — mining state persists across app restarts via SharedPreferences
- **Battery guard** — now pauses and resumes the native miner subprocess, not just isolate tasks
- **Error recovery** — exponential backoff on miner restarts (3 s → 6 s → 12 s), manual Retry button after max attempts
- **First-run consent dialog** — one-time prompt explaining mining before it can be enabled
- **Wallet constants** — extracted to `wallet_constants.dart` for single-source-of-truth

### Fixes
- `.gitignore` rewritten from corrupted UTF-16LE encoding
- Force-unwrap crashes in local_media_server.dart eliminated
- BrowserScreen widget test removed (requires platform InAppWebView)

### Internal
- Added `multicast_dns: ^0.3.2+1` dependency
- Added `FOREGROUND_SERVICE_DATA_SYNC` and `POST_NOTIFICATIONS` Android permissions
- Unit tests for QueueItem model and Strings constants

## 4.0.0 — Browser Overhaul

### Breaking Changes
- Removed Screencast tab entirely (replaced by in-browser video casting)
- Browser module completely rebuilt with `flutter_inappwebview`

### New Features
- **In-App Browser** rebuilt with full-featured WebView (JavaScript, DOM storage, caching)
- **Ad-Block Engine** — fetches EasyList, blocks ads and popups
- **Video Detection** — detects video streams (M3U8, MP4, MPD) via JS injection + network interception
- **Cast to TV** — cast detected videos to Chromecast and DLNA devices
- **Favourites** — full bookmarks manager with folders, drag-to-reorder, search, bulk operations
- **History** — date-grouped browsing history with search and swipe-to-delete
- **Incognito Mode** — separate WebView with no history/cookies persistence
- **New Tab Page** — premium home page with quick access, favourites, and recent history
- **Browser Settings** — search engine, ad-block, text size, dark mode, casting preferences
- **Multi-Tab Support** — tab manager with screenshots and smooth transitions
- **Cast Mini Bar** — persistent playback controls while casting

### Removed
- Screencast tab and all associated native code (MpegTsMuxer, ScreenCaptureService)
- Screencast-related Android permissions (RECORD_AUDIO, FOREGROUND_SERVICE_MEDIA_PROJECTION)
