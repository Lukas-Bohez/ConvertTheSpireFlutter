# Release Notes - v16.4.0

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
