# Release Notes - v16.4.1

## The mouse wheel and the arrow keys work in the browser, and a new icon

### Fixed

- **The mouse wheel scrolls web pages again (Windows).** In 16.4.0 turning the wheel over a page did nothing on current versions of Microsoft Edge WebView2, which quietly dropped the wheel turns the app passed on. The app now hands them to the page the way a real mouse does, so the page, and any panel or box under the mouse, scrolls.
- **The arrow keys stay the TV remote after you click a page (Windows).** Once a page had been clicked it kept the keyboard, and the arrow keys scrolled it instead of moving the remote cursor, so the TV controls could not be tried on a PC. The arrow keys now move the cursor, Enter clicks where it is, and Page Up and Page Down scroll a screen at a time, as on a TV. In a text field on a page the arrow keys move the text cursor as usual, and Enter sends.
- **The remote's OK clicks like a finger or a mouse (Android TV and Windows).** It used to be a click made by a script in the page, in the middle of whatever was under the cursor. Browsers do not count such a click as yours for starting a video, going full screen or opening a window, and many sites ignore it altogether. OK is now a real touch on Android TV and a real mouse click on Windows, exactly where the cursor is. On a text field it opens the typing box, on Windows now too; a field you click with the mouse you type into directly.
- **Pages no longer pick a text field by themselves.** A page focusing its own search box as it loads no longer opens the typing box, and on Android TV the first press of OK no longer jumps into the page's first field.
- **The first page waits until the browser is ready (Windows).** On a busy PC the first page could open before the browser had finished setting up: without the ad blocker, without the browser identity sites expect, and with Enter typing into the page instead of clicking.

### New

- **A new app icon:** a play button with a download arrow, riding two waves on a blue-to-green tile. It replaces both older icons, on every platform and in the Play Store and Microsoft Store listings.
- **Ready for Flathub.** The Linux app has its Flathub id (`io.github.Lukas_Bohez.ConvertTheSpireFlutter`), menu entry and AppStream description. A Linux install moves its settings and library to the new id by itself on first start.
