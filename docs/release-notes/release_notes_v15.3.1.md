# Convert the Spire Reborn v15.3.1

## No freezes during torrents, steady volume, and track list export

### New

- **Export your songs as a track list.** Playlists has a **Track lists** menu: save all your songs, or your favourites, as "Artist - Title" lines (.txt) or a spreadsheet (.csv), and import that list on another device to get the music back.

### Changed

- Bulk Import moved from Home into that menu, and an import now starts its downloads straight away.

### Fixed

- **Torrents no longer freeze the app** when a file finishes or starts seeding.
- **Songs keep their volume** when you play them again on Windows, Mac and Linux.
- Full screen (F11) stays on when you open another page.
- **Every Convert format works**: text from PDFs, real WebP images, and songs with cover art to video.
- Share on Android sends the song itself, not a link.

### Build Notes

- Version 15.3.1+1303. The Microsoft Store package (MSIX) is built by the "Microsoft Store package" workflow or `scripts\make_store_upload.cmd`; see `docs/publishing/windows-store.md`. The Store's "What's new in this version" text for all 18 languages is in `docs/publishing/store-listing/`.
