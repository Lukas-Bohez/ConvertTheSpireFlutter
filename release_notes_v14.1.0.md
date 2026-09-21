# Convert the Spire Reborn v14.1.0

## Playlists past 100 videos on Android, and the app in 18 languages

### Fixed

- **Playlists stopped at 100 videos on Android.** This is the big one. Android has no yt-dlp fallback, so every playlist is enumerated by the in-app page parser, which walks YouTube page by page using a "continuation token". YouTube emits that token in several different shapes and switches between them without notice — the parser only recognised one of them, so on any playlist whose page used a different shape pagination stopped dead after the first page, at exactly 100 entries. All known token shapes are now recognised, so an 800-item playlist enumerates fully on a phone.
- **Continuation pages that used the classic item format parsed to zero videos.** YouTube mixes two item layouts (`lockupViewModel` and `playlistVideoRenderer`) and can return a different one on page 2 than on page 1. Only the first was parsed, so some playlists paged forever while adding nothing. Both layouts are now read, and pages are merged by video id so nothing is counted twice.
- **Pagination could stall or spin.** Each continuation token is now spent once, and entries are de-duplicated by video id, so a repeated token can no longer loop forever re-fetching the same page.

### Added

- **The app now speaks 18 languages.** It follows your device language automatically, with English as the fallback: Arabic, Dutch, English, French, German, Hindi, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Russian, Simplified Chinese, Spanish, Turkish, Ukrainian and Vietnamese. Right-to-left layout works for Arabic. This first pass covers the navigation and the common actions and states; the longer screens are still English and will be translated as native speakers review them. Contributions are very welcome — the files are plain `.arb` under `lib/l10n/`.

### Improved

- The playlist parser is covered by offline tests for every token shape and both item layouts, so a future YouTube change fails a test instead of silently capping playlists again.
- Every translation file is checked in CI against the English template — a missing or blank translation fails the build rather than showing a blank label.

### Build Notes

- Android Play AAB built with `--flavor play` (version 14.1.0+1290).
- `flutter analyze` clean; 150 tests pass (was 86).
