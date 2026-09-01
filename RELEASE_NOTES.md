# Release Notes — v13.0.0

## What's New
- Linux and macOS now download the correct self-contained yt-dlp binary instead of a variant that requires a system Python 3.11+ interpreter.
- Target API level raised to 36 (Android 16) for Play Store compliance.
- Local build script fixed: version number is now always read from `pubspec.yaml`, and the GitHub build's ad-free/unlocked-colours flag is now set correctly.

## Bug Fixes
- Fixed "can't download playlists" and similar failures reported by Linux Mint users — root cause was the wrong yt-dlp asset being downloaded for Linux.

See [CHANGELOG.md](CHANGELOG.md) for fuller details.
