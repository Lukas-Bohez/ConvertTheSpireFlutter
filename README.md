# Convert the Spire Reborn

[![CI/CD](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Flutter](https://img.shields.io/badge/Flutter-3.27.4-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20Android%20%7C%20macOS-brightgreen)](#downloads)

## What is this?

Convert the Spire Reborn is a Flutter app that handles media downloading, conversion, playback, and DLNA casting in one place. It runs on Windows, Linux (older distros only, around Ubuntu 20.04), Android, and experimentally on macOS. No Electron, no browser overhead.

It started as a personal media tool and grew from there. The core was already functional before a second round of development added multi-site downloading, DLNA casting, a smarter browser, and an opt-in distributed computing feature.

---

## Features

### Core features

- **YouTube search & download** — search, browse, and download via yt-dlp, up to 1080p video or 320 kbps audio
- **Multi-search** — search across multiple sites at once and compare results
- **File converter** — 27+ formats across four categories:
  - Documents: PDF, EPUB, DOCX, HTML, TXT, CSV, JSON, XML, YAML, MD
  - Images: PNG, JPG, BMP, GIF, TIFF, WebP, ICO
  - Archives: ZIP, TAR.GZ, CBZ
  - Media: MP3, WAV, AAC, FLAC, OGG, MP4, MKV, WEBM
- **Media player** — audio/video playback via `media_kit` (libmpv), with library management, playlists, and queue
- **File organisation** — duplicate detection via streaming MD5, cross-filesystem moves, smart folder structure
- **Bulk import** — parse a track list and batch-download from YouTube
- **Statistics** — listening history with `fl_chart` charts
- **Built-in browser** — YouTube browsing with incognito mode (Windows only, via `webview_windows`)
- **Notifications** — download progress and completion alerts
- **Theming** — dark/light/auto, onboarding tour, configurable settings

### Newer features

#### Smart browser URL handling
The in-app browser normalises URLs before loading them. Bare domains (`hianime.to`), IP addresses (`192.168.1.1`), ports (`localhost:8080`), and plain search queries all work without any manual prefixing. YouTube detection covers standard watch links, Shorts, embeds, live streams, and `music.youtube.com`.

#### Multi-site download engine
Downloads aren't limited to YouTube anymore. Anything yt-dlp supports (~1,800 sites) goes through the same pipeline, with progress reporting, human-readable error messages for geo-blocks, private content, and rate limits, plus automatic format conversion via FFmpeg.

#### DLNA / UPnP casting
Cast to any DLNA-compatible TV, speaker, or receiver on your local network. SSDP scans for devices automatically, there's a manual IP fallback for anything that doesn't respond to multicast, and a local HTTP server serves files with Range request support so you can seek. Play, pause, stop, and volume go through UPnP AVTransport SOAP calls.

#### Distributed computing (opt-in)
Donate spare CPU cycles to a coordinator server for open-data workloads. Uses WebSockets with exponential-backoff reconnection, Dart isolates for sandboxed parallel computation, and automatically pauses when your battery drops below 30% or the device is unplugged. There's a gamified UI with contributor tiers (Bronze through Diamond) and a live task dashboard.

---

## Why native?

- **Startup** — ~200 ms AOT-compiled vs 2-5 s for Electron (JS parse + hydrate)
- **Memory** — ~80 MB vs 300-600 MB with a full Chromium process
- **File system** — direct `dart:io` access, not sandboxed
- **Network** — raw UDP/TCP sockets for SSDP/DLNA; Electron can't do UDP or multicast at all
- **CPU isolation** — `Isolate.run` gives true parallelism; Web Workers have serialisation overhead
- **Battery API** — `battery_plus` native plugin vs `Navigator.getBattery()` which is Chrome-only

Flutter compiles to native ARM/x64 binaries via Dart's AOT compiler. No JavaScript runtime, no DOM, no GC pauses. That matters for DLNA (HTTP range requests need to respond fast) and for the compute feature (isolate pool throughput).

---

## IoT / embedded relevance

A few patterns here show up in embedded and IoT work too:

- **SSDP / UPnP discovery** is the same multicast protocol used by smart-home hubs, Chromecast, and Sonos. The `DlnaDiscoveryService` sends M-SEARCH datagrams to `239.255.255.250:1900` and parses XML device descriptors, the same way a home-automation controller would.
- **Local HTTP media server** serves files from disk with Range header support so any network device can stream and seek. Same pattern as Plex, Jellyfin, or NAS firmware.
- **Battery-aware scheduling** monitors battery state and throttles work, directly applicable to battery-powered IoT gateways.
- **Isolate-based computation** gives memory-isolated parallelism without shared-state bugs, similar to separate task contexts in an embedded RTOS.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter UI                           │
│  HomeScreen (rail nav) → 13 screens (Search, Player, …)     │
├─────────────────────────────────────────────────────────────┤
│                     State Management                        │
│  AppController (ChangeNotifier + Provider)                  │
├───────────────┬─────────────────┬───────────────────────────┤
│  Services     │  Services       │  Services                 │
│               │                 │                           │
│ YtDlpService  │ DlnaDiscovery   │ ComputationService        │
│ DownloadSvc   │ DlnaControl     │ CoordinatorService        │
│ ConvertSvc    │ LocalMediaSvr   │ (WebSocket + Isolates)    │
│ PlaylistSvc   │ (SSDP + HTTP)   │                           │
├───────────────┴─────────────────┴───────────────────────────┤
│                   Platform Layer                            │
│  dart:io · media_kit · battery_plus · webview_windows       │
│  RawDatagramSocket · HttpServer · Isolate.run               │
└─────────────────────────────────────────────────────────────┘
```

Video playback uses `media_kit` backed by `libmpv`. On Android, `media_kit_libs_android_video` bundles the native libraries into the APK, so make sure you grab the arm64 APK (`ConvertTheSpireReborn.apk`).

### Key files

- `lib/main.dart` — entry point
- `lib/src/app.dart` — root widget, theme, Provider wiring
- `lib/src/state/app_controller.dart` — central state (queue, settings, downloads)
- `lib/src/screens/home_screen.dart` — navigation rail with 13 tabs
- `lib/src/screens/browser_screen.dart` — in-app browser and URL normalisation
- `lib/src/screens/compute_screen.dart` — distributed compute UI
- `lib/src/services/download_service.dart` — multi-site download engine
- `lib/src/services/dlna_discovery_service.dart` — SSDP device discovery
- `lib/src/services/dlna_control_service.dart` — UPnP AVTransport SOAP control
- `lib/src/services/local_media_server.dart` — HTTP file server with Range support
- `lib/src/services/computation_service.dart` — isolate pool for distributed tasks
- `lib/src/services/coordinator_service.dart` — WebSocket coordinator client

---

## Downloads

Pre-built binaries are on the [Releases](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases) page.

- **Windows x64** — `ConvertTheSpireReborn.zip`, extract and run `ConvertTheSpireReborn.exe`
- **Android arm64** — `ConvertTheSpireReborn.apk`, side-load on Android 6.0+
- **Linux x64** — `linux.zip`, requires libmpv at runtime; tested on older distros (around Ubuntu 20.04)
- **macOS** — untested, build from source; not yet in CI but probably works

---

## Building from source

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) **3.27.4** (stable channel)
- Git
- Platform toolchain (see below)

### Quick start

```bash
git clone https://github.com/Lukas-Bohez/ConvertTheSpireFlutter.git
cd ConvertTheSpireFlutter
flutter pub get
```

### Windows

```bash
flutter build windows --release
# Output: build\windows\x64\runner\Release\
```

Optional MSIX packaging (unsigned):
```bash
dart run msix:create
```

### Linux

```bash
sudo apt install clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-9-dev \
  libmpv-dev mpv libass-dev

flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

WSL users: symlinks break on NTFS mounts, use the included script instead:

```bash
wsl -e bash scripts/build_linux_wsl.sh
```

### Android

```bash
# Debug
flutter build apk --debug

# Release (split per ABI for smaller downloads)
flutter build apk --release --split-per-abi
```

Make sure `media_kit_libs_android_video` is in `pubspec.yaml` or the native libmpv libraries won't be bundled and video will fail on some devices. Avoid the single fat APK path if you can.

For signed release builds, create `android/key.properties`:
```properties
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=YOUR_ALIAS
storeFile=path/to/keystore.jks
```

### macOS (untested)

macOS isn't in the CI pipeline yet and the build hasn't been formally tested. That said, `flutter build macos --release` should work fine since there's nothing platform-specific blocking it. If you try it and run into issues, open an issue.

```bash
flutter build macos --release
```

You'll need Xcode and the macOS Flutter toolchain set up. The `media_kit` libraries should be handled automatically by the package.

---

## CI/CD pipeline

One [GitHub Actions workflow](.github/workflows/ci.yml), five jobs:

```
push/PR to main → quality → build-windows →
                             build-linux   → release (on v* tags)
                             build-android →
```

- **quality** (`ubuntu-latest`) — `flutter pub get`, `flutter analyse`, conditional `flutter test`
- **build-windows** (`windows-latest`) — build release, upload artefact
- **build-linux** (`ubuntu-latest`) — install apt deps, build release, upload artefact
- **build-android** (`ubuntu-latest`) — JDK 17, optional keystore from secrets, build split APKs, upload artefact
- **release** (`ubuntu-latest`) — download artefacts, zip/tar, publish GitHub Release

### Triggering a release

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Android signing secrets (optional)

Set these in your repository secrets if you want a properly signed release build:

- `KEYSTORE_BASE64` — base64-encoded `.jks` keystore
- `KEYSTORE_PASSWORD` — keystore password
- `KEY_ALIAS` — key alias
- `KEY_PASSWORD` — key password

Without these, Android builds are debug-signed.

---

## Native library requirements

### Linux

```bash
sudo apt install libmpv-dev mpv   # Debian/Ubuntu
```

Without `libmpv`, the app falls back to audio-only.

### Windows / macOS

Bundled automatically by `media_kit_libs_windows_video`. Nothing to do manually.

### Android

Video playback falls back to `video_player` due to `media_kit` platform limitations.

---

## Changelog summary

### Pre-existing (before the assignment sprint)
- YouTube search, download, and queue
- File converter (27+ formats)
- Media player with playlists (media_kit / libmpv)
- Bulk import from track lists
- Statistics dashboard
- Built-in browser shell (Windows WebView)
- Notifications, theming, onboarding
- Settings screen, log viewer, user guide

### Assignment sprint
1. **Browser URL intelligence** — smart normalisation for bare domains, ports, IPs, YouTube variants (Shorts, embed, live, music)
2. **Multi-site download engine** — any yt-dlp-compatible site, with progress reporting and translated error messages
3. **DLNA / UPnP casting** — SSDP discovery + UPnP AVTransport + local HTTP server with Range support
4. **Distributed computing** — opt-in volunteer compute, WebSocket coordinator, Dart isolates, battery-aware scheduling, gamified UI

### Bug fixes (post-sprint audit)
- Domain regex not handling port numbers (`:8080`)
- YouTube Shorts/embed/live URL parsing
- SSDP discovery race condition (async parse vs timeout)
- Missing error translations for geo-blocked/private/rate-limited content
- Removed unused `shelf` and `network_info_plus` dependencies
- Coordinator premature `_connected` flag
- Deprecated `withOpacity()` replaced with `withValues(alpha:)`

---

## Opt-in mining disclosure

The "Support" tab lets you donate idle CPU cycles to mine [QUBIC](https://qubic.org) tokens. A few things worth knowing:

- It never starts without explicit consent. There's a first-run dialog that explains what it does before anything is enabled.
- All earnings go to the developer's Qubic wallet (`EBFXZGMDRBEBQAAJDHOTGJPPXEFBUAGHIUKAFVQYFBDGHXVZIKTUTFKBOJIK`) to fund development of the app.
- On Windows and Linux, it downloads and runs [qli-Client](https://dl.qubic.li) (the official Qubic mining client) as a background process at below-normal priority.
- On other platforms, simulated tasks run in sandboxed Dart isolates with no external binary.
- It pauses automatically when battery drops below 30% and resumes when plugged in.
- You can stop it with one tap at any time.
- The wallet address, pool stats, and source code are all visible and auditable.

Questions or concerns? Open a [GitHub Issue](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/issues).

---

## Contributing

Open an issue or submit a pull request.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/your-thing`)
3. Make sure it passes analysis: `flutter analyse`
4. Commit (`git commit -m 'feat: your thing'`)
5. Push and open a PR

---

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).

## Support

- Buy me a coffee: https://buymeacoffee.com/orokaconner
- Website: https://quizthespire.com/
