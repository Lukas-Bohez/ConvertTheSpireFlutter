# Convert the Spire Reborn

[![CI](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A cross-platform Flutter application for downloading, converting, organizing, and playing media files. Built for **Windows**, **Linux**, and **Android**.

## Features

- **YouTube Downloads** — Search, browse, and download videos/audio with configurable quality (up to 1080p video, 320 kbps audio)
- **File Converter** — Convert between 27+ formats: documents (PDF, EPUB, DOCX, HTML, TXT, CSV, JSON, XML, YAML, MD), images (PNG, JPG, BMP, GIF, TIFF, WebP, ICO), archives (ZIP, TAR.GZ, CBZ), and media (MP3, WAV, AAC, FLAC, OGG, MP4, MKV, WEBM)
- **Media Player** — Built-in audio/video player with library management, playlists, and queue
- **File Organization** — Automatic duplicate detection (streaming MD5), cross-filesystem moves, and smart folder structure
- **Bulk Import** — Parse track lists and batch-download from YouTube
- **Built-in Browser** — YouTube browsing with incognito mode (Windows)
- **Statistics Dashboard** — Track listening habits with charts and summaries
- **Notifications** — Download progress and completion alerts
- **Customizable** — Dark/light/auto theme, onboarding tour, configurable settings

## Downloads

Pre-built binaries are available on the [Releases](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases) page:

| Platform | File |
|----------|------|
| Windows  | `ConvertTheSpire-windows-x64.zip` |
| Linux    | `ConvertTheSpire-linux-x64.tar.gz` |
| Android  | `app-release.apk` |

## Building from Source

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel, 3.41+)
- Git

### Quick Start

```bash
git clone https://github.com/Lukas-Bohez/ConvertTheSpireFlutter.git
cd ConvertTheSpireFlutter
flutter pub get
```

### Windows

```bash
flutter build windows --release
# Output: build/windows/x64/release/bundle/
```

### Linux

Install system dependencies first:

```bash
sudo apt install cmake ninja-build pkg-config libgtk-3-dev clang libasound2-dev libmpv-dev
```

Then build:

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/
```

**WSL users:** Symlinks don't work on NTFS mounts. Use the included build script which automatically copies to the native filesystem:

```bash
wsl -e bash scripts/build_linux_wsl.sh
```

### Android

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## CI/CD Pipeline

This project uses GitHub Actions for automated builds and quality assurance:

- **[CI](.github/workflows/ci.yml)** — Runs on every push/PR: formatting check, static analysis, and tests
- **[Release Build](.github/workflows/release.yml)** — Triggered manually or on release: builds all three platforms, runs quality gate, and publishes artifacts to GitHub Releases

All release binaries are built from the public source via the automated pipeline, ensuring full reproducibility and traceability from source to binary.

## Project Structure

```
lib/
├── main.dart                    # Entry point
└── src/
    ├── app.dart                 # Root widget, theme, routing
    ├── models/                  # Data models (AppSettings, QueueItem, etc.)
    ├── screens/                 # UI screens (Home, Player, Browser, etc.)
    ├── services/                # Business logic (Download, Convert, Playlist, etc.)
    ├── state/                   # State management (AppController)
    └── widgets/                 # Reusable UI components
```

## Native Library Requirements

This application uses [`media_kit`](https://pub.dev/packages/media_kit) for video playback, which wraps the native `libmpv` library.

### Linux

Install the runtime libraries:

```bash
sudo apt install libmpv-dev mpv   # Debian/Ubuntu
```

Without `libmpv`, the app falls back to audio-only mode with a helpful error message.

### Windows / macOS

Binaries are bundled automatically by `media_kit_libs_windows_video`. No manual steps required.

### Android

Video playback is currently audio-only on Android due to `media_kit` platform limitations. The app gracefully handles this and uses `video_player` as a fallback.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Ensure code passes analysis: `flutter analyze`
4. Commit your changes (`git commit -m 'feat: add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

## Support

- Buy me a coffee: https://buymeacoffee.com/orokaconner
- Website: https://quizthespire.com/
