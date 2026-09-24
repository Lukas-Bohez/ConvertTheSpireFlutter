# Release Notes - v14.4.1

## Startup fix and a smaller Windows download

### Fixed

* **The app opens again.** 14.4.0 stayed on its loading spinner and never got any further, on every platform. Nothing you had was touched: your library, downloads and settings are all there once it opens.
* **Windows Defender no longer flags the Windows download** (issue #12). The Windows version carried about a hundred conversion libraries that only the Android and iOS versions use, and Defender flagged one of them, avdevice. They are gone from Windows, which also halves the download, from about 86 MB to about 41 MB. Converting on Windows works as before. When you update, extract into a new folder rather than over the old one, so the flagged file does not stay behind.
* **Closing the app on Windows no longer crashes it** on the way out.

### Improved

* **What's new shows what you missed.** If you skipped a release, as nearly everyone did with 14.4.0, its notes now follow this one's.

### Also new since 14.3.1: everything from 14.4.0

14.4.0 did not get past its loading screen, so for most people these arrive with this release. They are the same as in [14.4.0's own notes](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.4.0).

#### New

* **Browser extensions on Windows.** Install Chrome extensions, and add-ons from addons.mozilla.org that also support Chromium, from Extensions in the browser menu or in Browser Settings. Search the add-ons catalog inside the app, see what an extension will be able to do before anything installs, switch extensions on and off, and open their popups and options, update or remove them. Downloads from addons.mozilla.org are checked against the checksum it publishes. Tested with Dark Reader and uBlock Origin Lite. Windows only for now.

#### Fixed

* **Downloads keep going when the phone is locked.** Android was freezing the app shortly after the screen went off, so downloads and torrents stalled until you opened it again. While anything is downloading, the app now keeps itself running with a notification that shows progress, and its Stop button pauses everything.
* **Watch Together no longer opens to a grey screen.** The room sheet could not reach the player, which showed up as a blank grey box on every platform.
* **Searching from the browser searches the web.** The address bar now uses your chosen search engine, the same as the new tab page, and links that used to throw you into the YouTube app open in the browser instead. Anything that really needs another app asks first.
* **Refresh no longer spins forever on Windows.** It finishes within a few seconds; checking your watched playlists now happens in the background.
* **Your support colour now reaches the whole app,** including the player bar, sliders, progress indicators and the incognito toolbar.
* **Userscripts now run in the Windows browser.** Since they arrived in 14.3.0 they installed and showed up in the list on Windows, but never actually ran on the page.
* **The browser toolbar fits larger text.** With a bigger system text size the address bar was cut off on every screen size; it now grows to fit, and long menu entries wrap instead of spilling over.

#### Improved

* **A less crowded player on phones.** Watch Together and the queue stay in the header, and open folder, organize, fix metadata and volume leveling move into a menu with proper labels. The video takes a sensible share of the screen instead of a fixed height, and the track title gets more room.
* **Watch Together without the file.** A guest that does not have the host's file, like a TV, now streams it from the host over your network, seeking included.
* **Choose the app language in Settings.** Any of the 18 translations, or automatic.
* **Report a bug** from Settings opens a GitHub issue with your app version, platform and recent log already filled in. You see all of it before anything is sent.
* **What's new** appears once after each update. The intro tour now only runs on a first install instead of after every update.
* If a screen ever fails to load, you get a readable message with Copy details and Report buttons instead of an empty grey box.
* A smaller download: several libraries the app no longer used have been removed.

### Build Notes

* Android Play AAB built with `--flavor play` (version 14.4.1+1297).
* The Windows zip no longer contains FFmpegKit's DLLs; the release workflow now fails if they reappear.
* `flutter analyze` clean; all tests pass, including a new test that starts the real app and requires it to get past the loading screen.
* GitHub release tag: v14.4.1
* Release page: [v14.4.1](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.4.1)
