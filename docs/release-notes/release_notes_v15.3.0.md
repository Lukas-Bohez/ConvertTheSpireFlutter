# Convert the Spire Reborn v15.3.0

## Seeding that works, a faster start, and a Microsoft Store version

### New

- **A Microsoft Store version is on its way**, with FFmpeg and yt-dlp built in and updates through the Store.
- Home shows which version you have.

### Fixed

- **Seeding works and keeps going**, about 20 times faster, and each torrent remembers how much it has seeded. Torrents no longer freeze the app or flood the log.
- **The app starts at once** and uses no CPU while it sits idle.
- Songs opened from outside the app play like the ones in your library.
- Smaller fixes: decimal commas are read right, the welcome pages fit a laptop screen, and Enter no longer clicks something you cannot see.

### Build Notes

- Version 15.3.0+1302. The Microsoft Store package (MSIX) is built by the "Microsoft Store package" workflow or `scripts\make_store_upload.cmd`; see `docs/publishing/windows-store.md`.
