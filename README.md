# Convert the Spire Reborn

## What is this?

Hey everyone! If you remember the old web-based Convert the Spire downloader, you probably know that YouTube eventually blocked our server's IP. To keep the project alive and better than ever, I built **Convert the Spire Reborn**.

It is a fully native Flutter app that handles all your media downloading, playlist converting, and playback right on your own device. It started out as a simple, ad-free tool to bulk-download massive YouTube playlists, but it has grown into a full media suite. You can now download from multiple sites, cast to your TV, and easily manage your local library.

Because it runs natively on Windows, Linux, Android, and macOS, there is no heavy Electron bloat and no browser overhead.

---

## Features

### The Core Stuff

* **YouTube Search & Download:** Browse and download straight via yt-dlp. You can easily grab videos up to 1080p or audio at 320 kbps.
* **Massive Playlist Support:** The main reason this project exists! Paste a playlist link and bulk-download the whole thing, completely ad-free.
* **Multi-Site Engine:** It is not just YouTube anymore. Anything yt-dlp supports (over 1,800 sites) goes through the same seamless pipeline.
* **Built-in Media Player:** Play your audio and video directly in the app. It comes with playlists, queue management, and library tracking powered by `media_kit`.
* **File Converter:** Convert between 27+ formats, covering documents, images, archives, and media files.
* **DLNA & UPnP Casting:** Cast your downloaded media to any compatible smart TV or speaker on your local network.
* **Smart Browser:** The built-in browser handles URLs effortlessly. Bare domains, IP addresses, and plain search queries all work without manual formatting.

---

## Why Native?

If you are curious about the tech stack, the app is built to be fast, lightweight, and efficient:

* **Lightning Fast:** Flutter compiles directly to native code, meaning startup takes milliseconds compared to the heavy load times of Electron apps.
* **Low Memory:** It uses around 80 MB of memory instead of hoarding hundreds of megabytes like a Chromium process.
* **Network Power:** Raw UDP and TCP sockets allow for seamless DLNA casting and local device discovery, which web wrappers simply cannot do.
* **Battery Smart:** The native battery plugins let the app throttle intense background tasks if your device is running low on juice.

### Architecture Highlights

```text
┌─────────────────────────────────────────────────────────────┐
│                       Flutter UI                            │
│  HomeScreen (rail nav) -> 13 screens (Search, Player, ...)  │
├─────────────────────────────────────────────────────────────┤
│                    State Management                         │
│  AppController (ChangeNotifier + Provider)                  │
├───────────────┬─────────────────┬───────────────────────────┤
│  Services     │  Services       │  Services                 │
│               │                 │                           │
│ YtDlpService  │ DlnaDiscovery   │ ComputationService        │
│ DownloadSvc   │ DlnaControl     │ CoordinatorService        │
│ ConvertSvc    │ LocalMediaSvr   │ (WebSocket + Isolates)    │
│ PlaylistSvc   │ (SSDP + HTTP)   │                           │
├───────────────┴─────────────────┴───────────────────────────┤
│                    Platform Layer                           │
│  dart:io * media_kit * battery_plus * webview_windows       │
│  RawDatagramSocket * HttpServer * Isolate.run               │
└─────────────────────────────────────────────────────────────┘

```

---

## How to Get It

You can download the app directly from our site at [quizthespire.com](https://quizthespire.com/) or head over to the [GitHub Releases](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases) page for the pre-built binaries.

* **Windows:** Download the `.zip`, extract it, and run the `.exe`.
* **Android:** Grab the `.apk` and side-load it on your device.
* **Linux:** Download the Linux package. Make sure you have `libmpv` installed on your system!
* **macOS:** Untested currently, but you can easily build it from source.

---

## Opt-In Mining (How I Keep the Lights On)

To help fund the development of the app, I included a "Support" tab. This allows you to voluntarily donate your idle CPU cycles to mine QUBIC tokens. All earnings go directly to my developer wallet.

A few important things to know:

* **It is 100% opt-in.** It will never run unless you explicitly consent and turn it on.
* **It is battery-aware.** The miner pauses automatically if your battery drops below 30% and resumes when plugged in.
* **Easy to stop.** You can disable it with a single tap at any time.
* **Transparent.** The wallet address, pool stats, and source code are fully visible for anyone to audit.

---

## Contributing

I would love your help! Feel free to open an issue or submit a pull request.

1. Fork the repo.
2. Create your feature branch.
3. Make sure your code passes: `flutter analyse`.
4. Commit and open a PR!

## License & Support

This project is licensed under the GNU General Public License v3.0.

If this tool has saved you time and you want to support me:

* Buy me a coffee: [Oroka Conner](https://buymeacoffee.com/orokaconner)
* Website: [Convert the Spire](https://quizthespire.com/)
