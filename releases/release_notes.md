## What's New in v5.1.4

### Bug Fixes & Improvements
- Tab‑switcher sheet now unfocuses the URL field before opening, ensuring the selected tab actually activates instead of merely blurring the address bar.
- Browser toolbar forces a light appearance on mobile (Android/iOS) when not in incognito, preventing the UI from appearing perpetually dark under system dark mode.
- Added new theme logic to `BrowserToolbar` for better contrast on phones.

## What's New in v5.1.3

### Bug Fixes
- Prevent Windows build crash on startup by relocating WebView2 user data folder to %LOCALAPPDATA%.
- Added FFI call in main to set environment variable before WebView initialization.

## What's New in v5.1.2

### Bug Fixes
- Restored Browser tile on the home page and fixed pop-up selector issue: tapping a link now clears focus and navigates correctly.
- Browser quick-link now works when URL/search field is active.
- Minor UI polish and stability tweaks.
