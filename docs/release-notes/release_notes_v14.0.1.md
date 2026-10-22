# Convert the Spire Reborn v14.0.1

## Tidy Windows download, fixed Android icon, and the demo video

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

### Build Notes

- Android Play AAB built with `--flavor play` (version 14.0.1+1289).
- Release workflow builds Windows, macOS, and Android artifacts.
