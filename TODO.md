# ConvertTheSpire (Refreshed) - Project Roadmap & TODOs

This file tracks the work needed to make ConvertTheSpireFlutter feel like a modern, trustworthy, and powerful downloader, while ensuring all legacy "scummy" behavior is completely eradicated.


## 🚀 PHASE 1: The "Exorcism" & Trust Rebuild (✅ COMPLETED)
*The critical steps taken to remove malicious/unwanted behavior and restore community trust.*



## ⚙️ PHASE 2: Core Engine & Resolution Fixes (✅ COMPLETED)
*Breaking the 1080p ceiling and establishing a reliable download pipeline.*



## 🎨 PHASE 3: Current Sprint - UI Polish & UX (🚧 IN PROGRESS)
*Transitioning the app from a "busy" generic wrapper to a premium native utility.*

 [x] **Global Typography:** Inject `GoogleFonts.inter()` or `Geist` globally via `MaterialApp` theme so it doesn't look like default Flutter.
 [x] **Dynamic/Modern Theming:** Implement Material 3 color schemes (Monet-style dynamic colors) and ensure true Dark Mode compatibility.

## 🔋 PHASE 4: High-Value Power Features (⏳ UP NEXT)
*Features that make this app vastly superior to using a raw terminal command.*

 [x] **Live Progress Visualization:** Show separate, accurate progress bars for video/audio streams, including download speeds and ETA.
 [x] **Metadata Tagging:** Automatically embed the thumbnail, artist name, album art, and title into the output `.mp3` or `.mp4` files.
 [x] **Cross-Platform Stability Test:** Run full end-to-end tests (paste playlist -> 4K select -> merge) on Windows, macOS, Linux, and Android.