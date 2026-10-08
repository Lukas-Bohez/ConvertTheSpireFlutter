# Microsoft Store

The Store version is the Windows app with every feature of the GitHub build.
It is packaged as an MSIX that Microsoft signs, so there is no SmartScreen
warning and no code-signing certificate to pay for. What differs from the
GitHub build:

| | GitHub build | Store build |
|---|---|---|
| Updates | the app updates itself from GitHub | the Store updates it; the app's own update check and "Update now" are off |
| FFmpeg, yt-dlp, Deno | downloaded on first use | come in the package (`ffmpeg\`, `yt-dlp\`, `deno\` next to the exe); nothing is downloaded at start. yt-dlp can still be updated from Settings |
| Colours | all unlocked | all unlocked (the **All colours** add-on is free) |
| "Rate" | opens GitHub | opens the Store's rating dialog; after five starts the app asks once |

All of it hangs on one build flag, `--dart-define=MS_STORE_BUILD=true`
(`kMsStoreBuild` in `lib/src/config/build_flags.dart`). The Store's purchase
and rating dialogs are reached through `windows/runner/store_purchases.cpp`
(Dart side: `lib/src/services/ms_store_service.dart`).

## Building the package

GitHub → **Actions** → **Microsoft Store package** → **Run workflow**, with the
three values from Partner Center (step 2 below). It takes about 25 minutes. The
run's **microsoft-store-msix** artifact is a zip with
`ConvertTheSpireReborn.msix` in it: unzip it, and upload the `.msix`.

The values can be saved once as repository variables instead (Settings →
Secrets and variables → Actions → Variables): `MSSTORE_IDENTITY_NAME`,
`MSSTORE_PUBLISHER`, `MSSTORE_PUBLISHER_DISPLAY_NAME`, and optionally
`MSSTORE_DISPLAY_NAME`. Then the workflow needs no input.

The package's version is the one in `pubspec.yaml` with `.0` added
(`15.2.0` → `15.2.0.0`). Every new submission needs a higher version than the
last, so bump `version:` in `pubspec.yaml` before building an update.

### On your own PC: `microsoft-upload\`

`scripts\make_store_upload.cmd` does the same on a Windows PC with Flutter and
Visual Studio, and puts everything for the submission in one folder,
`microsoft-upload\` in the repository (git ignores it):

| | |
|---|---|
| `ConvertTheSpireReborn.msix` | the package (Packages) |
| `screenshots\` | the 1920×1080 screenshots (Store listings) |
| `app-tile-300.png` | the 1:1 app tile icon (Store listings) |
| `listings\<language>.md` | each language's texts, field by field |
| `store-import\` | with `-ListingCsv`: the folder to import (the filled CSV, the screenshots and the app tile, for every language) |
| `HOW-TO-UPLOAD.txt` | what goes where |

The first time, with the three identity values (they are kept in
`microsoft-upload\identity.json` for the next runs):

    scripts\make_store_upload.cmd -IdentityName <Package/Identity/Name> -Publisher "CN=..." -PublisherDisplayName "<Package/Properties/PublisherDisplayName>"

After that, `scripts\make_store_upload.cmd` alone. To fill the listing CSV
exported from Partner Center with all 18 languages, without building:

    scripts\make_store_upload.cmd -ListingsOnly -ListingCsv "%USERPROFILE%\Downloads\<the export>.csv"

## First submission, step by step

### 1. Reserve the name

Partner Center → **Apps and games** → **New product** → **MSIX or PWA app**
(not "EXE or MSI app"). The reserved name is **Convert The Spire Reborn**
(capital T; Store ID 9MT834RPF8ZP), the workflow's default `display_name`.
The package's name must be the reserved one exactly: reserve another name
and the workflow's `display_name` must be that name.

### 2. Copy the package identity

The new app → **Product management** → **Product identity**. Copy:

* **Package/Identity/Name** → workflow input `identity_name`
* **Package/Identity/Publisher** (starts with `CN=`) → `publisher`
* **Package/Properties/PublisherDisplayName** → `publisher_display_name`

Run the workflow with them (see above). Carry on with step 3 while it runs.

### 3. Pricing and availability

* **Markets:** all.
* **Visibility:** Public audience, discoverable in the Store.
* **Pricing:** **Free**, no free trial. (Why: see "Earning from it" below.)
* **Publish date:** as soon as it passes certification.

### 4. Properties

* **Category:** Photo & video. (Music is the other good fit.)
* **Privacy policy URL:** `https://quizthespire.com/privacy`. Add the
  "Microsoft Store version" paragraph from `PRIVACY.md` to that page too.
* **Website:** `https://github.com/Lukas-Bohez/ConvertTheSpireFlutter`
* **Support contact info:** `https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/issues`
* **System requirements:** leave the defaults; x64 only.
* **Product declarations:** tick "Customers can install this app to alternate
  drives or removable storage". Leave the others unticked.

### 5. Age ratings

Fill in the IARC questionnaire truthfully. It matters for these answers:

* Category: **All other app types**.
* The app has a **built-in web browser** with unrestricted internet access,
  and it **downloads files from the internet**: answer **yes** to both. This
  usually gives 12+ / PEGI 12 and is the honest rating for a browser.
* Users interact or share content with each other: **yes** (Watch Together,
  torrents).
* No violence, gambling, location sharing or purchases of real-world goods.
  Digital purchases: **no** (the All colours add-on is free).

### 6. Packages

Upload `ConvertTheSpireReborn.msix`. Partner Center checks it at once; it
fails here when the identity values do not match the reserved app (re-run the
workflow with the right ones).

**Device families: Windows 10/11 Desktop only.** Untick Xbox, Mobile,
HoloLens and the others wherever Partner Center offers them. The package is
a Win32 desktop app (`Windows.Desktop`, full trust), which only runs on PCs:
Xbox runs UWP apps only, and Flutter cannot build those; Windows 10 Mobile is
gone. A device family ticked that the package does not support fails
certification or is ignored.

### 7. Store listings (18 languages)

The package declares the app's 18 languages, so Partner Center has a listing
for each. The texts for all of them are in
[`store-listing/`](store-listing/README.md): fill them in with one CSV
import (`scripts/store_listing.py fill`), or copy them per language. The
English texts are also below. Screenshots: at least one,
1366×768 or larger. The ones in `docs/screenshots/store/` are made for this
(1920×1080: Home, the player, a video with subtitles, the large view, loop
parts, Torrents, and the player in the dark theme). The **1:1 app tile icon
(300×300)** is optional; use `docs/screenshots/store/app-tile-300.png`.
**Trailers:** add `microsoft-upload/trailer/trailer.mp4` with its thumbnail;
how it is made and uploaded is in [store-trailer.md](store-trailer.md).

### 8. Submission options

**Restricted capabilities** asks why the app needs `runFullTrust`. Paste:

> Convert the Spire Reborn is a Win32 desktop app (Flutter). It needs full
> trust to run the FFmpeg, yt-dlp and Deno programs that come in the package
> as separate processes (to download and convert media), to accept incoming
> BitTorrent connections, to run a local media server for casting to TVs on
> the user's network, and to read and write media in the folders the user
> picks.

**Notes for certification:**

> No account or sign-in is needed. To try the main features: Home → paste a
> link to a video (for example a Creative Commons video) → pick MP3 or MP4 →
> Download. Convert tab → pick an audio or video file → convert. Torrents tab
> → add a magnet link of a legal torrent, such as an Ubuntu ISO. The app is
> open source (GPL-3.0): https://github.com/Lukas-Bohez/ConvertTheSpireFlutter.
> The free "All colours" add-on only unlocks cosmetic colour themes, which
> the app already has unlocked.

Then **Submit to the Store**. Certification usually takes 1 to 3 working days.

### 9. The All colours add-on

The new app → **Add-ons** → **Create a new add-on**:

* **Product type:** Durable. **Product lifetime:** Forever.
* **Product ID:** `get_all_themes`, exactly: the app finds the add-on by it.
* **Pricing:** free. Selling it needs a company BIC/SWIFT code in the
  payout profile, which Google Play does not ask for; the app unlocks every
  colour from install anyway.
* **Properties → Content type:** Electronic software download.
* **Store listing:** title "All colours"; description "Unlocks all 28 colour
  themes at once, and supports the app's development."

Submit it. It can be created and submitted before the app is out; it goes
live with or after the app. The app does not offer it: all colours are
unlocked from install, as in the GitHub build.

## Earning from it

* **Free app, paid extra.** A free app gets far more installs, and installs
  and ratings are what move an app up in Store search. The GitHub build
  stays free with the same features, so a price on the Store version mostly
  buys fewer users. The money comes from donations: the **All colours**
  add-on is free, as selling it needs a company BIC/SWIFT code.
* **Donations stay in the app.** Buy Me a Coffee and GitHub Sponsors in the
  Support tab are allowed for apps that are not games, and Microsoft takes no
  share of them.
* **Ratings.** From the fifth start on, after something went well (a
  finished download, a video played), the app asks once for a Store rating;
  good ratings lift the listing.
* **Expect a slow start.** A new Store app gets a few downloads a day until
  it has ratings. The listing's search terms and screenshots make the
  biggest difference early on.
* **Later, if wanted:** more add-ons (a "supporter" tip, extra themes), or a
  price with a free trial once the listing has ratings.

## Listing text

**Product name:** Convert The Spire Reborn

**Short description** (shown at the top of the listing):

> Download and convert video and music, play it, cast it to your TV, and
> download torrents. Free, open source, no account, no tracking.

**Description:**

> Convert The Spire Reborn is an all-in-one media app for Windows: a
> downloader, converter, player and torrent client in one window.
>
> DOWNLOAD
> • Save videos and music from YouTube and over 1,800 other sites, as MP4,
>   MP3, M4A and more, in the quality you pick.
> • Whole playlists at once, with titles, artwork and tags filled in.
> • A built-in browser finds the media on a page for you.
>
> CONVERT
> • Convert audio and video between 27+ formats with FFmpeg, right on your
>   PC. Nothing is uploaded.
>
> PLAY AND CAST
> • A media player for your music and videos, with playlists.
> • Cast to TVs and speakers on your network (DLNA/UPnP).
> • Watch Together: watch the same video in sync with friends.
>
> TORRENTS
> • A full BitTorrent client: magnet links and .torrent files, seeding with
>   ratio limits, and making and sharing your own torrents.
>
> PRIVATE BY DESIGN
> • No account, no ads, no analytics, no tracking. Everything stays on your
>   PC.
> • Open source (GPL-3.0) on GitHub.
>
> Available in 18 languages. Please only download content you have the right
> to download.

**Product features** (one per line):

> Download video and music from 1,800+ sites
> Convert between 27+ audio and video formats
> Whole playlists with tags and artwork
> Media player with playlists
> Cast to TVs and speakers (DLNA/UPnP)
> Watch videos in sync with friends
> BitTorrent client with magnet links and seeding
> Built-in browser that finds media on a page
> No account, no ads, no tracking
> Open source, in 18 languages

**Search terms** (up to 7): `video downloader`, `mp3 converter`,
`music downloader`, `torrent`, `media player`, `video converter`, `dlna`
(no other company's brand names here: the Store can reject those).

**What's new in this version:** written for each release, in all 18
languages, in [`store-listing/`](store-listing/README.md) (the `releaseNotes` of
`listings.json`).

**Copyright and trademark info:** © 2026 Oroka Conner

**Additional license terms:** "Free software under the GNU GPL v3:
https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/blob/main/LICENSE"

## If certification says no

Microsoft's policies have no rule against YouTube downloaders, and the Store
lists several, but YouTube's own terms forbid downloading except where
YouTube offers it, and a certifier can still object (policy 11.x,
intellectual property). If the report cites that, the fix is a build with
the YouTube features hidden (the Google Play build's feature set), which is a
small change to `kMsStoreBuild`. Read the report's exact policy number first:
a crash or a missing screenshot is fixed differently.
