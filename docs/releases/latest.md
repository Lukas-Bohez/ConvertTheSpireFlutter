# Release Notes - v13.0.20

## Playlist parsing and Windows browser fixes

## Fixes

* **Android/iOS playlists could load 0 tracks.** YouTube's new `lockupViewModel` structure is now parsed directly, restoring playlist imports including large lists.
* **Windows in-app browser could show a blank window.** WebView2 initialization is now gated before rendering, with a visible error and retry action when initialization fails.

## Improvements

* In-app browser search now uses a modern desktop Chrome user-agent for Google and Bing, with server-rendered DuckDuckGo results as the default.
* GitHub Actions release steps now use Node 24-compatible action versions.

## Build Notes

* GitHub release tag: v13.0.20
* Release page: [v13.0.20](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.20)
* `flutter analyze` clean; playlist service tests pass; release workflow builds Windows, Linux, macOS, Android, and web artifacts.

