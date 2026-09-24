# Manual Actions Checklist

This file collects the few steps that still need human review after automated work is done.

## Before Release

* Review `git diff`.
* Confirm the Play bundle and release notes match the current version: `python scripts/verify_play_aab.py <aab>` checks the bundle.
* Verify the GitHub release page after publishing.

## Useful References

* [How a release goes out](../releases/how-to-release.md)
* [Play AAB build guide](../build/play-store-aab.md)
* [Latest release notes](../releases/latest.md)
