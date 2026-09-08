# Release Notes - v13.0.17

## Defensive pinned-header clipping + review pass

## Fixes

* **Home screen search header could paint over the scrollable body.** The search bar sits in a fixed-height pinned `SliverPersistentHeader` (`_SearchHeaderDelegate`) whose `build` returned the child with no clip — the same latent overflow class already fixed in the player's pinned header (v13.0.15). Wrapped the delegate's child in a `ClipRect` so any content exceeding the fixed extent is clipped instead of drawn over the body below.

## Review (no functional change)

* Verified the v13.0.16 metadata_god → pure-Dart `audio_metadata_reader` Windows fix is sound: the duck-typed `dynamic` metadata consumption in `resolveArtist`, `_extractGenre` and `_extractReplayGainTrackGain` is safe (every access is try/catch-wrapped with `.toString()`; the replay-gain extractor falls through gracefully on non-matching types), and both `audio_metadata_reader` and `metadata_god` are present in `pubspec.yaml`.
* Confirmed the v13.0.15 player fixes (single-row scrollable genre chips, player pinned-header `ClipRect`, corrected header heights, unified-button `maximumSize` cap removal) and the v13.0.14 empty-state button consistency are all intact after the v13.0.16 changes.
* `flutter analyze` clean; all 30 tests pass.

## Build Notes

* GitHub release tag: v13.0.17
* Release page: [v13.0.17](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.17)
* flutter analyze clean; all 30 tests pass; Windows release and Play AAB (flavor `play`, `com.torrentspire.ai`, v13.0.17+1280) built locally and verified.

