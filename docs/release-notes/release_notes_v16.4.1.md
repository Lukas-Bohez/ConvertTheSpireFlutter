# Convert the Spire Reborn v16.4.1

## The mouse wheel and the arrow keys work in the browser, and a new icon

### Fixed

- **The mouse wheel scrolls web pages again (Windows).** In 16.4.0 turning the wheel over a page did nothing on current versions of Microsoft Edge WebView2, which quietly dropped the wheel turns the app passed on. The app now hands them to the page the way a real mouse does, so the page, and any panel or box under the mouse, scrolls.
- **The arrow keys stay the TV remote after you click a page (Windows).** Once a page had been clicked it kept the keyboard, and the arrow keys scrolled it instead of moving the remote cursor, so the TV controls could not be tried on a PC. The arrow keys now move the cursor, Enter clicks where it is, and Page Up and Page Down scroll a screen at a time, as on a TV. In a text field on a page the arrow keys move the text cursor as usual, and Enter sends.

### New

- **A new app icon:** a play button with a download arrow, riding two waves on a blue-to-green tile. It replaces both older icons, on every platform and in the Play Store and Microsoft Store listings.
- **Ready for Flathub.** The Linux app has its Flathub id (`io.github.Lukas_Bohez.ConvertTheSpireFlutter`), menu entry and AppStream description. A Linux install moves its settings and library to the new id by itself on first start.

### Build Notes

- Wheel: `third_party/webview_windows/windows/webview.cc` `SetScrollDelta` sends DevTools `Input.dispatchMouseEvent` (`mouseWheel`, CSS pixels = logical / zoom factor) and falls back to `SendMouseInput`; WebView2 accepts a `SendMouseInput` wheel (S_OK) but never delivers it to the page.
- Remote keys on Windows: the plugin's `AcceleratorKeyPressed` handler takes arrows and Page Up/Down (no Shift/Ctrl/Alt) from the page while `setRemoteKeys(true)` and emits `remoteKey`; `BrowserWindowsWebViewAdapter` turns it into a `remoteKey` page message and switches it off while a page text field has focus (`InputFocusChannel`). Enter is taken by a capture-phase `keydown` listener in the document-created script. `GlobalCursorOverlay.handleRemoteKey` handles both. Test: `integration_test/browser_windows_test.dart` (real WebView2; keys are posted to the test's own focused window).
- Icon: `scripts/make_app_icons.py` draws it (SVG + every PNG/ICO, the launcher icons of all three Android flavors with an image background layer); `flutter_launcher_icons` and `scripts/generate_full_icons.py` are gone. `store/google-play/build_store_assets.py` makes the banners and the Play icon from it; `scripts/play_tv_checks.py` checks the new adaptive layers.
- Linux id: `APPLICATION_ID` is `io.github.Lukas_Bohez.ConvertTheSpireFlutter`; `lib/src/services/linux_app_id.dart` moves `~/.local/share` and `~/.config` folders from `com.example.convert_the_spire_reborn`. `linux/packaging/` holds the desktop file and metainfo; inside a Flatpak the app does not update itself or write menu entries. Submission guide: `docs/publishing/flathub.md`.
