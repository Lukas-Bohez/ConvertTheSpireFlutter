# Convert the Spire Reborn v15.0.0

## Open files and magnet links with the app, faster torrents, copy song titles

### New

- **Open your songs, videos, torrents and magnet links with the app.** Windows, Android and macOS now list the app when you open a song, a video or a .torrent file: in "Open with" on Windows, in Open With in the Finder, and in the "Open with" choice on a phone. Songs and videos start playing in the player straight away, without being added to your library; .torrent files and magnet links go straight to Torrents. It works for mp3, m4a, flac, wav, ogg, opus, aac, wma, mp4, mkv, avi, webm, mov, wmv, flv and m4v.
- **Magnet links from your browser.** Click a magnet link in Chrome, Firefox, Edge or any other browser and it opens in the app. The app never takes magnet links away from a torrent app you already use: on Windows it only picks them up when no other app handles them, and you can choose it yourself under Settings › Apps › Default apps.
- **One window.** Opening a file, a link or the app itself while it is already running brings the open window to the front, also when it is hidden in the tray, instead of starting a second copy. On Android, a file opened from another app goes to the app that is already open.
- **Copy a song's title.** Press and hold a title in the player, or right-click it on a computer, and it is copied, ready to paste into a search or a message. Every track's ⋮ menu has Copy title too, which also works with a TV remote. The player looks just as it did.

### Fixed

- **Torrents download faster.** The app asked for every torrent's pieces strictly in order, and finding the next one took longer the bigger the torrent and the further along it was, on the same thread that draws the screen. On a 2 GB torrent that came to nearly 50 ms every time a peer had nothing new to send. Pieces now come rarest-first, the way other torrent apps fetch them, which takes a small fraction of that time, so downloads go faster and the app stays responsive while they run.
- **Downloads no longer stall just short of 100%.** A peer that ran out of pieces to send was never asked again, so once every peer had gone quiet the torrent stopped, often near the end. The app now checks every few seconds and asks idle peers for the pieces that are still missing.
- **Torrents with several files finish.** A season pack, an album or a game never reported that it was done, showed 0% to the torrent engine's own checks, and told trackers it had nothing left to download.
- **The ad-free half hour says so (Play Store version).** After you watched an ad for 30 minutes without ads, the app said "No reward recorded, ads stay on", although the break had started. It now waits until the ad is closed and tells you the break is on.
- **No ads without your consent (Play Store version).** When the privacy consent check failed at startup, ads were loaded anyway. They now stay off until consent is confirmed, at the latest on the next start.
- **The ad break lasts 30 minutes, not longer (Play Store version).** Full-screen ads only came back after the app had been in the background once.
- **The Play Store version's home screen no longer asks you to paste a link** it cannot download. It says what the app does instead: torrents, music, videos and file conversion.
- **Remove Ads no longer reads "Remove Ads — Remove Ads"** while the Play Store has not given its price yet (Play Store version).

### Improved

- **Ads that fit in (Play Store version).** One small banner under the home screen, and now and then a full-screen ad when you finish something, such as a conversion, or come back to Home: never in your first two minutes, at most one every three minutes, and never while music or a video is playing. Android TV shows no ads at all. The banner takes no room until an ad has loaded, fits the width of the screen, and goes away during your ad-free half hour.
- Watch an ad for a colour says so when there is no ad to watch, instead of doing nothing. On Android TV the colour spins straight away (Play Store version).
- The app no longer loads an ad it never shows, and no longer loads two full-screen ads at once.
- When a torrent moves on from a peer that stopped sending, the pieces it was waiting for are picked up by the others right away.

### Build Notes

- Version 15.0.0+1299. Build the Play AAB with `--flavor play` as usual.
- `flutter analyze` is clean and all tests pass (504 before this release's player and ad changes, plus their new tests).
- Copy title: `copyTrackTitle` in `player.dart`, from the track menu, the now-playing and opened-file cards, song rows, media cards and the browser's mini-player. Android 13+ phones show their own clipboard preview, so the app's message is skipped there (new `showsCopyConfirmation` on `convert_the_spire/saf`); Android TV, older Android and desktop show it.
- Ads: `AdService` is a `ChangeNotifier` with `adsReady` and `adsSupportedOnDevice`, and turns itself off on Android TV (`isAndroidTV`), whose quality guidelines (TV-AD, TV-AU) AdMob's formats do not meet. `AdBannerSlot` loads an anchored adaptive banner when ads become ready, retries after a minute, and reserves nothing until it has one. It uses the standard anchored size: google_mobile_ads 8.0.0 decodes every anchored size as non-large on Android, so `getLargeAnchoredAdaptiveBannerAdSize` gave a 128 dp slot around a 64 dp ad. `maybeShowInterstitialAtBreak` (was `maybeShowInterstitialAfterSuccess`) runs after a conversion and on returning to Home; `AdFrequencyGate` is 2 min grace, 3 min apart, 3 interactions, and a rewarded ad counts.
- AdMob console: UMP reports "no form(s) configured for the input app ID": the app has no GDPR message. The app still starts ads everywhere (also with the device treated as in the EEA), but without Google's certified consent message, EEA and UK traffic only gets Limited Ads, which fill poorly. Publish a European regulations message under Privacy & messaging. `--dart-define=UMP_DEBUG_EEA=<hashed device id>` makes a test build behave as if it were in the EEA.
- Torrents: `TorrentTask.newTask` gets `stream: false` (dtorrent_task_v2's rarest-first `BasePieceSelector`) instead of `AdvancedSequentialPieceSelector`, whose per-block cost grows with pieces × peer pieces; measured with the library's own classes. Multi-file models get `TorrentModel.length` set to the total size (`TorrentEngineService.withTotalLength`), because the library reads it as the total and left it null. Idle, unchoked peers are woken every 5 s through `requestPieces`.
- Opened files and links: a new `convert_the_spire/open` channel (`takePending`, and `pending` from the platform) on Android (`MainActivity`), Windows (runner) and macOS (`AppDelegate`), read by `OpenRequestService`.
- Android: `MainActivity` is `launchMode="singleTask"` and sets `flutter_deeplinking_enabled` to false. New intent filters for `magnet:`, .torrent, `audio/*` and `video/*`. No new permissions, so the Play data safety form does not change.
- Windows: `windows/runner/open_requests.cpp`. One copy at a time (mutex `Local\ConvertTheSpireReborn.Instance`, arguments forwarded with `WM_COPYDATA`). Per-user registration under `HKCU\Software\Classes` (ProgIDs `ConvertTheSpireReborn.Media`, `.Torrent`, `.Magnet`, `Applications\convert_the_spire_reborn.exe`) and `Capabilities` + `RegisteredApplications`, rewritten at each start so it follows a moved folder. `magnet:` itself is written only when no handler exists or it already points at this exe. Forwarding and registration were run under Wine; Explorer's own prompts need a real Windows PC.
- macOS: `Info.plist` document types (Alternate rank), the `magnet` URL scheme and imported UTIs for mkv, webm, flv, wmv, wma, flac, ogg, opus and torrent. CI does not build macOS, so the release workflow's macOS job is the first compile of the `AppDelegate.swift` change.
- Ads (`AdService`): the rewarded-ad result waits for the ad to close; every consent path goes through `canRequestAds()`; the unused rewarded interstitial and `loadInterstitial` are gone; a timer reloads ads when the ad break ends.
