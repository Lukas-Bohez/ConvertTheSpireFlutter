# Release Notes — v5.0.0

## Highlights

- **Cast to any device** — Chromecast, AirPlay, and DLNA devices are all discovered automatically via mDNS and SSDP
- **Desktop polish** — window geometry persists, media key shortcuts work out of the box, library auto-refreshes when files change
- **Performance** — player lists virtualised with `ListView.builder` for smooth scrolling on large libraries
- **Accessibility** — all player controls have proper screen-reader labels and tooltips
- **Reliability** — null-safety fixes in media server, better error handling for difficult download sites, kIsWeb guards throughout
- **Miner stability** — auto-resume on restart, battery guard pauses native miner, exponential backoff on connection failures, manual retry button, first-run consent dialog

See [CHANGELOG.md](CHANGELOG.md) for full details.

## Windows Requirements

If the app fails to open with an error about a missing Visual C++ runtime (e.g. "The specified module could not be found" or errors referencing `vcruntime140.dll`/`msvcp140.dll`), please install the Microsoft Visual C++ Redistributable (x64):

- https://aka.ms/vs/17/release/vc_redist.x64.exe

This is a one-time install required by many native Windows applications and resolves runtime errors caused by missing CRT components used by `libmpv`.
