# Convert the Spire Reborn

[![CI/CD](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Flutter](https://img.shields.io/badge/Flutter-3.27.4-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20Android-brightgreen)](#downloads)

## What Is This?

**Convert the Spire Reborn** is a cross-platform Flutter application that unifies media downloading, conversion, playback, DLNA casting, and opt-in distributed computing into a single native app. It runs on **Windows**, **Linux**, and **Android** — no Electron, no browser overhead, just native performance.

The app began as a personal media-management tool and evolved into a full-featured platform through four major feature sprints (see [What Was Built When](#what-was-built-when) below).

---

## Features

### Core (Pre-existing)
| Feature | Description |
|---------|-------------|
| **YouTube Search & Download** | Search, browse, and download videos/audio with configurable quality (up to 1080p video, 320 kbps audio) via yt-dlp |
| **Multi-Search** | Search across multiple sites simultaneously and compare results |
| **File Converter** | Convert between 27+ formats: documents (PDF, EPUB, DOCX, HTML, TXT, CSV, JSON, XML, YAML, MD), images (PNG, JPG, BMP, GIF, TIFF, WebP, ICO), archives (ZIP, TAR.GZ, CBZ), and media (MP3, WAV, AAC, FLAC, OGG, MP4, MKV, WEBM) |
| **Media Player** | Built-in audio/video player powered by `media_kit` (libmpv) with library management, playlists, and queue |
| **File Organization** | Automatic duplicate detection via streaming MD5, cross-filesystem moves, smart folder structure |
| **Bulk Import** | Parse track lists and batch-download from YouTube |
| **Statistics Dashboard** | Track listening habits with `fl_chart` visualizations |
| **Built-in Browser** | YouTube browsing with incognito mode (Windows, via `webview_windows`) |
| **Notifications** | Download progress and completion alerts via `flutter_local_notifications` |
| **Customizable** | Dark/light/auto theme, onboarding tour, configurable settings |

### Assignment Features (New)

#### 1. Built-in Browser with Smart URL Handling
Full in-app browser with intelligent URL normalization — bare domains (`hianime.to`), IP addresses (`192.168.1.1`), ports (`localhost:8080`), and search queries are all handled automatically. YouTube URL detection supports standard watch links, Shorts, embeds, live streams, and `music.youtube.com`.

#### 2. Multi-Site Download Engine
Extended the download service beyond YouTube to support **any site that yt-dlp supports** (~1,800 sites). The `downloadGeneric()` pipeline provides progress reporting, human-readable error messages (geo-blocks, private content, rate limits), and automatic format conversion via FFmpeg.

#### 3. DLNA / UPnP Casting
Cast media to any DLNA-compatible TV, speaker, or receiver on the local network:
- **SSDP discovery** scans the LAN for UPnP renderers
- **Manual IP fallback** for devices that don't respond to multicast
- **Local HTTP server** (`dart:io HttpServer`) serves media files with `Range` request support for seeking
- **SOAP/XML control** for play, pause, stop, and volume via UPnP AVTransport

#### 4. Distributed Computing (Opt-in)
Volunteer spare CPU cycles to a coordinator server for scientific / open-data workloads:
- **WebSocket coordination** with exponential-backoff reconnection and offline job queue
- **Dart `Isolate.run`** for sandboxed, parallel computation (no main-thread jank)
- **Battery-aware scheduling** — automatically pauses when battery <30% or unplugged
- **Gamification UI** — contributor tiers (Bronze → Silver → Gold → Diamond), progress bars, live dashboard with task stats

---

## Why Native?

| Concern | Native (Flutter) | Web / Electron |
|---------|-------------------|----------------|
| **Startup time** | ~200 ms (AOT compiled) | 2–5 s (JS parse + hydrate) |
| **Memory** | ~80 MB | 300–600 MB (Chromium process) |
| **File system** | Direct `dart:io` access | Sandboxed, limited |
| **Network** | Raw UDP/TCP sockets (SSDP, DLNA) | No UDP, no multicast |
| **CPU isolation** | `Isolate.run` (true parallelism) | Web Workers (serialization overhead) |
| **Battery API** | `battery_plus` native plugin | Navigator.getBattery() (Chrome only) |

Flutter compiles to native ARM/x64 binaries via Dart's AOT compiler. There is no JavaScript runtime, no DOM, and no garbage-collection pauses. This matters for real-time features like DLNA streaming (HTTP range requests must respond in <100 ms) and distributed compute (isolate pool throughput).

---

## IoT / Embedded Relevance

This project demonstrates patterns common in IoT and embedded-adjacent applications:

- **SSDP / UPnP discovery** — The same multicast protocol used by smart-home hubs, Chromecast, and Sonos. Our `DlnaDiscoveryService` sends M-SEARCH datagrams to `239.255.255.250:1900` and parses XML device descriptors, exactly as a home-automation controller would.
- **Local HTTP media server** — `LocalMediaServer` serves files from disk with `Range` header support, enabling any network device (TV, speaker, set-top box) to stream and seek. This is the same pattern used by Plex, Jellyfin, and NAS firmware.
- **Battery-aware scheduling** — The distributed compute feature monitors battery state and throttles work accordingly — a pattern directly applicable to battery-powered IoT gateways and edge devices.
- **Isolate-based computation** — Dart isolates provide memory-isolated parallelism without shared-state bugs, similar to how embedded RTOS systems use separate task contexts.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter UI                           │
│  HomeScreen (rail nav) → 13 screens (Search, Player, …)    │
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

### Key Files

| Path | Purpose |
|------|---------|
| `lib/main.dart` | Entry point |
| `lib/src/app.dart` | Root widget, theme, Provider wiring |
| `lib/src/state/app_controller.dart` | Central state (queue, settings, downloads) |
| `lib/src/screens/home_screen.dart` | Navigation rail with 13 tabs |
| `lib/src/screens/browser_screen.dart` | In-app browser + URL normalization |
| `lib/src/screens/compute_screen.dart` | Distributed compute UI with gamification |
| `lib/src/services/download_service.dart` | Generic multi-site download engine |
| `lib/src/services/dlna_discovery_service.dart` | SSDP device discovery |
| `lib/src/services/dlna_control_service.dart` | UPnP AVTransport SOAP control |
| `lib/src/services/local_media_server.dart` | HTTP file server with Range support |
| `lib/src/services/computation_service.dart` | Isolate pool for distributed tasks |
| `lib/src/services/coordinator_service.dart` | WebSocket coordinator client |

---

## Downloads

Pre-built binaries are available on the [Releases](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases) page:

| Platform | File | Notes |
|----------|------|-------|
| Windows x64 | `ConvertTheSpire-Windows-vX.Y.Z.zip` | Extract and run `my_flutter_app.exe` |
| Linux x64 | `ConvertTheSpire-Linux-vX.Y.Z.tar.gz` | Requires `libmpv` at runtime |
| Android arm64 | `app-arm64-v8a-release.apk` | Modern 64-bit devices |
| Android armv7 | `app-armeabi-v7a-release.apk` | Older 32-bit devices |

---

## Building from Source

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) **3.27.4** (stable channel)
- Git
- Platform-specific toolchains (see below)

### Quick Start

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
# Output: build\windows\x64\runner\Release\my_flutter_app.msix
```

### Linux

Install system dependencies first:

```bash
sudo apt install clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libstdc++-12-dev \
  libmpv-dev mpv libass-dev
```

Then build:

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

**WSL users:** Symlinks don't work on NTFS mounts. Use the included build script:

```bash
wsl -e bash scripts/build_linux_wsl.sh
```

### Android

```bash
# Debug APK
flutter build apk --debug

# Release APKs (split per ABI for smaller downloads)
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-{abi}-release.apk
```

For signed release builds, create `android/key.properties`:
```properties
storePassword=YOUR_PASSWORD
keyPassword=YOUR_PASSWORD
keyAlias=YOUR_ALIAS
storeFile=path/to/keystore.jks
```

---

## CI/CD Pipeline

The project uses a single [GitHub Actions workflow](.github/workflows/ci.yml) with five jobs:

```
push/PR to main ──► quality ──► build-windows ──►
                                build-linux   ──► release (on v* tags)
                                build-android ──►
```

| Job | Runner | What it does |
|-----|--------|-------------|
| **quality** | `ubuntu-latest` | `flutter pub get`, `flutter analyze`, conditional `flutter test` |
| **build-windows** | `windows-latest` | `flutter build windows --release` → upload artifact |
| **build-linux** | `ubuntu-latest` | Install apt deps → `flutter build linux --release` → upload artifact |
| **build-android** | `ubuntu-latest` | JDK 17 → optional keystore from secrets → `flutter build apk --release --split-per-abi` → upload artifact |
| **release** | `ubuntu-latest` | Download all artifacts → zip/tar → create GitHub Release with OSSign compliance info |

### Triggering a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

The pipeline builds all three platforms and publishes a GitHub Release with downloadable binaries.

### Android Signing Secrets (optional)

| Secret | Value |
|--------|-------|
| `KEYSTORE_BASE64` | Base64-encoded `.jks` keystore |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias name |
| `KEY_PASSWORD` | Key password |

Without these secrets, Android builds are debug-signed.

---

## Native Library Requirements

### Linux

```bash
sudo apt install libmpv-dev mpv   # Debian/Ubuntu
```

Without `libmpv`, the app falls back to audio-only mode.

### Windows / macOS

Binaries are bundled automatically by `media_kit_libs_windows_video`. No manual steps required.

### Android

Video playback uses `video_player` as a fallback due to `media_kit` platform limitations.

---

## What Was Built When

### Pre-existing (before assignment)
The application's core was fully functional before the four assignment features were added:
- YouTube search, download, and queue management
- File converter (27+ formats)
- Media player with playlists (media_kit / libmpv)
- Bulk import from track lists
- Statistics dashboard
- Built-in browser shell (Windows WebView)
- Notifications, theming, onboarding
- Settings screen, log viewer, user guide

### Assignment Sprint (new features)
Four features were implemented as part of the coursework assignment:

1. **Browser URL Intelligence** — Smart URL normalization (domain detection, port handling, IP addresses, YouTube variant parsing for Shorts/embed/live/music)
2. **Multi-Site Download Engine** — Extended download pipeline to support any yt-dlp-compatible site with progress reporting and translated error messages
3. **DLNA / UPnP Casting** — Full SSDP discovery + UPnP AVTransport control + local HTTP media server with Range support
4. **Distributed Computing** — Opt-in volunteer compute via WebSocket coordinator, Dart isolates, battery-aware scheduling, and gamified UI

### Bug Audit (post-implementation)
After the four features were built, a systematic audit identified and fixed 8 bugs:
- Domain regex not handling port numbers (`:8080`)
- YouTube Shorts/embed/live URL parsing in browser
- SSDP discovery race condition (async parse vs timeout)
- Missing error translations for geo-blocked/private/rate-limited content
- Unused `shelf` and `network_info_plus` dependencies removed
- Coordinator premature `_connected` flag
- Deprecated `withOpacity()` → `withValues(alpha:)` migration

---

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Ensure code passes analysis: `flutter analyze`
4. Commit your changes (`git commit -m 'feat: add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

---

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

## Support

- Buy me a coffee: https://buymeacoffee.com/orokaconner
- Website: https://quizthespire.com/
