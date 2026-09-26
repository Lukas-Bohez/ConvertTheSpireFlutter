# Privacy policy

Convert the Spire Reborn has no accounts, no analytics and no tracking. Your settings, library and downloads stay on your device.

## What the app connects to by itself

The GitHub builds (Windows, macOS, Android APK) connect to other systems on their own only for this:

- **Update check:** when the app starts, it asks GitHub (`api.github.com`) for the latest release. You can turn this off in Settings. On Windows, **Update now** downloads the new installer from GitHub only when you press it.
- **yt-dlp:** on first start the app downloads yt-dlp from its official GitHub releases, and keeps it up to date.
- **FFmpeg (Windows):** when it is missing, the app downloads FFmpeg from gyan.dev.

These requests send nothing about you beyond what any download sends (your IP address and the app's request). GitHub's [privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement) applies to the GitHub requests.

## What happens only when you ask for it

- **Downloads** go to the sites you choose (for example YouTube), through yt-dlp.
- **Torrents** connect to trackers and other peers, who see your IP address, as with any torrent app.
- **The built-in browser** loads the pages you open.
- **Casting and Watch Together** talk to devices on your own network.
- **Report a bug** opens a GitHub issue page in your browser with your app version, platform and recent log. You see all of it before anything is sent, and nothing is sent unless you submit it.

## Play Store version

The Play Store version (BitPlayer) shows ads from Google AdMob and handles purchases through Google Play. Its [data safety details](docs/publishing/play-data-safety.md) say exactly what that involves. It is built and signed separately and is not part of the SignPath code signing.
