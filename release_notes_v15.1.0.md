# Convert the Spire Reborn v15.1.0

## Safe torrent deletes, magnets that fetch, one-line Windows install

### Fixed

- **Deleting a torrent's files no longer empties your download folder.** "Remove torrent" with "Also delete downloaded files" deleted the whole folder the torrent was saved in, which for most torrents was the download folder itself, so other downloads and your own files went with it. It now deletes only the torrent's own files, one by one, and only the folders that end up empty. When it cannot tell which files are the torrent's, it deletes nothing and says so.
- **Magnet links get their file list again.** Magnets waited at "No metadata" until the app gave up, because qBittorrent, Deluge and other clients built on libtorrent dropped the connection. They now answer in under a second.
- **The Android icon looks right.** On phones and Android TV the icon shows the whole logo on white and fills its square, and the GitHub version's icon is no longer cut off at the edges.

### New

- **One-line Windows install.** Paste one line into Win+R and the app installs itself: it downloads the latest release, checks it, adds a Start menu entry and starts, without the "Windows protected your PC" screen. Run it again to update. The zip is still there if you prefer it.
- **Share a torrent as a .torrent file.** Each torrent's menu has Share .torrent file on a phone and Save .torrent file on a computer, next to Copy magnet link.

### Improved

- **Torrents is one screen.** Its settings are in Settings under Torrents, and its guide is part of the app's Guide. The AI copilot and chat, and the second browser inside Torrents, are gone.
- **The Search page is gone.** Quick Download on Home and the Playlist Manager do everything it did. Multi-Search stays.
- The Play Store version no longer calls its pages "Vault" and "Vault Guide".

### Build Notes

- Version 15.1.0+1300. Build the Play AAB with `--flavor play` as usual, and check it with `scripts/verify_play_aab.py`.
- `flutter analyze` is clean and all tests pass.
- Torrents: `dtorrent_task_v2` 0.4.9 is vendored under `third_party/` with two fixes (the BEP 10 handshake is sent before `ut_metadata`, and a disconnected peer leaves the metadata sources), covered by `test/services/torrent_metadata_exchange_test.dart`. Deletes go through `TorrentContentDeleter`.
- CI builds the Play flavor and runs `scripts/play_tv_checks.py` on its Android TV banner and icon.
