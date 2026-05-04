# Crash Diagnosis

Use the logs in the project root to diagnose build or runtime issues.

## What to Check

* `flutter_verbose_log.txt`
* `build_windows_log.txt`
* `manifest_merge_log.txt`
* `build_play_verbose.log`

## Rule of Thumb

If the issue is Android-specific, inspect the merged manifest in the Gradle output and the Play flavor manifest first.
