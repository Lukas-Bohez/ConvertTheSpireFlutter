## Convert the Spire Reborn v13.0.0 - "The Linux & Compliance Release"

> ⚠️ **Pre-release / Beta** - core features are stable but
> some edge cases remain. Feedback very welcome.

### What's new in v13.0.0
- Linux & macOS now download the correct self-contained yt-dlp binary (no system Python required)
- Target API level raised to 36 (Android 16) for Play Store compliance
- Fixed build_release.sh: version reads from pubspec.yaml, GITHUB_RELEASE flag set correctly
- Cinematic view v2: de-periodized star twinkle, sun/moon always visible, clouds, rain with puddles
- Browser bottom bar auto-hide with gesture-gated search bar
- Onboarding streamlined from 14 to 5 pages, Android TV overscan fixed
- Unified downloads inbox with filter/sort toolbar
- Favourite/dislike badges visible in player and cinematic transport
- Offline thumbnail generation from cinematic view
- Keystore exposure fixed (removed from public repo history)
- Strict CI lint gates enabled (no more --no-fatal-warnings)

### Download
| Platform | File |
|----------|------|
| Windows (x64) | `ConvertTheSpireReborn.zip` |
| Android (arm64) | `ConvertTheSpireReborn.apk` |
| Android / Play Store | `ConvertTheSpireReborn.aab` |
| Linux (x64) | `linux.zip` |

### Installation
**Windows:** Extract ZIP, run `ConvertTheSpireReborn.exe`.
No installer needed. VC++ Redistributable required if not
already installed.

**Android:** Enable "Install from unknown sources", install APK. For Play Store distribution, upload the `.aab`.

**Android TV:** Uses the Android build and the same Play/AAB package.

**Linux:** Extract ZIP, run `bundle/convert_the_spire_reborn`.
Requires libmpv and development headers for builds:
`sudo apt install libmpv1 libmpv-dev mpv libass-dev libayatana-appindicator3-dev` (Ubuntu/Debian)

### Known limitations in this pre-release
- DLNA casting may drop on some older renderers
- No in-app auto-update yet (planned for future release)
- Linux requires manual libmpv install (one-liner above)

### Privacy
No telemetry or analytics. All downloads happen locally via yt-dlp.

---

#### VERIFICATION - DO THESE BEFORE PUSHING THE RELEASE TAG

Run through this yourself manually - no prompt can do it:

  □ Fresh flutter pub get - no version conflicts
  □ flutter analyze - zero errors, zero warnings
  □ Windows release build completes:
      flutter build windows --release
  □ Android release build completes:
      flutter build apk --release --split-per-abi
    □ Play Store bundle build completes:
      flutter build appbundle --release --dart-define=PLAY_STORE_BUILD=true
  □ Rename artifacts to exact release filenames:
      ConvertTheSpireReborn.zip
      ConvertTheSpireReborn.apk  (arm64 only)
      ConvertTheSpireReborn.aab
      linux.zip
  □ Launch Windows build: title bar shows correct app name
  □ Task manager shows "Convert the Spire Reborn" not
    "my_flutter_app"
  □ Download one YouTube video end to end
  □ Download one non-YouTube URL (Vimeo or SoundCloud)
  □ Open browser, navigate, tap download button - spinner
    appears, download queued, SnackBar confirms
  □ Open settings - all dropdowns show correct selected values
  □ Toggle dark mode - no white/grey boxes anywhere
  □ Queue: add 3 items, filter by title - correct results shown
  □ CI passes on main branch before tagging
