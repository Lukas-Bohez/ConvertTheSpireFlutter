# Release Notes - v13.1.1

## Browser stability and code quality improvements

## Fixes

* **Fixed all Flutter analyzer errors.** Resolved 93 analyzer issues including class declarations inside abstract class, missing dispose() method, undefined clearCookies() method, and deprecated API usage.
* **Fixed deprecation warnings in third-party webview_windows.** Updated color.value.toSigned(32) to color.toARGB32(), replaced deprecated window.devicePixelRatio with View.of(context), and updated SDK constraint to >=2.15.0.
* **All 79 tests passing.** Verified test suite passes after all fixes.

## Improvements

* **Better code quality.** All classes (BrowserPageEvent, BrowserJsMessage, BrowserErrorEvent, BrowserHistoryState, BrowserWebViewHooks) and typedef BrowserOffset moved outside the abstract class for proper Dart structure.
* **Proper resource cleanup.** Added dispose() method to BrowserWebviewController abstract class interface.
* **Modern API usage.** All deprecated APIs replaced with current alternatives throughout the codebase.

## Build Notes

* GitHub release tag: v13.1.1
* Release page: [v13.1.1](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.1.1)
* `flutter analyze` clean; all 79 tests pass; release workflow builds Windows, Linux, macOS, Android, and web artifacts.

