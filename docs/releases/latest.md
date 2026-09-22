# Release Notes - v14.3.1

## Watch Together polish

### Fixed

* **Seeking now reaches the room immediately.** A scrub was only picked up by the once-a-second state broadcast, so everyone else stayed up to a second behind after the host dragged the scrubber. The new position is sent the moment it changes.
* **"The room is watching something you do not have" is now actually shown.** When the room moves to a file that is not in your library, the player produced that message but nothing displayed it, so the screen just sat there looking stuck. It now appears as a warning.
* Local build logs no longer clutter the repository root.

### Build Notes

* Android Play AAB built with `--flavor play` (version 14.3.1+1295).
* `flutter analyze` clean; 251 tests pass.
* GitHub release tag: v14.3.1
* Release page: [v14.3.1](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.3.1)
