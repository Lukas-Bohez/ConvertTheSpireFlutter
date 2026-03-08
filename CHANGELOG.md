# Changelog

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
