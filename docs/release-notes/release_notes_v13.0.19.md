## Highlights

- **Fixed:** Android/iOS playlists loading 0 tracks. YouTube changed
  playlist-page markup to a new `lockupViewModel` format that the old
  parser (and youtube_explode_dart) don't recognize. The app now parses
  the new format directly, restoring full playlist loads including
  800+ track lists. **Verified:** parser tested against real YouTube
  playlist HTML including the `lockupMetadataViewModel` and
  `contentMetadataViewModel` structures.
- **Fixed:** the in-app browser on Windows could show a black/blank
  window on first load. The widget now waits for the WebView2 controller
  to report ready before building content. **Also fixed:** if WebView2
  initialization fails (missing runtime, GPU issue), the browser now
  shows an error message with a Retry button instead of a permanent
  blank screen.
- **Improved:** in-app browser search — Google and Bing no longer show
  a bot-check wall (new desktop Chrome user-agent), and the default
  DuckDuckGo search now uses its server-rendered results page for more
  reliable results.

## Under the hood

- GitHub Actions bumped to Node 24 runtimes: `actions/upload-artifact@v7`,
  `actions/download-artifact@v8`, `softprops/action-gh-release@v3`
  (eliminates Node 20 deprecation warnings).
- Removed a stray diagnostic output file (`diag_output.txt`) from tracking.

