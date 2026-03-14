# Changelog

## 5.2.0 — Bug Fix & Stability Release

### Fixed
- Android Share button now works with content:// URIs
- "Open Folder" button visible on Android queue items
- Browser shows WebView2 download link on older Windows PCs
- Linux AppImage for better compatibility on older distros

### Notes
- Bumped version to 5.2.0; see RELEASE_NOTES.md for highlights.

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
