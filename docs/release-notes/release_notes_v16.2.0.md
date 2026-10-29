# Convert the Spire Reborn v16.2.0

## Linux is back, and the Store version's desktop shortcut works

### New

- **Linux is back.** An AppImage, the whole app in one file with nothing else to install, and a tar.gz to extract and run. They run on 64-bit PCs with Ubuntu 22.04 or later, Linux Mint 21 or later, Debian 12, Fedora and other distributions of that age. The player's engine comes inside, and yt-dlp, FFmpeg and Deno download themselves on the first start, as on Windows. The app adds itself to the app menu (and the desktop), opens songs, videos, torrents and magnet links you open with it, brings its window forward when started again, and the AppImage updates itself. The built-in browser is the one thing Linux does not have: links open in your own browser.

### Fixed

- **The Microsoft Store version's desktop shortcut works.** It pointed at the app's exe inside the protected WindowsApps folder, which Windows does not let anyone start ("you do not have permission"), and which moves with every update. The shortcut now opens the app through Windows, like one dragged from the Start menu, and the app puts an old shortcut right on its first start. To make one yourself, drag the app from the Start menu to the desktop.
- **A desktop shortcut you delete stays deleted.** The app made it again on every start.

### Build Notes

- Issue #47. The Store build finds its app id with `GetCurrentApplicationUserModelId` and makes the shortcut to `shell:AppsFolder\<id>`; any shortcut of the app's name that points into WindowsApps, or at a file that is gone, is replaced (`ShortcutService`, with a Windows test that runs the script). Nothing changes the WindowsApps folder.
- Linux: the release workflow and CI build on Ubuntu 22.04 (`scripts/linux_build_deps.sh`), package with `scripts/package_linux.sh` (libmpv and the libraries it needs, minus the AppImage exclude list and the GTK stack; static AppImage runtime, so no libfuse2) and start both packages on clean Ubuntu 22.04 and 24.04 with `LD_BIND_NOW` (`scripts/smoke_test_linux.sh`).
- Linux fixes: `linux/CMakeLists.txt` no longer bundles the build machine's libstdc++ and a lone libmpv, no longer keeps `/usr/local` as install prefix after a failed first configure, and leaves FFmpegKit's unused libraries out. The runner is a unique GApplication that passes its command line to the running copy, with the `convert_the_spire/open` channel. The runner sets `GDK_BACKEND=x11,wayland` unless the user set it (X11 first, XWayland on Wayland desktops): on Wayland libmpv probed VA-API through libva-wayland while making the video output and crashed the app, and window_manager can only place and centre a window on X11.
- FFmpeg downloads itself on Linux (BtbN's shared build, unpacked with tar); yt-dlp, Deno and FFmpeg take the aarch64 builds on ARM Linux; Deno is unzipped in Dart (no `unzip` needed). The free-space check before a download split `df` output on the letter "s" instead of whitespace; it uses `df -P` and `\s+` now.
- Version 16.2.0+1307.
