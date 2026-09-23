# Release Notes - v14.4.0

## Mobile fixes

### Fixed

* **Downloads keep going when the phone is locked.** Android was freezing the app shortly after the screen went off, so downloads and torrents stalled until you opened it again. While anything is downloading, the app now keeps itself running with a notification that shows progress, and its Stop button pauses everything.
* **Watch Together no longer opens to a grey screen.** The room sheet could not reach the player, which showed up as a blank grey box on every platform.
* **Searching from the browser searches the web.** The address bar now uses your chosen search engine, the same as the new tab page, and links that used to throw you into the YouTube app open in the browser instead. Anything that really needs another app asks first.
* **Refresh no longer spins forever on Windows.** It finishes within a few seconds; checking your watched playlists now happens in the background.
* **Your support colour now reaches the whole app,** including the player bar, sliders, progress indicators and the incognito toolbar.

### Improved

* **A less crowded player on phones.** Watch Together and the queue stay in the header, and open folder, organize, fix metadata and volume leveling move into a menu with proper labels. The video takes a sensible share of the screen instead of a fixed height, and the track title gets more room.
* **Watch Together without the file.** A guest that does not have the host's file, like a TV, now streams it from the host over your network, seeking included.
* **Choose the app language in Settings.** Any of the 18 translations, or automatic.
* **Report a bug** from Settings opens a GitHub issue with your app version, platform and recent log already filled in. You see all of it before anything is sent.
* **What's new** appears once after each update. The intro tour now only runs on a first install instead of after every update.
* If a screen ever fails to load, you get a readable message with Copy details and Report buttons instead of an empty grey box.
* A smaller download: several libraries the app no longer used have been removed.

### Build Notes

* Android Play AAB built with `--flavor play` (version 14.4.0+1296).
* `flutter analyze` clean; all tests pass.
* GitHub release tag: v14.4.0
* Release page: [v14.4.0](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.4.0)
