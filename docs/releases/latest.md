# Release Notes - v13.0.1

## Regression fix release

## Highlights

* **Cinematic view rewritten.** The new ambient shader uses a deterministic day/night cycle, soft drifting clouds, rain puddles, and stars that twinkle on individual schedules instead of a single strobing pulse. The transport controls now sit on a simple dark translucent panel, eliminating the white/grey overlay that appeared when they faded in. The black top bar is also gone.
* **Windows playback fixed.** The YouTube fallback client list no longer selects the `androidVr` client on Windows, which was producing unplayable streams. Desktop now rotates through `tv`, `safari`, `ios`, and `web` clients instead.
* **Windows release bundle tidier.** Plugin DLLs are moved into a `dlls/` subfolder next to the executable; the executable and its direct runtime dependencies stay in the root.
* See [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## Build Notes

* GitHub release tag: `v13.0.1`
* Release page: [v13.0.1](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.1)
* `flutter analyze` and `flutter test --coverage` pass cleanly.
