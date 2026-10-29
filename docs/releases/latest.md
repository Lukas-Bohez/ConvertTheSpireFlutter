# Release Notes - v16.2.0

## Linux is back, and the Store version's desktop shortcut works

### New

- **Linux is back.** An AppImage, the whole app in one file with nothing else to install, and a tar.gz to extract and run. They run on 64-bit PCs with Ubuntu 22.04 or later, Linux Mint 21 or later, Debian 12, Fedora and other distributions of that age. The player's engine comes inside, and yt-dlp, FFmpeg and Deno download themselves on the first start, as on Windows. The app adds itself to the app menu (and the desktop), opens songs, videos, torrents and magnet links you open with it, brings its window forward when started again, and the AppImage updates itself. The built-in browser is the one thing Linux does not have: links open in your own browser.

### Fixed

- **The Microsoft Store version's desktop shortcut works.** It pointed at the app's exe inside the protected WindowsApps folder, which Windows does not let anyone start ("you do not have permission"), and which moves with every update. The shortcut now opens the app through Windows, like one dragged from the Start menu, and the app puts an old shortcut right on its first start. To make one yourself, drag the app from the Start menu to the desktop.
- **A desktop shortcut you delete stays deleted.** The app made it again on every start.
