# Convert the Spire Reborn v14.1.2

## Full playlists on Android, and a Play Data Safety fix

### Fixed

- **Large playlists stopped at 200 entries on Android.** v14.1.0 fixed the first half of this (the parser only knew one of YouTube's continuation-token shapes, which capped it at 100). Testing an 863-entry playlist showed the real remaining cause: YouTube's plain WEB API **stops issuing continuation tokens after two pages**. Page 2 comes back with 100 videos and no continuation marker anywhere in the response, so there was nothing left to follow — no parser change could have gone further.

  The app now falls back to the YouTube Music (`WEB_REMIX`) client, which pages through the same playlist to the end, and merges the results by video id. Measured on the 863-entry playlist used to reproduce this: **200 entries before, 855 after.** The handful still missing are private, deleted or region-locked videos, which no client can enumerate.

- **The ad-free GitHub build no longer requests the advertising-ID permission.** The Google Mobile Ads library merges `AD_ID` and `ACCESS_ADSERVICES_AD_ID` into every build from its own manifest, even though ads are Play-only and never initialise here. Both are now explicitly stripped from the GitHub flavor, verified against the merged manifest.

- **In-app privacy text is now accurate per build.** The Play build previously showed "No advertising or analytics" under a heading literally called "Data Safety", while serving AdMob. It now states plainly that ads use the device advertising ID. The GitHub build keeps the stronger claim, because there it is true.

### Improved

- The playlist parser reads all three item layouts YouTube serves (`lockupViewModel`, `playlistVideoRenderer` and the Music client's `musicResponsiveListItemRenderer`), so a layout switch on any page no longer silently yields zero videos.
- `docs/publishing/play-data-safety.md` records exactly what each SDK collects and the precise Play Console answers, guarded by tests so the declaration cannot drift out of sync with the code again.

### Build Notes

- Android Play AAB built with `--flavor play` (version 14.1.2+1292).
- `flutter analyze` clean; 163 tests pass.
