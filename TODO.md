# TODO: ConvertTheSpireFlutter Improvements

This file tracks the work needed to make ConvertTheSpireFlutter feel like a modern, trustworthy, and powerful downloader while removing "scummy" behavior.

---

## 1) Immediate “Exorcism” (Critical)

### ✅ Remove Miner / Background CPU Usage
- [x] Delete all code related to QUBIC or any hidden/background CPU mining behavior.
- [x] Remove any background threads/processes that run without explicit user action (e.g., outside of downloads).
- [x] Replace “miner” monetization strategy with a transparent donation option (e.g., **Buy Me a Coffee** link or **GitHub Sponsors** button).

### ✅ Audit & Trim Dependencies
- [ ] Review `pubspec.yaml` for unused or redundant dependencies.
- [ ] Remove packages that are not strictly necessary for core functionality (download + UI + platform support).
- [ ] Confirm pubspec has no suspicious or irrelevant packages (especially those associated with analytics, tracking, or crypto).

---

## 2) Fix the “Resolution Ceiling” (Core Functionality)

### ✅ Replace `youtube_explode_dart` for high-res downloads
- [x] Identify where `youtube_explode_dart` is used for stream enumeration and downloading.
- [x] Remove or minimize reliance on `youtube_explode_dart` for DASH streams by using yt-dlp when available.

### ✅ Integrate `yt-dlp` via process execution
- [ ] Add a bridge using a package like `process_run` (or equivalent) to execute `yt-dlp` commands.
- [x] Enable 4K/8K/HDR stream selection and proper audio/video merging.
- [ ] Ensure cross-platform compatibility (Windows/macOS/Linux and mobile platforms if supported).
- [x] Add an engine health indicator that shows whether `yt-dlp` is present and the version.

---

## 3) UI/UX: From “Busy” to “Boutique”

### ✅ Simplify the Download Flow
- [x] Replace cluttered dashboard with a single “Paste Link” entry point.
- [x] Add a preview modal showing title/thumbnail/quality before download starts.
- [x] Support per-download quality selection (1080p/4K/8K) in the preview.
- [ ] Remove or hide non-essential UI elements.

### ✅ Implement Modern Theming
- [ ] Adopt Material 3 / Fluent design (Android/Desktop) and Cupertino (iOS) where appropriate.
- [x] Use a clean system font (Inter) across the app for premium typography.
- [ ] Add dynamic theming support (Monet-style dynamic colors) and dark mode.

### ✅ Improve Progress Visualization
- [ ] Show separate progress indicators for video and audio streams.
- [ ] Display download speeds, ETA, and estimated file size.
- [ ] Display clear status messaging for each phase (fetching info, downloading, encoding, finishing).

---

## 4) High-Value Power Features

### ✅ Metadata Tagging
- [ ] Embed thumbnail, artist, album art, and title metadata into output files (MP3/MP4).

### ✅ Playlist Management
- [ ] When a playlist URL is entered, list items and allow users to uncheck tracks before downloading.

### ✅ SponsorBlock Integration
- [x] Provide an optional setting to use SponsorBlock API to skip sponsored segments during download/conversion.

---

## 5) Portability & Privacy

### ✅ No Analytics / Privacy First
- [ ] Ensure there is no usage of analytics/telemetry libraries.
- [ ] Add a clear “No analytics” statement in the app’s UI and documentation.

### ✅ Self-Updating yt-dlp
- [x] Add a “Update Downloader Engine” button in settings.
- [x] Implement logic to download and replace the `yt-dlp` binary (or script) without requiring a full app update.

---

## “Better Version” Goals (For Messaging / Feature Planning)

| Feature | “Hated” Version | Improved Version |
|--------|----------------|-----------------|
| Monetization | Background crypto mining | Open source / optional donations |
| Video Quality | Capped at 1080p | Full 4K/8K support (via yt-dlp) |
| UI Design | Cluttered / AI-generated | Clean, native Material 3 / Fluent |
| Features | Simple download only | Metadata tagging, SponsorBlock, subtitles |
| Trust | Shady miner + hidden tracking | Transparent, privacy-focused, lean |




Since you’ve been given the keys to the main branch, you have a rare opportunity to perform a "rebrand" that turns a project people were suspicious of into a tool they actually rely on.

To do this "kindly," you don’t need to trash the previous version. Instead, frame the update as an **evolution toward transparency and performance.**

### The "New Direction" Strategy

Your README should act as a "Statement of Intent." It should signal to anyone who previously "hated" the project that the issues (the miner, the bloat, the low resolution) have been heard and addressed.

---

### Suggested README Template

```markdown
# ConvertTheSpire (Refreshed) 🚀
**A lean, high-performance YouTube playlist downloader for Desktop & Android.**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/graphs/commit-activity)

---

## 🌟 What’s New? (The "Community-First" Update)
We’ve completely overhauled the project to focus on what matters: **Privacy, Speed, and Quality.**

* **🚫 Zero Mining:** All background crypto-mining components have been removed. This is now a 100% clean, transparent utility.
* **💎 True 4K Support:** Broken the 1080p ceiling. High-resolution downloads are now fully supported.
* **⚡ Native Performance:** Optimized Flutter code for a faster, lighter footprint on your system.
* **🎨 Clean UI:** Stripped away the bloat for a streamlined, modern Material 3 interface.

---

## ✨ Features
* **Mass Playlist Sync:** Paste a URL and download an entire playlist in one go.
* **Duplicate Detection:** Automatically skips files you already have in your local folder.
* **Multi-Platform:** Built for Linux, Windows, and Android.
* **Parallel Downloading:** Configurable workers to maximize your bandwidth.

---

## 🛠 Installation

### Linux / Windows
1. Download the latest release from the [Releases](#) tab.
2. Ensure you have `yt-dlp` and `ffmpeg` installed on your system.
3. Run the executable and start syncing!

### Android
* Download the `.apk` from the latest release.
* *Note: High-resolution downloads on Android are now optimized via [Your New Engine].*

---

## 🛡 Privacy & Ethics
This project is now maintained with a strict "User-First" philosophy.
1. **No Tracking:** We don't collect data on what you download.
2. **Open Source:** Every line of code is auditable.
3. **No Hidden Costs:** No "optional" mining or background resource usage.

---

## 🤝 Contributing
Have a feature request or found a bug? 
- Open an [Issue](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/issues)
- Submit a [Pull Request](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/pulls)

```

---

### 3 "Pro Tips" for a Kind Transition

1. **The "Acknowledge & Move On" Note:**
If you want to be extra transparent, add a small section or a pinned issue titled **"State of the Project - 2026."** Briefly state: *"After community feedback, the project has transitioned to a new maintainer focused on removing resource-intensive background tasks (miners) and improving core download quality."* It shows you listened without being mean to the original dev.
2. **Visual Proof:**
Replace the old screenshots. Nothing says "this is a new app" like a fresh, clean screenshot that doesn't look like a template.
3. **Update the "About" Section:**
Change the GitHub "About" description to something like: *"A privacy-focused, high-quality YouTube playlist downloader. No miners, no bloat."*

**Would you like me to help you draft a "V2.0 Release" announcement that you can post on Reddit or the GitHub Releases page to show the 'haters' that the project has changed?**