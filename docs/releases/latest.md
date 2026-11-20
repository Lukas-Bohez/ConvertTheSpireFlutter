# Release Notes - v16.4.1

## The mouse wheel and the arrow keys work in the browser, and a new icon

### Fixed

- **The mouse wheel scrolls web pages again (Windows).** In 16.4.0 turning the wheel over a page did nothing on current versions of Microsoft Edge WebView2, which quietly dropped the wheel turns the app passed on. The app now hands them to the page the way a real mouse does, so the page, and any panel or box under the mouse, scrolls.
- **The arrow keys stay the TV remote after you click a page (Windows).** Once a page had been clicked it kept the keyboard, and the arrow keys scrolled it instead of moving the remote cursor, so the TV controls could not be tried on a PC. The arrow keys now move the cursor, Enter clicks where it is, and Page Up and Page Down scroll a screen at a time, as on a TV. In a text field on a page the arrow keys move the text cursor as usual, and Enter sends.

### New

- **A new app icon:** a play button with a download arrow, riding two waves on a blue-to-green tile. It replaces both older icons, on every platform and in the Play Store and Microsoft Store listings.
- **Ready for Flathub.** The Linux app has its Flathub id (`io.github.Lukas_Bohez.ConvertTheSpireFlutter`), menu entry and AppStream description. A Linux install moves its settings and library to the new id by itself on first start.
