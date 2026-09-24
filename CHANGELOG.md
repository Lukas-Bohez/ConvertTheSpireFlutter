# Changelog

## 14.5.0+1298 — Every screen in your language, magnets that start, Compare on phones

### Fixed

- **The app speaks your language, all of it.** Choosing a language in Settings used to change little more than the tab names; almost every screen, dialog and message stayed in English. All 18 languages now cover the whole app: Arabic, Dutch, English, French, German, Hindi, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Russian, Simplified Chinese, Spanish, Turkish, Ukrainian and Vietnamese. A check in the build now fails if a screen slips back into English.
- **Magnet links no longer sit at "Stalled 0.0%".** A magnet first has to get its file list from other people before anything can download, and three things kept that from happening. The app threw away the trackers listed in the link and asked only its own backup list, so a nyaa release never reached the tracker most of its swarm uses. One peer that stopped answering could hold up the file list for good. And links with a base32 hash, which nyaa uses, were saved in a form that broke resuming. The app now uses the link's own trackers, moves on to fresh peers when the file list stops coming, and saves every magnet under its standard hash. If nobody sends the file list within ten minutes, the torrent waits and tries again by itself instead of staying stuck.
- **Your settings stay put on Android.** Every setting, the download folder included, was forgotten each time the app closed: the app asked Android where to keep its settings and never got an answer. It keeps them now, so you choose a download folder once.
- **Compare works on phones.** A folder picked on a phone is an Android document address that the scan could not open, so every song showed as missing. The app now reads those folders, and asks Android for a whole folder at a time instead of file by file, so big music folders also open quicker in the player.
- **Compare no longer calls different songs a match.** A title check compared each title with itself, so almost any song "matched" whatever file was left over, on every platform, and the Missing tab came up short. Exact matches are strict now; anything less certain shows its real confidence in the Matched tab.
- **A half-finished download no longer counts as downloaded.** Files like `Song.temp.mp4` and yt-dlp's `.part` files are listed under Extras as incomplete, ready to delete, instead of hiding the song from Missing.
- **Export missing list and Export as M3U work on Android.** Both did nothing on phones.
- **Saving a converted file tells you where it went,** or why it could not be saved. The Save button used to give no sign either way.
- **Compare fits a phone.** The confidence filters, the Missing tab buttons and the Extras headings ran off the edge of the screen; they wrap now. The Quick Download card no longer overflows with larger text.
- **A full-size tile on Android TV.** The app's banner and icon now come in the sizes Android TV asks for, and the banner shows just the logo and the name, big enough to read from the couch, instead of a tagline too small to read. Google Play's TV review had flagged the old ones.

### New

- **This video or the whole playlist?** Press download while a video plays from a playlist, in the browser or in Quick Download, and the app asks which one you meant. On a playlist page, download takes the playlist. Either way the playlist opens in the Playlist Manager, which first shows the songs you already have. Before, you got only the video, and a playlist page failed. Mixes, Watch Later and Liked videos still download just the video.
- **Open folder is back on the phone player's top bar,** where Watch Together was. Watch Together moves into the ⋮ menu, and returns to the bar while you are in a room. An empty library has its own Open folder button.
- **The player remembers your library.** The folder you open comes back by itself the next time you start the app.
- **The file converter is on Android,** in the Play version too. It was hidden on every Android phone and TV, but the Android app carries FFmpeg, so audio, video, image, document and archive conversions all work there. Converted files go to Downloads/Converted unless you picked a download folder.
- **Extensions on phones.** The browser menu has Extensions on Android too. Full Chrome and Firefox extensions still need the Windows app, so on a phone it shows what does run: the built-in ad blocker, your userscripts, and one-tap searches for popular userscripts such as dark mode, Return YouTube Dislike and SponsorBlock.

### Improved

- While a magnet is getting its file list, it says "Fetching metadata" instead of "Stalled". Torrent statuses are now in your language too.
- Adding a magnet from the browser or a link opens the Torrents tab right away, instead of after the file list arrives. When the app starts, other torrents no longer wait behind a magnet that is still getting its file list.
- Converting shows that it is working, and says why when a conversion fails, instead of leaving the reason in the log.
- Compare remembers the last folder, starts from your download folder, and asks for a folder instead of doing nothing when none is set. Phone folders read "Phone storage/Music" instead of a content:// address, in Compare and in Settings.
- Downloading the missing songs saves them into the folder you compared, next to the rest of the playlist.
- In the Missing tab, tap anywhere on a row to select it.
- A playlist sent from Quick Download keeps the format you chose there.
- A folder with no music in it says so, instead of listing every song as missing.
- Compare skips folders it is not allowed to read, such as Android/data, instead of stopping.
- The Play Store version says that YouTube downloads are not part of it, instead of "Added to queue".

## 14.4.1+1297 — Startup fix and a smaller Windows download

### Fixed

- **The app opens again.** 14.4.0 stayed on its loading spinner and never got any further, on every platform. Nothing you had was touched: your library, downloads and settings are all there once it opens.
- **Windows Defender no longer flags the Windows download** (issue #12). The Windows version carried about a hundred conversion libraries that only the Android and iOS versions use, and Defender flagged one of them, avdevice. They are gone from Windows, which also halves the download, from about 86 MB to about 41 MB. Converting on Windows works as before. When you update, extract into a new folder rather than over the old one, so the flagged file does not stay behind.
- **Closing the app on Windows no longer crashes it** on the way out.

### Improved

- **What's new shows what you missed.** If you skipped a release, as nearly everyone did with 14.4.0, its notes now follow this one's.

## 14.4.0+1296 — Mobile fixes and browser extensions

### New

- **Browser extensions on Windows.** Install Chrome extensions, and add-ons from addons.mozilla.org that also support Chromium, from Extensions in the browser menu or in Browser Settings. Search the add-ons catalog inside the app, see what an extension will be able to do before anything installs, switch extensions on and off, and open their popups and options, update or remove them. Downloads from addons.mozilla.org are checked against the checksum it publishes. Tested with Dark Reader and uBlock Origin Lite. Windows only for now.

### Fixed

- **Downloads keep going when the phone is locked.** Android was freezing the app shortly after the screen went off, so downloads and torrents stalled until you opened it again. While anything is downloading, the app now keeps itself running with a notification that shows progress, and its Stop button pauses everything.
- **Watch Together no longer opens to a grey screen.** The room sheet could not reach the player, which showed up as a blank grey box on every platform.
- **Searching from the browser searches the web.** The address bar now uses your chosen search engine, the same as the new tab page, and links that used to throw you into the YouTube app open in the browser instead. Anything that really needs another app asks first.
- **Refresh no longer spins forever on Windows.** It finishes within a few seconds; checking your watched playlists now happens in the background.
- **Your support colour now reaches the whole app,** including the player bar, sliders, progress indicators and the incognito toolbar.
- **Userscripts now run in the Windows browser.** Since they arrived in 14.3.0 they installed and showed up in the list on Windows, but never actually ran on the page.
- **The browser toolbar fits larger text.** With a bigger system text size the address bar was cut off on every screen size; it now grows to fit, and long menu entries wrap instead of spilling over.

### Improved

- **A less crowded player on phones.** Watch Together and the queue stay in the header, and open folder, organize, fix metadata and volume leveling move into a menu with proper labels. The video takes a sensible share of the screen instead of a fixed height, and the track title gets more room.
- **Watch Together without the file.** A guest that does not have the host's file, like a TV, now streams it from the host over your network, seeking included.
- **Choose the app language in Settings.** Any of the 18 translations, or automatic.
- **Report a bug** from Settings opens a GitHub issue with your app version, platform and recent log already filled in. You see all of it before anything is sent.
- **What's new** appears once after each update. The intro tour now only runs on a first install instead of after every update.
- If a screen ever fails to load, you get a readable message with Copy details and Report buttons instead of an empty grey box.
- A smaller download: several libraries the app no longer used have been removed.

## 14.3.1+1295 — Watch Together polish

### Fixed

- **Seeking now reaches the room immediately.** A scrub was only picked up by the once-a-second state broadcast, so everyone else stayed up to a second behind after the host dragged the scrubber. The new position is sent the moment it changes.
- **"The room is watching something you do not have" is now actually shown.** When the room moves to a file that is not in your library, the player produced that message but nothing displayed it, so the screen just sat there looking stuck. It now appears as a warning.
- Local build logs no longer clutter the repository root.

## 14.3.0+1294 — Userscripts in the browser

### Added

- **Userscript support.** The browser now runs Greasemonkey/Tampermonkey userscripts. Install one by URL from somewhere like Greasy Fork, or paste the code in, and manage everything under **Browser menu → Userscripts**. Scripts can be switched on and off individually, updated in place, and there is a master switch for all of them.

  The `// ==UserScript==` header is parsed the way Tampermonkey parses it: `@match`, `@include`, `@exclude`, `@run-at`, `@grant`, `@name`, `@version`, `@description` and `@downloadURL`. Chrome-style match patterns are supported, including `*://*.example.com/*`, as are `@include` globs and `/regular expressions/`. `@run-at document-start` runs before the page's own scripts; everything else runs once the DOM is ready.

  A `GM_*` shim is provided so most scripts run unmodified: `GM_addStyle`, `GM_getValue`, `GM_setValue`, `GM_deleteValue`, `GM_listValues`, `GM_log`, `GM_info`, `GM_openInTab`, `GM_setClipboard`, `GM_xmlhttpRequest` and `unsafeWindow`, plus the promise-based `GM.*` equivalents. Stored values are namespaced per script so two scripts cannot tread on each other, and every script runs inside its own try/catch so a broken one logs an error instead of breaking the page.

- **Install by clicking a link.** Navigating to any `.user.js` URL now offers to install it, the way a userscript manager does, instead of showing you a wall of JavaScript. The prompt states plainly that userscripts run with full access to the pages they match, so only install from a source you trust.

- **`@require` and `@noframes`.** Libraries listed with `@require` (jQuery and friends) are downloaded at install time, cached, and inlined ahead of the script body — so a page load never waits on the network and the script keeps working offline. A library that fails to download is skipped rather than blocking the install. `@noframes` scripts run only in the top-level page, never inside iframes.

### A note on Chrome and Firefox extensions

This is **not** extension support, and it cannot become it. Extensions need the browser shell to implement the WebExtensions API — background workers, isolated content-script worlds, `declarativeNetRequest`, the tabs and permissions model, CRX/XPI loading. The app renders pages with the platform WebView (WebView2 on Windows, the system WebView on Android), which exposes no extension host at all; the binding has a `UserScript` type and no extension API whatsoever. Shipping real extension support would mean shipping a browser engine, which is a different project.

Userscripts cover a good share of what people actually install extensions for — site tweaks, layout fixes, quality-of-life patches — and ad and tracker blocking is already built in separately.

### Fixed

- **Release builds were failing to compile.** `flutter pub get` writes a plugin registrant that registers every plugin including dev-only ones (`integration_test`), while Gradle correctly leaves those off the release classpath — so the generated Java referenced a package that did not exist. Release builds now strip dev-dependency registrations before compiling, using Flutter's own `dev_dependency` flag as the source of truth. Debug builds are untouched, so integration tests still run.

### Improved

- The ad blocker's matching rules are now covered by tests, including the guard that stops a bare TLD from ever being blocked and the case where a lookalike domain merely ends with a blocked name.


## 14.2.0+1293 — Watch Together

### Added

- **Watch Together.** Start a room on one device, share the six-character code, and everyone watches in step: play, pause and seek all propagate. Phone, PC, Mac and the TV, in any combination.

  It runs entirely on your own network. There is no server, no account and no sign-up — the host device *is* the server, and guests find it automatically over the LAN, so the code is the only thing anyone has to type. If a network blocks discovery (guest wifi often does), you can join with the host's address instead.

  Keeping devices in step across a network is not as simple as "send play" — the clocks disagree and messages take time to arrive. The host stamps every update with its own clock; each guest measures the round-trip delay the way NTP does, keeping the fastest sample so one slow packet cannot skew it, then works out where playback *should* be right now. Drift under ¾ of a second is left alone, because correcting it is more jarring than living with it. Someone joining halfway through gets the current position immediately instead of a black screen.

### Improved

- **The ad blocker is now covered by tests.** It had none. The rules that matter most are now pinned down: subdomains of a blocked domain are blocked, a bare TLD never is (a single bad list entry could otherwise have taken down every `.com` site), and a lookalike domain such as `nottracker.net` is not blocked just because it ends with a blocked name.

## 14.1.2+1292 — Full playlists on Android (200 -> 855), Play Data Safety fix

### Fixed

- **Large playlists stopped at 200 entries on Android.** v14.1.0 fixed the first half of this (the parser only knew one of YouTube's continuation-token shapes, which capped it at 100). Testing an 863-entry playlist showed the real remaining cause: YouTube's plain WEB API **stops issuing continuation tokens after two pages**. Page 2 comes back with 100 videos and no continuation marker anywhere in the response, so there was nothing left to follow — no parser change could have gone further.

  The app now falls back to the YouTube Music (`WEB_REMIX`) client, which pages through the same playlist to the end, and merges the results by video id. Measured on the 863-entry playlist used to reproduce this: **200 entries before, 855 after.** The handful still missing are private, deleted or region-locked videos, which no client can enumerate.

- **The ad-free GitHub build no longer requests the advertising-ID permission.** The Google Mobile Ads library merges `AD_ID` and `ACCESS_ADSERVICES_AD_ID` into every build from its own manifest, even though ads are Play-only and never initialise here. Both are now explicitly stripped from the GitHub flavor, verified against the merged manifest.

- **In-app privacy text is now accurate per build.** The Play build previously showed "No advertising or analytics" under a heading literally called "Data Safety", while serving AdMob. It now states plainly that ads use the device advertising ID. The GitHub build keeps the stronger claim, because there it is true.

### Improved

- The playlist parser reads all three item layouts YouTube serves (`lockupViewModel`, `playlistVideoRenderer` and the Music client's `musicResponsiveListItemRenderer`), so a layout switch on any page no longer silently yields zero videos.
- `docs/publishing/play-data-safety.md` records exactly what each SDK collects and the precise Play Console answers, guarded by tests so the declaration cannot drift out of sync with the code again.


## 14.1.0+1290 — Playlists past 100 videos on Android, app in 18 languages

### Fixed

- **Playlists stopped at 100 videos on Android.** This is the big one. Android has no yt-dlp fallback, so every playlist is enumerated by the in-app page parser, which walks YouTube page by page using a "continuation token". YouTube emits that token in several different shapes and switches between them without notice — the parser only recognised one of them, so on any playlist whose page used a different shape pagination stopped dead after the first page, at exactly 100 entries. All known token shapes are now recognised, so an 800-item playlist enumerates fully on a phone.
- **Continuation pages that used the classic item format parsed to zero videos.** YouTube mixes two item layouts (`lockupViewModel` and `playlistVideoRenderer`) and can return a different one on page 2 than on page 1. Only the first was parsed, so some playlists paged forever while adding nothing. Both layouts are now read, and pages are merged by video id so nothing is counted twice.
- **Pagination could stall or spin.** Each continuation token is now spent once, and entries are de-duplicated by video id, so a repeated token can no longer loop forever re-fetching the same page.

### Added

- **The app now speaks 18 languages.** It follows your device language automatically, with English as the fallback: Arabic, Dutch, English, French, German, Hindi, Indonesian, Italian, Japanese, Korean, Polish, Portuguese, Russian, Simplified Chinese, Spanish, Turkish, Ukrainian and Vietnamese. Right-to-left layout works for Arabic. This first pass covers the navigation and the common actions and states; the longer screens are still English and will be translated as native speakers review them. Contributions are very welcome — the files are plain `.arb` under `lib/l10n/`.

### Improved

- The playlist parser is covered by offline tests for every token shape and both item layouts, so a future YouTube change fails a test instead of silently capping playlists again.
- Every translation file is checked in CI against the English template — a missing or blank translation fails the build rather than showing a blank label.

## 14.0.1+1289 — Tidy Windows download, fixed Android icon, demo video

### Fixed

- **The Windows download is no longer a wall of DLLs.** The zip root now contains just `convert_the_spire_reborn.exe`, a `data/` folder and a `dll/` folder holding every library, so the exe is easy to find. This works by delay-loading the engine and plugin DLLs and pointing the loader at `dll/` before they are first used (the earlier attempt crashed at launch because those imports were resolved before the app started). The exe now links the C runtime statically, so it needs no runtime DLLs beside it.
- **Android launcher icon was cut off and had see-through parts.** The icon is rebuilt from the real logo with an opaque background and the whole logo (including the music note) kept inside the adaptive-icon safe zone, so it is no longer zoomed in or cropped by round/squircle masks. A matching legacy icon is included for older Android versions.
- **Old AI-generated logo removed from the Android TV banner and Play TV images.** The TV banner, the two TV screenshots and the promo image now use the proper logo and real app screenshots.
- **Windows builds no longer fail on machines using a non-UTF-8 system code page** (for example Japanese code page 932): sources are now compiled as UTF-8.

### Added

- **Demo video.** Watch the tour on YouTube: https://youtu.be/66Rx8PDY_r0. It is linked from the README, at the top of every GitHub release and from the in-app Support screen.
- **Store assets folder.** `store/google-play/` holds every Play Console graphic plus one script that regenerates all of them (and the Android launcher icons) from the real logo and screenshots.

### Improved

- The release workflow now fails if any loose DLL ends up in the Windows zip root.
- Unit tests for the volume-leveling gain calculation.

## 14.0.0+1288 — Reliable play stats, simpler video playback, volume leveling, friendlier errors


### Fixed


- **Play counts and time played now stay in sync.** Listening time was added as the track's *absolute* position on every app-lifecycle/select event (so it double counted), while the play count was only recorded after several awaited steps that could be skipped. Time is now committed as a delta since the last commit (also saved every 30 s and on track completion), the play count is refreshed in the UI immediately, and per-track stats are re-baselined on each new play.
- **Videos no longer restart from the start after you leave the app.** Videos are now treated differently from songs: the glitchy video-to-audio "background mode" hand-off has been removed. A video simply pauses when the app goes to the background (Android) and keeps its position; on desktop, losing window focus no longer touches playback.
- **Browser "Clear browsing data" now really clears everything.** It previously wiped history only and needed an open page; quick-access links (recent sites) were never cleared. Both are cleared now, and the new-tab page refreshes right away.
- **Browser Refresh button** now performs a real reload and refreshes the quick-access tiles on the new-tab page (it used to do nothing there).

### Improved

- **Volume leveling (new, on by default).** Every track/video is measured once (FFmpeg `volumedetect`, cached) and played at a common target loudness, so a very quiet track and a very loud one sound equally loud. Toggle it with the equaliser icon in the player toolbar.
- **Errors are impossible to miss.** Error messages now have a red border, a bug icon, a longer display time and a light-hearted headline above the real message.
- **Releases now include screenshots and a README link** automatically (appended by the release workflow).

### Removed

- **Linux builds are discontinued.** The release workflow no longer builds or publishes Linux artifacts.


## 13.2.1+1287 — yt-dlp SABR/player_client fix, browser tab thumbnails, decode fix, live Missing tab

### Fixed
- **YouTube downloads failing with \"the page needs to be reloaded\" — root cause found and fixed: the app was forcing `--extractor-args youtube:player_client=tv,web` on every download.** The verbose run the note below called for was executed on the affected Windows machine using the app's own provisioned binary (`Roaming\Oroka Conner\Convert the Spire Reborn\yt-dlp\yt-dlp.exe`, yt-dlp 2026.08.19, Deno 2.9.6 — the Deno fix is confirmed working: `JS runtimes: deno-2.9.6`, provider `deno` available). The app's exact argument set reproduced the failure outside the app, and bisection isolated it: with `player_client=tv,web` the `tv` player response returns **UNPLAYABLE** and the `web` client's https formats are skipped as \"missing a URL\" (YouTube is forcing SABR streaming for that client, yt-dlp#12482) → `ERROR: [youtube] <id>: The page needs to be reloaded.` The plain invocation of the *same binary* on the *same video* succeeds. The in-code comment claiming the tv client \"doesn't trigger SABR\" no longer matched reality — YouTube moved. The override is removed from `yt_dlp_service.download()`; downloads now use yt-dlp's default client order. Verified post-fix: the full app argument set (Node + Deno runtimes, both the mp4 `bestvideo[height<=H]+bestaudio/best[height<=H]` and the audio `bestaudio/best` specs) extracts the target video cleanly — exit 0, no SABR/UNPLAYABLE warnings in the verbose log. Independently confirmed against yt-dlp#12482 and an Arch Linux forum thread — the `tv` client specifically is affected, not just `web`.
- **Browser tab-switcher screenshot thumbnails stretched to 16:9 at decode time.** The tab-switcher's `Image.memory` and `Image.file` in `browser_screen.dart` passed paired `cacheWidth: 640, cacheHeight: 360` decode hints. A browser page's rendered viewport has no guaranteed aspect, so non-16:9 pages (portrait docs, tall articles) were pre-stretched at decode time — the same bug class as the now-player hero fix below. Dropped `cacheWidth`, kept `cacheHeight: 360` (aspect-preserving), so the true page aspect is now respected.
- **Thumbnail stretching in the now-playing hero card and the mini-player bar.** All four `Image.memory` thumbnail sites (the hero expand path, `thumbnailForItem`'s grid path, `_TrackThumbnail`, and the mini-player's `_buildArtwork`) passed *paired* `cacheWidth`+`cacheHeight` decode hints sized to the display box. `instantiateImageCodec` scales to exactly those dimensions **without preserving the source image's own aspect**, so square (album-art) or portrait thumbnails were pre-stretched to 16:9 *at decode time* — and `BoxFit.cover` crops, it cannot un-distort an already-stretched bitmap. The cards that looked correct (`quick_download_card`) simply had no decode hints. The home screen's download-list `Image.network` tile (4:3 hint) and the search-results list tile (square 112×112 hint) had the same bug class and were fixed the same way. Decode hints are now height-only (aspect-preserving) at every site, so `BoxFit.cover` crops the true aspect correctly everywhere.
- **Playlist "Missing" tab went stale after downloading missing tracks.** `Download Selected` only *queues* downloads — it returns immediately — and nothing ever re-ran the folder compare afterwards, so a track the queue panel showed as completed stayed on the Missing list (the track really did download; the tab just never looked again). The playlist screen now listens to `AppController` and, when a previously-missing track's queue item reaches `completed`, moves it Missing → Matched in memory immediately (queue `outputPath` as ground truth, no folder re-scan); the Compare button still does a full re-scan.
- **Misleading "self-update failed" error from yt-dlp reload-error recovery.** The catch block wrapped both the self-update call *and* the post-update retried download, so when yt-dlp updated fine and the fresh binary *still* failed the same `[youtube]` extraction way, the app reported "self-update failed" with the download's error text — hiding the important fact that a current yt-dlp still can't extract the video. The two outcomes are now reported distinctly: "self-updated successfully, but the retried download still failed (a live YouTube extraction problem — run `yt-dlp -v <url>` outside the app)" vs "the self-update itself failed and a plain retry with the existing binary also failed". Also removes the accidental third attempt of the same fresh binary on that path.
## 13.0.18+1281 — Web browser support, player tab icons, low-end PC safety

### Added
- **Web browser support.** The in-app browser now works on web platform via `flutter_inappwebview`'s iframe-based adapter. Browser screen renders and functions correctly in web browsers.

### Fixed
- **Player tab icons replaced emoji with proper Material Icons.** The player tabs now use `Icons.library_music`, `Icons.music_note`, `Icons.video_library`, and `Icons.favorite` instead of emoji characters (♪, ▶, ☁) that rendered inconsistently across platforms.
- **Favourites tab renamed from "EFav" to "Fav".** Cleaner, more professional label.

### Safety
- **Web browser adapter is safe for low-end PCs.** The web adapter uses pure HTML/JS iframe rendering with no native code, no BMI2 instructions. Windows continues to use WebView2 (`webview_windows`) which is also BMI2-safe. The factory correctly selects the right adapter per platform.

## 13.0.17+1280 — Defensive pinned-header clipping + review pass

### Fixed
- **Home screen search header could paint over the scrollable body.** The search bar sits in a fixed-height pinned `SliverPersistentHeader` (`_SearchHeaderDelegate`) whose `build` returned the child with no clip — the same latent overflow class already fixed in the player's pinned header (v13.0.15). Wrapped the delegate's child in a `ClipRect` so any content exceeding the fixed extent is clipped instead of drawn over the body below.

### Review (no functional change)
- Verified the v13.0.16 metadata_god → pure-Dart `audio_metadata_reader` Windows fix: the duck-typed `dynamic` metadata consumption in `resolveArtist`, `_extractGenre` and `_extractReplayGainTrackGain` is safe (every access is try/catch-wrapped with `.toString()`; the replay-gain extractor falls through gracefully on non-matching types), and both `audio_metadata_reader` and `metadata_god` are present in `pubspec.yaml`.
- Confirmed the v13.0.15 player fixes (single-row scrollable genre chips, player pinned-header `ClipRect`, corrected header heights, and the unified-button `maximumSize` cap removal) are all intact after the v13.0.16 changes.
- `flutter analyze` clean; all 30 tests pass.

## 13.0.16+1279 — Folder-load crash fix on low-end Windows (no BMI2) + 811-video playlist install

### Fixed
- **Loading a folder into the player crashed the entire app on older Windows CPUs without BMI2/AVX2 (e.g. the Ivy Bridge i3-3220 low-end QA box).** Folder load (`PlayerState.setLibrary`) kicked off background metadata enrichment (`_enrichArtistsInBackground` / `_enrichMetadataFast`) and playlist/local matching (`PlaylistService._labelsFromMetadata`), all of which called `metadata_god` — a Rust library loaded via `flutter_rust_bridge`. That native lib can contain instructions the old CPU doesn't support, and a native illegal-instruction crash cannot be caught by any Dart handler (the `runZonedGuarded` shell in `main.dart` only catches Dart exceptions — the same failure mode already documented for the `flutter_inappwebview` Windows plugin). Pinning `flutter_rust_bridge` to 2.11.1 (v13.0.13) fixed the Dart-level `ZONE ERROR` storm but unmasked the *native* calls.
  The read paths now go through a platform-gated helper (`_readLocalTag`) that uses `metadata_god` on Android only (where it is known to work and is the only writable tag path) and the pure-Dart `audio_metadata_reader` on Windows / iOS / web, with a session-disable flag that falls back to the pure-Dart reader on any native failure (so a future frb version skew degrades instead of crashing). The three tag-write paths (`_writeArtistTagIfPossible`, `fixSongMetadata`, `bulkFixArtistMetadata`) no-op gracefully where `metadata_god` is unavailable. Folder load no longer touches the native lib on Windows, so it cannot crash on low-end CPUs. Android behaviour is unchanged.


## 13.0.15+1278 — Player tag glitch + button-height clamp fixes

### Fixed
- **Player — genre filter chips overflowing the pinned header into the grid (the "people / blogs / music tags glitch").** The genre chips lived in a `Wrap` inside the search bar, which is in a **fixed-height pinned `SliverPersistentHeader`**. When the library had many genres (e.g. People, Blogs, Music, …) the wrapped chips exceeded the header's fixed height and — because nothing clipped them — painted *over* the media grid below. The chips are now a single horizontally-scrollable row (every genre stays reachable, none overflow), the pinned header child is wrapped in a `ClipRect` so any overflow is clipped instead of drawn over the body, and the header height was corrected to actually fit one search row + one chip row (mobile tightened from 128 → 72, desktop raised from 88 → 112).
- **Button-height cap clipping intentional taller buttons (regression from v13.0.12).** The unified button theme capped every button at 40 px tall with `maximumSize`, which clamped any button that deliberately sets a larger size via `styleFrom`: the circular play/pause button (`minimumSize 48` was clipped to 40) and the full-width Search / Preview + Download buttons (`padding 16` was clipped to 40, cropping their labels). Removed the `maximumSize` cap — keeping only the 40 *floor* — so sibling buttons stay consistent while genuinely taller buttons render at their real height again. The v13.0.14 empty-state buttons stay even because they're now all `OutlinedButton.icon` with 18 px icons.

### Confirmed (live run on the main PC)
- `deno-runtime: using provisioned Deno at …\deno.exe` — the v13.0.13 Deno lookup fix finds the existing binary (no re-download) on a real launch.
- No `metadata_god` `ZONE ERROR` on startup/library access — the `flutter_rust_bridge` 2.11.1 pin holds at runtime.

## 13.0.14+1277 — Player / empty-state UI fixes (Add Magnet, overlap, share)

### Fixed
- **Torrents empty state — Add Magnet is now an `OutlinedButton.icon`** matching its three siblings (was the emphasized `FilledButton.icon`), and all four empty-state action buttons plus "Go to Settings" now use 18 px icons so they sit cleanly inside the 40-tall unified button theme with no height clamp/glitch.
- **Player — first row / scrollbar hidden behind the pinned TabBar + search bar.** The `NestedScrollView` pinned headers overlapped the grid body, so the first media row and the scrollbar's top drew behind them (the classic `NestedScrollView` overlap gotcha). Added the canonical `SliverOverlapAbsorber` / `SliverOverlapInjector` pair and consolidated the TabBar + search bar into a single pinned sliver, so the grid (and its scrollbar) now render below the pinned header.
- **Player — Share button crowding the now-playing row on phones.** The inline Share `IconButton` is now hidden on phones (`width < 600`); Share is instead the first action in the existing 3-dot track menu — freeing the tight thumbnail / title / favourite / dislike / overflow row and removing the overlap glitch. Tablet/desktop keep the inline Share button.
- **Player empty tabs** (no library / no results) now also align below the pinned header via the same overlap-injector scroll view.

## 13.0.13+1276 窶・Low-End CPU Stability Fixes

### Fixed
- **metadata_god / flutter_rust_bridge codegen mismatch (library refresh crash).** metadata_god 1.1.0's shipped Rust library was built with frb codegen 2.11.1 while pub resolved frb runtime 2.12.0, so every library refresh / folder pick threw `ZONE ERROR: Bad state: metadata_god's codegen version (2.11.1) should be the same as runtime version (2.12.0)`. `flutter_rust_bridge` is now pinned to 2.11.1 as a direct dependency.
- **Deno provisioning could never succeed (yt-dlp "page needs to be reloaded").** `DenoRuntimeService.resolveOrDownload()` computed the destination as `deno-x86_64-pc-windows-msvc` (no `.exe`) while the official Windows zip extracts `deno.exe`, so download+extract succeeded but lookup failed and the whole zip was re-downloaded on every attempt. The provisioned-binary lookup now checks `deno.exe` / `deno` / `$destBase.exe` / `destBase` before and after extraction, and all outcomes (success and each failure mode) are surfaced via `SessionLogService.markOnce` keys (`deno-ok`, `deno-not_on_path`, `deno-download_failed_http_*`, `deno-verify_failed_*`, `deno-binary_not_found`, …).
- **Burst-pause log spam.** `downloadAll()` workers each logged "Pausing downloads — YouTube may be rate-limiting…" every 15 s for the whole pause (a 7-minute pause with 3 workers ≈ 84 identical entries). Pause/resume is now logged once per pause window with a single worker, and a "Burst pause over — resuming downloads" line follows.
- **Add Magnet button sizing.** The torrents empty state's `Add Magnet` button (kept as the emphasized primary `FilledButton.icon` action) is height-pinned via the unified button theme's `maximumSize`, fixing the mismatched/overflowing appearance.

## 13.0.12+1275 — Single Close Path & Ship Fixes

### Changed
- **Window-close handling consolidated into a single path.** `TrayService` no longer reacts to `onWindowClose` — `_MyAppState` in `app.dart` is the sole close path. This eliminates the v13.0.11 race at its root (previously `onTrayQuit`'s `exit(0)` could kill the process before app.dart's slower teardown flushed the session log; now there is only one teardown sequence). Geometry is saved explicitly on close, the tray icon is destroyed on quit so it doesn't linger, and a failed hide-to-tray now falls through to full teardown instead of leaving the window stuck open.

## 13.0.11+1274 — QA Fixes & yt-dlp Diagnostics

### Fixed
- **Share button now shares the actual audio file.** Was `Share.share(text)`, which only ever shared an app-store link and the song title. Now shares the real file via `SharePlus.instance.share(ShareParams(files: [XFile(item.path)]))` (matching the pattern in `home_screen.dart`), falling back to a text-only share only if the file isn't on disk (e.g. streamed).
- **Missing session logs on normal close — found the actual cause.** Two independent `WindowListener`s (`app.dart` and `TrayService`) both fire `onWindowClose`. `TrayService`'s `onTrayQuit` calls `exit(0)` immediately, which kills the process before `app.dart`'s slower `onWindowClose` (which poll for WebView2 teardown before flushing) ever reaches its flush line. Fixed by flushing the session log first in the `onTrayQuit` path, so whichever path wins the race, the log is already on disk.
- **Inconsistent button sizing — unified at the theme level.** No `FilledButtonTheme`/`OutlinedButtonTheme`/`ElevatedButtonTheme` existed, so different button types fell back to Material 3's per-type defaults (not guaranteed identical once icons are involved). One shared `_unifiedButtonStyle` applied to all three in both light and dark themes fixes it everywhere at once.
- **Mobile share-icon-over-badge glitch.** The now-playing card's track-info `Row` overflows on real phone widths; `Row`'s default `clipBehavior: Clip.none` paints overflowing children at their out-of-bounds position, landing the share icon on top of the type badge. Wrapped the `Row` in `ClipRect(clipBehavior: Clip.hardEdge)` (clean crop instead of overlap) and added `visualDensity: VisualDensity.compact` on the three icon buttons (share/favourite/dislike) to shrink their footprint.

### Added
- **Deno binary verification.** `DenoRuntimeService.resolveOrDownload()` now runs `deno --version` on every resolved binary (cached, system-found, and newly-downloaded) instead of only checking file existence. Logs which failure mode a low-end PC hits — "not found", "download failed (HTTP N)", or "exists but won't run" — so the next round can fix the specific cause rather than guessing.
- **yt-dlp Deno-unavailable warning.** When the Deno JS runtime can't be resolved (the silent failure path), a debugPrint now fires pointing to the deno-runtime logs, making "page needs to be reloaded" failures debuggable.

### Internal
- Node.js detection path (`_tryApplyNodeRuntime`) now logs when Node isn't found, so the Deno fallback is observable rather than silent.



### Fixed
- **Windows startup crash on older CPUs (root cause found via crash dumps).** `flutter_inappwebview`'s Windows plugin ships a binary containing BMI2 instructions (confirmed: `EXCEPTION_ILLEGAL_INSTRUCTION` at a fixed offset in `flutter_inappwebview_windows_plugin.dll`), and the app eagerly created a `WebViewEnvironment` at startup, crashing pre-2013/2015 CPUs instantly. The in-app browser on Windows now runs on WebView2 (`webview_windows`) via a platform adapter; `flutter_inappwebview` remains for Android/iOS only. Android behaviour is unchanged.
- **Headless WebView JS solver race.** `WebViewEJSSolver._ensureReady()` now memoizes its initialization as a single in-flight Future (same pattern as the v13.0.8 database fix), so concurrent YouTube metadata calls can't race two headless WebView inits.

### Changed
- **All player thumbnails are 16:9** (same width as before, height derived from it): track-list rows were square, library grid cards filled the whole card; both are now 16:9, with the grid card shape retuned to match.

### Added
- **Session diagnostics for slow starts.** Timestamped startup breadcrumbs (flavor init, permissions, ads, media kit, window ready, first frame) are written to `session_log_<timestamp>.log` in the documents folder on every normal app close - not only on crashes - so slow-start reports come with real phase timings. Crash/error paths now flush the same log.

## 13.0.8+1271 — Low-End Stability & Playlist Reliability

### Fixed
- **Crash entering Torrents tab on low-end PCs.** Memoized the vault DB open as a single in-flight Future so concurrent first callers don't race two opens; `TorrentsScreen` now awaits `VaultBootstrap.ensureInitialized()` before its first DB access.
- **yt-dlp self-update hard-failing on slow machines.** The Windows binary-replace in `updateYtDlp` now retries with backoff on transient file locks; a self-update failure falls back to one plain retry with the existing binary before surfacing an error.
- **Android playlist import returning 0 of ~790.** Added per-video logging, raised the inter-page idle timeout to 180s, and retry stops when an attempt makes no net progress.

### Internal
- CI release workflow verifies the built APK is not debug-signed and hard-fails if signing secrets are absent.

## 13.0.6+1269 — Reliability Pass v2 Completion + Monetization Wiring

### Fixed
- **Android playlist loading** — headless WebView JS challenge solver (`WebViewEJSSolver`) replaces Deno on mobile; Deno stays desktop-only.
- **Orphaned downloads on cancel** — cancelling no longer leaves behind the intermediate `.mp4`/`.webm` yt-dlp was writing; cleanup now scans for all files sharing the output stem.
- **Reload errors during update cooldown** — a "page needs to be reloaded" failure now gets a plain retry even while the 2-hour self-update cooldown is active, instead of failing with zero retries.
- **Reload-error bursts** — 3+ reload errors within 5 minutes are treated as a YouTube-side throttle: the queue pauses for 7 minutes with a visible message instead of hammering into it.
- **AdMob** — native ads are now theme-aware; new placements in Watched Playlists and the Support screen.
- **Torrent background survival** — the Android torrent service runs in foreground mode so the OS won't kill it in the background.

### Added
- **Vault** — database encryption key is now provisioned via `flutter_secure_storage` and wired into both bootstrap paths.
- **Ollama (Android)** — clearer connectivity UX: desktop-only buttons hidden, network panel with `OLLAMA_HOST=0.0.0.0` guidance, actionable error messages.
- **Play build** — "Advanced build on GitHub" link added to the Support screen.
- **Motion tokens** adopted across onboarding; shared `EmptyState` widget reused in the vault torrents screen.

## 13.0.5+1268 — yt-dlp / youtube_explode_dart Reliability Pass v2

### Added
- **DenoRuntimeService** — shared Deno provisioning for both yt-dlp's `--js-runtimes` and youtube_explode_dart's `DenoEJSSolver`, so a single provisioned binary serves both.
- **Bigram similarity fallback** in `_titlesMatch` for CJK and other non-space-delimited scripts.

### Fixed
- **Android playlist loading** — wired `DenoEJSSolver` into the `YoutubeExplode` instance serving playlist loads; raised inactivity timeout 25s → 60s and made the retry loop continuation-aware.
- **CJK title matching** — character-bigram Dice-coefficient fallback so Japanese/Chinese titles no longer lose all matching tolerance.
- **Japanese author names** — broadened `_artistFromFilename` to recognize `/`, `_`, `／`, and `【】` tag prefixes; switched local-library tag read from `audio_metadata_reader` to `MetadataGod` for consistency.
- **"Could not check for updates"** — cached the latest-release check for an hour (SharedPreferences) and branched on HTTP 403 with a rate-limit-specific message.
- **"yt-dlp missing" during downloads** — status indicator now distinguishes checking / transient error / genuinely not configured.
- **Dead code** — deleted `yt_dlp_updater.dart` and `yt_dlp_update_controller.dart` (never called).

## 13.0.4+1267 — yt-dlp "page needs to be reloaded" Fix

### Fixed
- **Self-updating yt-dlp on "page needs to be reloaded" / UNPLAYABLE failures.** When a download fails with YouTube's "The page needs to be reloaded", `UNPLAYABLE`, or bot/age-check errors, the app now automatically updates the yt-dlp binary (throttled to once per 2 hours per session) and retries the download once. YouTube-side extractor/player (nsig/SABR) changes are patched on stable releases within days, so a refresh routinely restores downloads that a pinned binary was failing.
- **Bundled a JavaScript runtime (Deno) for yt-dlp.** Modern yt-dlp needs an external JS interpreter to evaluate YouTube's signature code; without one it emits "page needs to be reloaded" / UNPLAYABLE errors. The app now detects a system Deno/Node install or lazily downloads a standalone Deno binary (into the app support dir) and passes it to yt-dlp via `--js-runtimes deno:...`.
- **Kept the existing non-fatal fallback updater** (best-effort on boot) and made the download-path auto-update cooldown-aware so a failed burst doesn't hammer the GitHub API.

### Notes
- Also includes the v13.0.3 changes: cinematic view (and its ambient shader) fully removed.

## 13.0.3+1266 — Remove Cinematic View

### Removed
- **Cinematic view and all related code removed.** Deleted the ambient shader, the cinematic view screen, the ambient-scene widget, and the cinematic thumbnail renderer. The player now opens the standard fullscreen album/song view instead of the ambient shader. Removing it simplifies the player and avoids GPU/driver-specific rendering artifacts on a range of desktop hardware.

## 13.0.2+1265 — DLL Linking & Download Fix Release

### Fixed
- **Windows launch crash**: Removed the `SetDllDirectoryW`-based DLL subfolder mechanism that moved plugin DLLs into `dlls/` at packaging time. The Windows loader loads the executable's direct import dependencies before `wWinMain` runs, so `SetDllDirectoryW` — called inside `wWinMain` — could not resolve DLLs the loader needed during process startup, preventing the app from launching. All plugin DLLs now ship flat in the release root directory.
- **YouTube `androidVr` PO-token regression**: Replaced `androidVr` with `tv` in every youtube_explode_dart client list and in the yt-dlp `--extractor-args` passed to yt-dlp. YouTube now requires a GVS PO token for `androidVr` on anything above 360p, which was silently blocking HD downloads on all platforms. The `tv` client returns playable streams without PO tokens and works on desktop, Android, and iOS.
- **Windows release packaging**: Removed the `organize_dlls.ps1` invocation from the CI release workflow so DLLs are never moved into a subfolder that the Windows loader can't see at startup.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 13.0.1 — Regression Fix Release

### Fixed
- **Cinematic view** rebuilt with a new deterministic ambient shader and a non-blurred transport overlay. This fixes the solid white/grey layer that appeared when the controls faded in, the black top bar, and the overly flickering starfield.
- **Windows playback failures** caused by the YouTube `androidVr` client being selected on desktop. The fallback client list now avoids `androidVr` on Windows and prefers `tv`/`safari`/`ios`/`web` instead.
- **Windows release clutter:** plugin DLLs are now moved into a `dlls/` subfolder next to the executable, while the executable and its direct runtime dependencies remain in the root.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 13.0.0 — Linux Download Fix & Target API 36

### Fixed
- Linux and macOS builds now download the correct self-contained yt-dlp binary instead of a variant that silently required a system Python 3.11+ interpreter. This was the cause of "can't download playlists" and similar reports from Linux Mint users.
- `targetSdkVersion` raised to 36 (Android 16) for Play Store compliance.
- `build_release.sh` no longer hardcodes a stale version/build number; it now reads the version from `pubspec.yaml` like every other part of the build does, and sets the `GITHUB_RELEASE` build flag correctly for both flavors.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 10.7.1 — Fixed Windows Crash

### Highlights
- Fixed a crash where the Windows exe would not launch properly.

### Notes
- See [docs/releases/latest.md](docs/releases/latest.md) for the current release summary.

## 5.2.0 — Bug Fix & Stability Release

### Fixed
- Android Share button now works with content:// URIs
- "Open Folder" button visible on Android queue items
- Browser shows WebView2 download link on older Windows PCs
- Linux AppImage for better compatibility on older distros

### Notes
- Bumped version to 5.2.0; see [docs/releases/latest.md](docs/releases/latest.md) for the current release notes.

## 5.0.0 — Production Polish Release

### New Features
- **Chromecast & AirPlay discovery** — mDNS-based scanning discovers Google Cast and AirPlay devices alongside DLNA renderers
- **Desktop window management** — window size, position, and geometry persist across sessions; minimum size enforced
- **Desktop media keys** — play/pause, next, previous, and Ctrl+Space shortcuts via CallbackShortcuts
- **Directory watcher** — media library auto-refreshes when files are added or removed on desktop
- **Download progress banner** — Android foreground notification shows remaining downloads during batch operations
- **Browser tab** — re-added as a first-class quick-link entry
- **HiAnime extraction** — difficult-site headers, cookies, and force-generic-extractor retry for yt-dlp

### Improvements
- **Virtualised player lists** — All and Favourites tabs use `ListView.builder` for large libraries
- **SafeArea audit** — all major screens respect system insets (notch, status bar, nav bar)
- **Accessibility** — player controls now have Semantics labels and Tooltips
- **Centralised strings** — `Strings` constants class for UI text
- **Code quality** — null-safe Range header parsing, race-condition-safe local media server, kIsWeb guards
- **Mobile nav labels** — shortened to fit 5-tab layout ("Search+", "Import")
- **URL bar** — single-line with ellipsis overflow, tap navigates to tab switcher
- **Miner auto-resume** — mining state persists across app restarts via SharedPreferences
- **Battery guard** — now pauses and resumes the native miner subprocess, not just isolate tasks
- **Error recovery** — exponential backoff on miner restarts (3 s → 6 s → 12 s), manual Retry button after max attempts
- **First-run consent dialog** — one-time prompt explaining mining before it can be enabled
- **Wallet constants** — extracted to `wallet_constants.dart` for single-source-of-truth

### Fixes
- `.gitignore` rewritten from corrupted UTF-16LE encoding
- Force-unwrap crashes in local_media_server.dart eliminated
- BrowserScreen widget test removed (requires platform InAppWebView)

### Internal
- Added `multicast_dns: ^0.3.2+1` dependency
- Added `FOREGROUND_SERVICE_DATA_SYNC` and `POST_NOTIFICATIONS` Android permissions
- Unit tests for QueueItem model and Strings constants

## 4.0.0 — Browser Overhaul

### Breaking Changes
- Removed Screencast tab entirely (replaced by in-browser video casting)
- Browser module completely rebuilt with `flutter_inappwebview`

### New Features
- **In-App Browser** rebuilt with full-featured WebView (JavaScript, DOM storage, caching)
- **Ad-Block Engine** — fetches EasyList, blocks ads and popups
- **Video Detection** — detects video streams (M3U8, MP4, MPD) via JS injection + network interception
- **Cast to TV** — cast detected videos to Chromecast and DLNA devices
- **Favourites** — full bookmarks manager with folders, drag-to-reorder, search, bulk operations
- **History** — date-grouped browsing history with search and swipe-to-delete
- **Incognito Mode** — separate WebView with no history/cookies persistence
- **New Tab Page** — premium home page with quick access, favourites, and recent history
- **Browser Settings** — search engine, ad-block, text size, dark mode, casting preferences
- **Multi-Tab Support** — tab manager with screenshots and smooth transitions
- **Cast Mini Bar** — persistent playback controls while casting

### Removed
- Screencast tab and all associated native code (MpegTsMuxer, ScreenCaptureService)
- Screencast-related Android permissions (RECORD_AUDIO, FOREGROUND_SERVICE_MEDIA_PROJECTION)
