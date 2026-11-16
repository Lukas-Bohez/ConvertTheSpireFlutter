# Convert the Spire Reborn v16.3.1

## No more sudden closing on Windows, and songs keep their volume

### Fixed

- **Windows:** the app no longer closes by itself while music plays. Windows apps tell screen readers and other window-reading tools (some come with Windows) what is on screen. When such a tool asked about something the page had just removed, Flutter, the toolkit the app is built with, crashed. The app now answers "that is gone" instead. The bug is still open in Flutter itself.
- A song no longer plays quieter the second time. Volume leveling measured a song while it played for the first time, and only the replay used the result.
- Clicking quickly through tracks always ends on the last one you picked. A click within a third of a second of the previous one showed the new track but kept playing the old one.
- The **Play Spire Museum** button on Home is as tall as the buttons beside it. So is every filled button in the app, which were shorter than the outlined and text buttons next to them.

### Improved

- Volume leveling is off unless you turn it on (the equalizer button at the top of the player). Turned on, a song plays at its leveled volume from the first second: playback waits the second or two the measurement takes. A long video that takes more than 10 seconds to measure starts anyway and fades to its level in two seconds instead of jumping.
- With volume leveling off, every file plays at the level it was made, ReplayGain tags included.
- Measuring a song's loudness stops FFmpeg when it takes too long, and file names with unusual characters no longer break it.

### Build Notes

- `windows/runner/accessibility_guard.cpp`: a vectored exception handler for [flutter#195399](https://github.com/flutter/flutter/issues/195399) and [flutter#192220](https://github.com/flutter/flutter/issues/192220). `FlutterPlatformNodeDelegate::ChildAtIndex` reads `id()` of a null child (`flutter_windows.dll` + 0x3CEF3 in 3.41.2, `mov edx, [rax+50h]`). The two crashes in 16.3.0 on 15 November were there. The handler matches the machine code around the fault and makes `ChildAtIndex` return `nullptr`; every other fault crashes as before.
- `convert_the_spire_reborn.exe --self-test-accessibility-guard` calls the bundled engine's `ChildAtIndex` for a missing child and exits 0 when the guard caught it. The release and Microsoft Store workflows run it after the Windows build. If it fails after a Flutter upgrade, check whether the engine checks for null now, then drop the guard or update its pattern.
- Track loads run one at a time (`_selectionLock`); a load that a newer selection replaced stops at its next check. The 350 ms "too soon" skip that dropped quick clicks is gone from that path.
- The release workflow has a `publish_release` input: `false` builds every package without publishing a release.
