# Convert the Spire Reborn v15.2.0

## Double-click install on Windows, smoother torrents

### New

- **Double-click install on Windows.** `ConvertTheSpireReborn-Setup.exe` installs the app for your account, with a Start menu entry and an uninstaller. No admin rights.
- **Updates itself on Windows.** **Update now** in the update banner downloads the new version, checks it and restarts the app.
- **A .dmg for Mac**, to drag the app into Applications.

### Fixed

- **Torrents no longer freeze the app** or fill up memory on slower PCs.
- The update banner shows the release notes as plain text.

### Build Notes

- Version 15.2.0+1301.
- Windows installer: Inno Setup script `windows/installer/ConvertTheSpireReborn.iss`, per-user into `%LOCALAPPDATA%\Programs\ConvertTheSpireReborn`. The release workflow builds it, installs it silently, checks the files and Start menu entry, and uninstalls it again before publishing.
- In-app update: `WindowsUpdater` downloads Setup.exe, checks it against `SHA256SUMS.txt` and runs it (silently for the installed copy). Setup closes the app, replaces it and starts it again.
- macOS: the release also carries `ConvertTheSpireReborn-macOS.dmg`.
