# Convert the Spire Reborn v16.0.1

## Subtitles for every film, and a player for files you open

### New

- **Subtitles inside the video.** MKV and MP4 files with subtitles built in show them by themselves, English first, and the Subtitles sheet lists every track to choose from. On Windows, macOS and Linux.
- **A file you open from outside your library plays like one in it**: its subtitles or lyrics, looping parts, speed, the sleep timer, and long films open where you left off. A menu next to it has the rest.

### Changed

- **Calmer controls.** The play button is the biggest one; shuffle and repeat show they are on with their colour and a dot, not a big circle. With a video, the library's tools sit above it, not between the video and its controls.
- The new trailer replaces the old demo video.

### Fixed

- **Subtitles saved as UTF-16**, as subtitles made on Windows often are, showed nothing. They load now.
- **Covers no longer go grey** when your library loads again, as it does when a download lands in its folder, and they load without stalling the app.
- The play button showed play while a song you opened was playing.
- The large view showed a library song's title for a film opened from outside the library.

### Build Notes

- Version 16.0.1+1305. The Microsoft Store package (MSIX) is built by the "Microsoft Store package" workflow or `scripts\make_store_upload.cmd`; see `docs/publishing/windows-store.md`. The Store listings for all 18 languages are in `docs/publishing/store-listing/`, and the Google Play listing in `store/google-play/listing/`.
