## Convert the Spire Reborn v5.0.0 — "The Polish Release"

> ⚠️ **Pre-release / Beta** — core features are stable but
> some edge cases remain. Feedback very welcome.

### What's new in v5.0.0
- Full browser toolbar redesign: download button front and
  centre, cast/more actions moved to ⋮ menu
- Live URL tracking via onUpdateVisitedHistory — download
  button always reflects the actual current page
- DropdownButtonFormField value binding fixed across all tabs
- AppColors theme extension — zero hardcoded color values
- Queue sidebar adapts to panel width (compact/full modes)
- Navigation history (back/forward) across all tabs
- CI/CD pinned to Flutter 3.41.2 across all build jobs
- Dependency verification step added to CI pipeline

### Download
| Platform | File |
|----------|------|
| Windows (x64) | `ConvertTheSpireReborn.zip` |
| Android (arm64) | `ConvertTheSpireReborn.apk` |
| Linux (x64) | `linux.zip` |

### Installation
**Windows:** Extract ZIP, run `ConvertTheSpireReborn.exe`.
No installer needed. VC++ Redistributable required if not
already installed.

**Android:** Enable "Install from unknown sources", install APK.

**Linux:** Extract ZIP, run `bundle/convert_the_spire_reborn`.
Requires libmpv and development headers for builds:
`sudo apt install libmpv1 libmpv-dev mpv libass-dev libayatana-appindicator3-dev` (Ubuntu/Debian)

### Known limitations in this pre-release
- DLNA casting may drop on some older renderers
- Android background mining pauses on low battery;
  heat throttling not yet fine-tuned
- No in-app auto-update yet (planned for v5.1)
- Linux requires manual libmpv install (one-liner above)

### Privacy
No telemetry or analytics. Mining is 100% opt-in and only
shares CPU cycles via public QUBIC endpoints — no personal
data is sent. All downloads happen locally via yt-dlp.

---

#### VERIFICATION — DO THESE BEFORE PUSHING THE RELEASE TAG

Run through this yourself manually — no prompt can do it:

  □ Fresh flutter pub get — no version conflicts
  □ flutter analyze — zero errors, zero warnings
  □ Windows release build completes:
      flutter build windows --release
  □ Android release build completes:
      flutter build apk --release --split-per-abi
  □ Rename artifacts to exact release filenames:
      ConvertTheSpireReborn.zip
      ConvertTheSpireReborn.apk  (arm64 only)
      linux.zip
  □ Launch Windows build: title bar shows correct app name
  □ Task manager shows "Convert the Spire Reborn" not
    "my_flutter_app"
  □ Download one YouTube video end to end
  □ Download one non-YouTube URL (Vimeo or SoundCloud)
  □ Open browser, navigate, tap download button — spinner
    appears, download queued, SnackBar confirms
  □ Open settings — all dropdowns show correct selected values
  □ Toggle dark mode — no white/grey boxes anywhere
  □ Queue: add 3 items, filter by title — correct results shown
  □ CI passes on main branch before tagging
