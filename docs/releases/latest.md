# Release Notes - v13.0.2

## DLL Linking & Download Fix Release

## Highlights

* **Windows launch fixed.** The `SetDllDirectoryW` + `dlls/` subfolder mechanism was unreliable — the Windows loader binds the executable's direct import dependencies before `wWinMain` begins, so any DLL moved to a `dlls/` subfolder could not be resolved at process startup, preventing the app from launching. All plugin DLLs now ship flat in the release root directory, and the `organize_dlls.ps1` step has been removed from the release workflow.
* **YouTube `androidVr` PO-token fix.** Replaced `androidVr` with `tv` everywhere — in all `youtube_explode_dart` client lists (both the `_getManifestWithFallbackClients` bucket rotation and the Android download manifest-refresh paths) and in the yt-dlp `--extractor-args` (`youtube:player_client=tv,web`). YouTube now requires a GVS PO token for `androidVr` above 360p, which was silently blocking HD downloads on all platforms.
* **Cinematic view** (from v13.0.1) — see [CHANGELOG.md](CHANGELOG.md) for the full list of changes.

## Build Notes

* GitHub release tag: `v13.0.2`
* Release page: [v13.0.2](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.2)
* `flutter analyze` and `flutter test --coverage` pass cleanly.
