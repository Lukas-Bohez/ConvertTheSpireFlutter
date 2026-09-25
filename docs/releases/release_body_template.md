<p align="center">
  <a href="https://youtu.be/66Rx8PDY_r0"><img src="https://img.youtube.com/vi/66Rx8PDY_r0/maxresdefault.jpg" width="70%" alt="Watch the demo video on YouTube"></a>
  <br><b>▶ <a href="https://youtu.be/66Rx8PDY_r0">Watch the demo video</a></b>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/{{TAG}}/screenshots/media-player-audio-controls.webp" width="32%" alt="media player audio controls">
  <img src="https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/{{TAG}}/screenshots/search-and-download-songs.webp" width="32%" alt="search and download songs">
  <img src="https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/{{TAG}}/screenshots/convert-files-between-supported-media-types.webp" width="32%" alt="convert files between supported media types">
  <img src="https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/{{TAG}}/screenshots/match-playlists-to-folders.webp" width="32%" alt="match playlists to folders">
  <img src="https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/{{TAG}}/screenshots/watch-playlists-auto-install.webp" width="32%" alt="watch playlists auto install">
  <img src="https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/{{TAG}}/screenshots/custom-file-explorer-tv.webp" width="32%" alt="custom file explorer tv">
</p>

**Nothing to set up.** One line on Windows, one file everywhere else, and it runs: no admin rights, no Python, no account.

{{NOTES}}

## Install in a minute

**Windows:** press <kbd>Win</kbd>+<kbd>R</kbd>, paste this line and press Enter. It installs this release for your account, checks it against `SHA256SUMS.txt` and starts it, with no "Windows protected your PC" screen. Run it again to update.

```powershell
powershell -c "irm https://raw.githubusercontent.com/Lukas-Bohez/ConvertTheSpireFlutter/main/install.ps1 | iex"
```

Or pick your file under **Assets** just below.

| | Download | Then |
|---|---|---|
| **Windows** | `ConvertTheSpireReborn-windows-x64.zip` | Extract it and double-click `convert_the_spire_reborn.exe`. That's it. |
| **Android phone or TV** | `ConvertTheSpireReborn.apk` | Open the file and allow the install when Android asks. |
| **macOS** | `ConvertTheSpireReborn-macOS.zip` | Unzip and open the app. If macOS says it cannot check the developer, right-click it and choose **Open**. |
| **Google Play** | [The Play Store version](https://play.google.com/store/apps/details?id=com.torrentspire.ai) | Everything except the YouTube download features, which Play policy does not allow. |

- **No installer and no admin rights on Windows.** On first start the app fetches yt-dlp and FFmpeg by itself and keeps yt-dlp up to date, so sites that change keep working, and it adds itself to "Open with" for your songs, videos, torrents and magnet links. To remove it, delete the folder.
- **Nothing extra on Android.** FFmpeg is built into the APK. No root, no Termux, no Google account. The same APK runs on Android TV.
- **On a Mac,** yt-dlp installs itself too; converting to MP3 and M4A needs FFmpeg, which you add once with `brew install ffmpeg`.
- **Updating?** On Android, open the new APK and it installs over the old one. On Windows, run the line above again; with the zip, extract into a new folder rather than over the old one.
- **Windows shows "Windows protected your PC"?** That is SmartScreen checking the zip your browser downloaded, which is not signed with a paid certificate. The one-line install above does not show it. With the zip, choose **More info**, then **Run anyway**.

---

**More screenshots & info:** [README](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter#readme) · [Full changelog](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/blob/{{TAG}}/CHANGELOG.md) · [Report an issue](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/issues)
