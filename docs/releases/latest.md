# Release Notes - v13.0.13

## Low-End CPU Stability Fixes

## Fixes

* **Library refresh crash fixed (metadata_god / flutter_rust_bridge mismatch).** metadata_god's bundled Rust library was built with frb codegen 2.11.1 while pub resolved runtime 2.12.0, so every library refresh / folder pick threw a ZONE ERROR. `flutter_rust_bridge` is now pinned to 2.11.1.
* **Deno provisioning now actually succeeds.** The provisioned-binary lookup couldn't find `deno.exe` after extraction and re-downloaded the whole zip on every attempt (causing yt-dlp "page needs to be reloaded" failures). The lookup now checks all naming variants before and after extraction, and every deno-runtime outcome is surfaced in the session log.
* **Burst-pause log spam fixed.** Downloads pausing due to rate-limiting logged one line per worker every 15 s (≈84 identical entries for a 7-minute pause); pause/resume is now logged once per pause window.
* **Add Magnet button sizing** in the torrents empty state is height-pinned by the unified button theme; it stays the emphasized primary action.

## Internal

* Line endings renormalized repo-wide per `.gitattributes` (no behavior change).

## Build Notes

* GitHub release tag: v13.0.13
* Release page: [v13.0.13](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.13)
* flutter analyze passes cleanly; Windows release and Play AAB (flavor `play`, `com.torrentspire.ai`, v13.0.13+1276) built locally and verified.
