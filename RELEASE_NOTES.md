# Release Notes — v5.2.0

## What's New
- Windows browser now falls back safely when embedded WebView is unavailable.
- Play Store builds disable YouTube conversion features while APK builds keep them enabled.
- Android Vault AI tabs are hidden on Android devices.
- Release workflow now publishes both Android APK and AAB artifacts.
- Fixed Android share button for downloaded files
- Fixed "Open Folder" button now showing on Android
- Browser fallback UI for PCs without WebView2 runtime
- Linux AppImage for better compatibility on older distros
- Battery monitoring now reacts instantly (stream-based)
- CSV import uses safe parser (no more freeze on large files)

## Bug Fixes
- Worker pool no longer downloads same item twice
- Notifications now appear on Android 13+
- Converted files now visible in Files app on Android

See [CHANGELOG.md](CHANGELOG.md) for fuller details.
