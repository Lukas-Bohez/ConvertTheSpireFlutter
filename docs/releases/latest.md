# Release Notes - v13.2.0

## Download queue reliability and playlist Extras improvements

## Fixes

* **Fixed repeated download failures on lower-end hardware.** The download queue was being fully rewritten to disk on every progress update of the song currently downloading - including every previously-completed song. With a large download history this made each tick slower and slower until it produced timeout-flavored failures with no YouTube-side cause. The queue is now only persisted when a download's status actually changes, not on progress/speed/ETA ticks.
* **Fixed the burst-pause cooldown not being honored by every retry path.** A failing download could keep retrying every few seconds instead of actually backing off after a burst of reload-errors was detected. `downloadSingle()` now respects an in-progress burst-pause no matter how it's called (worker, resume button, or retry button).
* **Fixed a null-safety analyzer issue** in `playlist_screen.dart` (redundant null-aware operator on `settings?.downloadDir?.trim()`).

## New

* **Playlist Extras tab categorization.** The Extras tab now separates leftover incomplete-download files (`.temp.` infix), files in the wrong format for their folder, and files that just aren't in this playlist - each with a one-tap fix and a "resolve all" option for the whole category.

## Notes

* **Low-end hardware confirmation pending.** The queue-persistence fix is code-verified and analyze/test-clean, but live confirmation on the affected low-end machine is still pending. The `[_saveQueue] persisted N items in Xms` log line is the live signal to verify it there.

## Build Notes

* GitHub release tag: v13.2.0
* Release page: [v13.2.0](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.2.0)
* `flutter analyze` clean; all 79 tests pass; release workflow builds Windows, Linux, macOS, Android, and web artifacts.

