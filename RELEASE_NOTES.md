# Release Notes — v13.0.2

## What's New
(none — fix release)

## Bug Fixes
- **Windows launch crash**: Removed the `SetDllDirectoryW`-based DLL subfolder mechanism that moved plugin DLLs into `dlls/` at packaging time. The Windows loader loads the executable's direct import dependencies before `wWinMain` runs, so `SetDllDirectoryW` — called inside `wWinMain` — couldn't resolve DLLs the loader needed during process startup. All plugin DLLs now ship flat in the release root directory, and the `organize_dlls.ps1` invocation has been removed from the release workflow.
- **YouTube `androidVr` PO-token regression**: Replaced `androidVr` with `tv` in all youtube_explode_dart client lists and yt-dlp extractor args across all platforms (not just Windows). YouTube now requires a GVS PO token for `androidVr` above 360p, which was blocking HD downloads.

See [CHANGELOG.md](CHANGELOG.md) for fuller details.
