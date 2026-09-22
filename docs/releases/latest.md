# Release Notes - v14.1.1

## Full playlists on Android — all 855 of them, not 200

### Fixed

* **Large playlists stopped at 200 entries on Android.** v14.1.0 fixed the first half of this (the parser only knew one of YouTube's continuation-token shapes, which capped it at 100). Testing an 863-entry playlist showed the real remaining cause: YouTube's plain WEB API simply **stops issuing continuation tokens after two pages**. Page 2 comes back with 100 videos and no continuation marker anywhere in the response, so there is nothing left to follow — no parser change could have gone further.

  The app now falls back to the YouTube Music (`WEB_REMIX`) client, which pages through the same playlist to the end, and merges the results by video id. Measured on the 863-entry playlist used to reproduce this: **200 entries before, 855 after.** The handful still missing are videos that are private, deleted or region-locked, which no client can enumerate.

### Improved

* The playlist parser now reads all three item layouts YouTube serves (`lockupViewModel`, `playlistVideoRenderer` and the Music client's `musicResponsiveListItemRenderer`), so a layout switch on any page no longer silently yields zero videos.
* Artist/channel attribution on Music-client entries is read from the artist column specifically, so an album or menu id can't be mistaken for the channel.
* Offline tests cover every token shape and all three item layouts.

### Build Notes

* Android Play AAB built with `--flavor play` (version 14.1.1+1291).
* `flutter analyze` clean; 160 tests pass.
* GitHub release tag: v14.1.1
* Release page: [v14.1.1](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.1.1)
