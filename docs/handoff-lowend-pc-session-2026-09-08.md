# Handoff — low-end PC session (2026-09-08)

Session ran live on the affected low-end Windows PC (`C:\Users\lukas\convert\ConvertTheSpireFlutter`,
branch `main`). Work stopped early per user request; continuing on the main PC.
This file is the complete state handoff.

## Machine facts (this PC)

- CPU: **Intel Core i3-3220 (Ivy Bridge, 2012) — no BMI2 / AVX2**. This is the
  machine behind the old `flutter_inappwebview` BMI2 crash.
- **No Flutter SDK, no Dart, no Visual Studio C++ toolchain, no pub cache** on
  this PC (verified: no `.dart_tool`, no `windows/flutter/ephemeral`,
  `vswhere` reports no VC tools). All builds so far came from GitHub CI
  (`release.yml`, manual `workflow_dispatch`); `ci.yml` only runs
  pub get + analyze + tests on ubuntu (Flutter pinned 3.41.2 there).
- Installed app the user runs: `C:\Users\lukas\Documents\convert\ConvertTheSpireReborn-windows-x64\convert_the_spire_reborn.exe`
  = **v13.0.12+1275 = exactly the pre-fix code** (useful as the "before" build
  for live repros).
- Session logs: `C:\Users\lukas\Documents\session_log_*.log`;
  errors: `C:\Users\lukas\Documents\startup_errors.log`.

## Root causes found this session (all live-confirmed unless noted)

### 1. metadata_god / flutter_rust_bridge version skew — the `zone_error` storm (FIXED)
`startup_errors.log` shows dozens of `ZONE ERROR: Bad state: metadata_god's
codegen version (2.11.1) should be the same as runtime version (2.12.0)` from
`PlayerState._enrichArtistsInBackground` → every library refresh / folder pick
threw. The repeated `=== flush: zone_error ===` blocks in session_log files are
these, not mystery crashes. metadata_god 1.1.0 is the latest release (12 mo old)
and its pubspec declares `flutter_rust_bridge: ^2.11.1`, so the shipped Rust lib
is codegen 2.11.1 while pub resolved frb 2.12.0.
**Fix applied:** `pubspec.yaml` pins `flutter_rust_bridge: 2.11.1` (direct dep,
comment included); `pubspec.lock` updated to match (sha256 verified from
pub.dev API; frb 2.11.1 needs Dart >=3.4.0 — fine for CI's Flutter 3.41.2).

### 2. Deno provisioning could never succeed — the "page needs to be reloaded" 2/4 failures (FIXED, needs live confirm)
`DenoRuntimeService.resolveOrDownload()` computed `destBase` as
`<appSupport>\deno\deno-x86_64-pc-windows-msvc` (no `.exe`) but the official
Windows zip extracts **`deno.exe`**. So download+extract succeeded, the lookup
failed, `_cachedPath` was never set, and the next attempt re-downloaded the
whole zip — while `resolveOrDownload()` kept returning null and yt-dlp never
got `--js-runtimes deno:...` → "page needs to be reloaded" on nsig-protected
videos. Live evidence: a working `deno.exe` (v2.9.6) sits at
`C:\Users\lukas\AppData\Roaming\Oroka Conner\Convert the Spire Reborn\deno\deno.exe`
— **verified running on this CPU** (`deno --version` exit 0; no BMI2 problem
for Deno on i3-3220).
**Fix applied:** `_findProvisionedBinary()` now checks `deno.exe` / `deno` /
`$destBase.exe` / `destBase` before and after extraction (so the existing
binary is picked up with no download), and every failure mode + success is
surfaced via `SessionLogService.markOnce` (keys `deno-ok`,
`deno-not_on_path`, `deno-download_failed_http_*`, `deno-verify_failed_*`,
`deno-binary_not_found`, …) so `session_log_*.log` finally shows what the code
always promised. debugPrints kept.

### 3. Burst-pause log spam (FIXED, needs live confirm)
`downloadAll()`'s workers each logged "Pausing downloads — YouTube may be
rate-limiting…" every 15 s for the whole pause: a 7-minute pause with 3 workers
≈ 84 identical entries (matches the 3-bursts-in-2-minutes screenshot).
**Fix applied:** log once per pause window, deduped on the `_burstPauseUntil`
timestamp (`_loggedBurstPauseUntil`), plus a single
"Burst pause over — resuming downloads" line when it ends. `LogService` was
already capped (500 entries) — no cap work needed.
**Honest caveat:** the Application Logs tab uses `ValueListenableBuilder` +
`ListView.builder`, so per-append cost is bounded; whether the spam alone
caused the no-dump hang is still unconfirmed (Priority 0 live measurement
below still worth doing).
### 4. Torrent buttons (partially fixed, one decision open)
- `Force refresh` (torrent_detail_screen) was `FilledButton.tonalIcon` next to
  `OutlinedButton.icon` siblings → changed to `OutlinedButton.icon`.
- `_unifiedButtonStyle` (app.dart) got `maximumSize: (double.infinity, 40)` so
  height pins to exactly 40 (`.icon()` padding could previously render lower).
- **`Add Magnet` (torrents_screen empty state) is UNDECIDED on purpose** — two
  previous attempts shipped blind guesses. Render both and pick on screen:
  (A) `OutlinedButton.icon` matching its three siblings exactly, vs
  (B) keep `FilledButton.icon` as the empty-state's primary action with the
  new `maximumSize`. One-line change either way at `torrents_screen.dart`
  `_buildEmptyState()` (~line 954).

### 5. Android playlist 0/800 — root cause confirmed, no code this round
`playlist_service.dart` documents it: yt-dlp (desktop-only) is primary because
youtube_explode_dart times out on >100-video playlists; on Android everything
goes through youtube_explode_dart. **Option 1 from the plan is exhausted**:
pub.dev's latest youtube_explode_dart IS 3.1.0 (already locked); the >100 fix
landed back in 2.5.0 and 3.1.0 "fix[ed] playlist apis" already. Remaining
options: (2) YouTube Data API v3 `playlistItems.list` fallback for Android
listing (needs an API key + quota mgmt), (3) yt-dlp on Android (big lift).
Needs an Android device/emulator; separate track.

## Live verification protocol for the next session

1. Get a runnable exe: push to `main`, then dispatch `release.yml`
   (Actions → release → Run workflow), download the Windows zip, replace the
   exe in `Documents\convert\` (or run standalone). The installed v13.0.12
   exe doubles as the pre-fix build for A/B.
2. P0: queue the reload-error-prone videos again; watch Task Manager
   (CPU/memory) during the pause window with the Application Logs tab open.
   Expected after fix: exactly 2-3 lines per burst window ("Burst of
   reload-errors detected — pausing queue for 7 minutes", one "Pausing
   downloads … resuming at HH:MM", later "Burst pause over — resuming
   downloads") instead of ~84.
3. P1: repeat a previously-failing download, close the app normally (session
   log flushes on exit), then read the newest `session_log_*.log`: expect
   `deno-runtime: using provisioned Deno at …` and no "page needs to be
   reloaded" failures. If instead `deno-verify_failed_*` appears → Deno binary
   won't run on this CPU → treat like the BMI2 webview case (pin an older Deno
   build or ship a lower-baseline binary; decide then).
4. P2: look at the Torrents empty state + torrent detail buttons on screen;
   make the Add Magnet call (see above).

## Repo state / follow-ups

- Committed here: `app_controller.dart`, `deno_runtime_service.dart`,
  `app.dart`, `torrent_detail_screen.dart`, `pubspec.yaml`, `pubspec.lock`,
  this note. Pushed to `origin/main` (CI quality job runs analyze/tests on
  Flutter 3.41.2 — watch it).
- Left dirty on purpose (line-ending-only phantoms caused by the new
  `.gitattributes` renormalization; `git diff --ignore-cr-at-eol` is empty):
  `multi_source_search_service.dart`, `youtube_service.dart`,
  `browser_shell.dart`, `quick_download_card.dart`. Recommended follow-up:
  `git add --renormalize . && git commit` as a standalone EOL commit.
- Validation done locally: none (no SDK on this PC). Code reviewed by
  reading; frb pin verified against pub.dev metadata. CI is the first real
  analyze/test gate.
- `SessionLogService` only flushes on exit/error — deno marks appear after
  app close. A periodic flush or "copy diagnostics" button would make field
  debugging easier (follow-up idea, not implemented).
- The 21 scattered `*Button.styleFrom(...)` calls across 8 files remain a
  known dedup/theme debt (explicitly deferred).
- A partial Flutter SDK download on this PC was started and then cleaned up
  (`C:\src` removed). No toolchain was installed.

