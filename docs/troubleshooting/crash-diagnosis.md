# Crash Diagnosis

Use the archived logs in `results/root-archive/` to diagnose build or runtime issues.

## What to Check

* The files archived under `results/root-archive/`
* Any fresh logs written during a local build

## Rule of Thumb

If the issue is Android-specific, inspect the merged manifest in the Gradle output and the Play flavor manifest first.
