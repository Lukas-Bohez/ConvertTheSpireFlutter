# Privacy policy

The full privacy policy is at **[quizthespire.com/privacy](https://quizthespire.com/privacy)**. It covers this app (Convert the Spire Reborn for Windows, macOS and Android, published on Google Play as BitPlayer, `com.torrentspire.ai`) and the quizthespire.com website. This page is the same policy for the app, kept next to its code.

One person runs all of this: Lukas Bohez, a solo developer in Belgium. There is no company behind it. Nothing is sold, and nothing is shared except where this page names who.

**In short:** the app sends me nothing, and everything it keeps stays on your device. Only the Google Play build shows ads.

## What the app collects

The app has no account, no sign-in and no server of mine to talk to. It sends me nothing: no analytics, no crash reports, no usage statistics, no telemetry. Your downloads, conversions, playlists, library, settings and logs are written to your own device and stay there. Files you convert are processed on the device and are never uploaded.

## Where the app connects

- **The sites you give it a link to** (YouTube and the other sites yt-dlp supports). The request goes straight from your device to that site, which sees what any browser visit shows: your IP address and a user-agent.
- **GitHub.** The Windows, macOS and GitHub Android builds check for a new app version when they start (you can turn this off in Settings). The desktop builds download yt-dlp and keep it up to date. On Windows, **Update now** downloads the new installer, only when you press it. Nothing about you goes with these requests beyond what any download needs.
- **gyan.dev** (Windows only): when FFmpeg is missing, the app downloads it from there, the same way.
- **Torrent trackers and peers**, if you use torrents: they see your IP address, as with any BitTorrent client.
- **Devices on your own network**, if you cast or use Watch Together.
- **Google AdMob**, in the Google Play build only (see below).

**Report a bug** in Settings opens a GitHub issue page in your browser with your app version, platform and recent log. You see all of it first, and nothing is sent unless you submit it.

None of these requests carry an identifier I created, because the app never creates one.

## Ads (Google Play build only)

The Android build from Google Play shows ads through Google AdMob. To fetch an ad, AdMob reads your device's advertising ID with device and connection information and sends it to Google, over HTTPS. I never see it. You can reset or delete the advertising ID in Android's settings (Settings → Google → All services → Ads), and the app keeps working with non-personalised ads. The Windows, macOS and GitHub Android builds carry no ads. The full details, and the Google Play data safety summary, are in the [full policy](https://quizthespire.com/privacy) and [docs/publishing/play-data-safety.md](docs/publishing/play-data-safety.md).

## Deleting your data

Nothing is held off your device, so there is nothing to request. To remove what the app keeps on it:

- **Windows:** uninstall it in Settings → Apps (or delete the folder, if you used the zip), then delete `%APPDATA%\Oroka Conner\Convert the Spire Reborn` and `%LOCALAPPDATA%\ConvertTheSpireReborn`, which hold its settings and caches.
- **macOS:** delete the app and its settings folder.
- **Android:** Settings → Apps → the app → Storage → Clear storage, or uninstall it.

Files you downloaded or converted stay where you saved them: they are your files, not app data.

## Your rights and contact

You can ask what is held about you, ask for it to be corrected or deleted, or complain to the Belgian Data Protection Authority. Contact details are in the [full policy](https://quizthespire.com/privacy).
