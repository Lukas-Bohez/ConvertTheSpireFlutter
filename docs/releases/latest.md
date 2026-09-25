# Release Notes - v15.0.0

## Open files and magnet links with the app, faster torrents, copy song titles

### New

* **Open your songs, videos, torrents and magnet links with the app.** Windows, Android and macOS now list the app when you open a song, a video or a .torrent file: in "Open with" on Windows, in Open With in the Finder, and in the "Open with" choice on a phone. Songs and videos start playing in the player straight away, without being added to your library; .torrent files and magnet links go straight to Torrents. It works for mp3, m4a, flac, wav, ogg, opus, aac, wma, mp4, mkv, avi, webm, mov, wmv, flv and m4v.
* **Magnet links from your browser.** Click a magnet link in Chrome, Firefox, Edge or any other browser and it opens in the app. The app never takes magnet links away from a torrent app you already use: on Windows it only picks them up when no other app handles them, and you can choose it yourself under Settings › Apps › Default apps.
* **One window.** Opening a file, a link or the app itself while it is already running brings the open window to the front, also when it is hidden in the tray, instead of starting a second copy. On Android, a file opened from another app goes to the app that is already open.
* **Copy a song's title.** Press and hold a title in the player, or right-click it on a computer, and it is copied, ready to paste into a search or a message. Every track's ⋮ menu has Copy title too, which also works with a TV remote. The player looks just as it did.

### Fixed

* **Torrents download faster.** The app asked for every torrent's pieces strictly in order, and finding the next one took longer the bigger the torrent and the further along it was, on the same thread that draws the screen. On a 2 GB torrent that came to nearly 50 ms every time a peer had nothing new to send. Pieces now come rarest-first, the way other torrent apps fetch them, which takes a small fraction of that time, so downloads go faster and the app stays responsive while they run.
* **Downloads no longer stall just short of 100%.** A peer that ran out of pieces to send was never asked again, so once every peer had gone quiet the torrent stopped, often near the end. The app now checks every few seconds and asks idle peers for the pieces that are still missing.
* **Torrents with several files finish.** A season pack, an album or a game never reported that it was done, showed 0% to the torrent engine's own checks, and told trackers it had nothing left to download.
* **The ad-free half hour says so (Play Store version).** After you watched an ad for 30 minutes without ads, the app said "No reward recorded, ads stay on", although the break had started. It now waits until the ad is closed and tells you the break is on.
* **No ads without your consent (Play Store version).** When the privacy consent check failed at startup, ads were loaded anyway. They now stay off until consent is confirmed, at the latest on the next start.
* **The ad break lasts 30 minutes, not longer (Play Store version).** Full-screen ads only came back after the app had been in the background once.
* **The Play Store version's home screen no longer asks you to paste a link** it cannot download. It says what the app does instead: torrents, music, videos and file conversion.
* **Remove Ads no longer reads "Remove Ads — Remove Ads"** while the Play Store has not given its price yet (Play Store version).

### Improved

* **Ads that fit in (Play Store version).** One small banner under the home screen, and now and then a full-screen ad when you finish something, such as a conversion, or come back to Home: never in your first two minutes, at most one every three minutes, and never while music or a video is playing. Android TV shows no ads at all. The banner takes no room until an ad has loaded, fits the width of the screen, and goes away during your ad-free half hour.
* Watch an ad for a colour says so when there is no ad to watch, instead of doing nothing. On Android TV the colour spins straight away (Play Store version). Where there are no ads, on Android TV and in the GitHub builds, the Support screen no longer shows Remove Ads or an ad counter.
* The app no longer loads an ad it never shows, and no longer loads two full-screen ads at once.
* When a torrent moves on from a peer that stopped sending, the pieces it was waiting for are picked up by the others right away.
