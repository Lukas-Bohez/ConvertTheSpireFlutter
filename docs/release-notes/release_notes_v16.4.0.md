# Convert the Spire Reborn v16.4.0

## Extensions on every device, and a browser that scrolls

### New

- **Chrome and Firefox extensions on Android, Android TV, Linux and macOS.** Install them from the Extensions screen (addons.mozilla.org) or from a .crx, .zip or .xpi file, as on Windows. On these devices an extension does what it adds to web pages: page themes and dark modes, site tweaks, YouTube and reading helpers, and it keeps its settings between pages and restarts. Extensions that work only through a toolbar popup, a background page or network blocking need a desktop browser engine; the app tells you before installing one of those, and ad blocking is built into the browser anyway. On Windows extensions run in full, as before.
- **The browser works on Linux.** It runs Chromium, drawn inside the app, so pages look as they do in Chrome, and the remote cursor, menus and dialogs stay on top of them. The Linux downloads are bigger because Chromium comes inside (about 290 MB).

### Fixed

- **Scrolling up with a TV remote works on every page.** On many sites the remote could scroll down but not back up: at the top edge the cursor sat over the site's fixed header, and the header does not scroll. Up and down now scroll whatever part of the page the cursor is over, the page itself when that part cannot move. Page Up and Page Down, and Channel Up and Down on a remote, scroll a screen at a time.
- **The mouse wheel scrolls where the mouse is (Windows).** The browser sent every wheel turn to the page's top-left corner, so chat boxes, comment panels and side menus never scrolled, and on some sites the page did not either.
- **Pages can reach the app again on Android, Android TV, iOS and macOS.** Since 13.0.10 nothing a page sent arrived: choosing a text field on a page, finding the video on a page and noticing that it plays all depend on it.

### Improved

- On Android phones and tablets a keyboard's or game controller's arrow keys and Enter go to the app as usual; only Android TV turns them into the remote cursor.

### Build Notes

- Extensions without an engine: `lib/src/browser/extensions/content_script_extension_host.dart` (install, registry, `chrome.storage` kept per extension in `web_extensions/storage/<id>.json`) and `content_scripts.dart` (manifest `content_scripts` matching, the `chrome`/`browser` API given to content scripts, `_locales`, `web_accessible_resources` as data: URLs up to 512 KB). `ExtensionHosts` picks it on every platform but Windows and the web. Tests: `test/browser/extensions/content_script_host_test.dart` runs the generated page code in Node; `integration_test/browser_linux_test.dart` runs an extension on real Chromium.
- `flutter_inappwebview` delivers `callHandler` only to handlers registered by name; 13.0.10 dropped the registrations. `jsBridgeHandlerNames` in `js_bridge.dart` lists them and the adapter registers each.
- Linux browser: `third_party/webview_cef` (webview_cef 0.6.2, CEF/Chromium 149, vendored and registered on Linux only), `BrowserCefWebViewAdapter`. The runner calls `initCEFProcesses` and forwards GTK key events; the plugin passes arrow keys and Enter to Flutter (the TV-remote simulator). CEF downloads at the first CMake configure (659 MB, cached in CI); `scripts/package_linux.sh` strips `libcef.so` and bundles the NSS modules. On Linux there are no network ad-block rules, navigation veto, screenshots or progress; pasting into pages needs `xclip`.
- Scrolling: `lib/src/browser/js/scroll_bridge.dart` scrolls the element under the cursor (or the last one scrolled, then the page). `GlobalCursorOverlay` is the only owner of the remote keys (the second `cursor_overlay.dart` is gone); `BrowserScreen.isActive` registers its callbacks only while the browser tab shows. `third_party/webview_windows/windows/webview.cc` `SendScroll` uses the last cursor position.
- `MainActivity.dispatchKeyEvent` sends D-pad, Enter, Page and Channel keys to Flutter on TVs only.
