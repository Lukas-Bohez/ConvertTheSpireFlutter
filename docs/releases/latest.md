# Release Notes - v14.3.0

## Userscripts in the browser

### Added

* **Userscript support.** The browser now runs Greasemonkey/Tampermonkey userscripts. Install one by URL from somewhere like Greasy Fork, or paste the code in, and manage everything under **Browser menu → Userscripts**. Scripts can be switched on and off individually, updated in place, and there is a master switch for all of them.

  The `// ==UserScript==` header is parsed the way Tampermonkey parses it: `@match`, `@include`, `@exclude`, `@run-at`, `@grant`, `@name`, `@version`, `@description` and `@downloadURL`. Chrome-style match patterns are supported, including `*://*.example.com/*`, as are `@include` globs and `/regular expressions/`. `@run-at document-start` runs before the page's own scripts; everything else runs once the DOM is ready.

  A `GM_*` shim is provided so most scripts run unmodified: `GM_addStyle`, `GM_getValue`, `GM_setValue`, `GM_deleteValue`, `GM_listValues`, `GM_log`, `GM_info`, `GM_openInTab`, `GM_setClipboard`, `GM_xmlhttpRequest` and `unsafeWindow`, plus the promise-based `GM.*` equivalents. Stored values are namespaced per script so two scripts cannot tread on each other, and every script runs inside its own try/catch so a broken one logs an error instead of breaking the page.

* **Install by clicking a link.** Navigating to any `.user.js` URL now offers to install it, the way a userscript manager does, instead of showing you a wall of JavaScript. The prompt states plainly that userscripts run with full access to the pages they match, so only install from a source you trust.

* **`@require` and `@noframes`.** Libraries listed with `@require` (jQuery and friends) are downloaded at install time, cached, and inlined ahead of the script body — so a page load never waits on the network and the script keeps working offline. A library that fails to download is skipped rather than blocking the install. `@noframes` scripts run only in the top-level page, never inside iframes.

### A note on Chrome and Firefox extensions

This is **not** extension support, and it cannot become it. Extensions need the browser shell to implement the WebExtensions API — background workers, isolated content-script worlds, `declarativeNetRequest`, the tabs and permissions model, CRX/XPI loading. The app renders pages with the platform WebView (WebView2 on Windows, the system WebView on Android), which exposes no extension host at all; the binding has a `UserScript` type and no extension API whatsoever. Shipping real extension support would mean shipping a browser engine, which is a different project.

Userscripts cover a good share of what people actually install extensions for — site tweaks, layout fixes, quality-of-life patches — and ad and tracker blocking is already built in separately.

### Fixed

* **Release builds were failing to compile.** `flutter pub get` writes a plugin registrant that registers every plugin including dev-only ones (`integration_test`), while Gradle correctly leaves those off the release classpath — so the generated Java referenced a package that did not exist. Release builds now strip dev-dependency registrations before compiling, using Flutter's own `dev_dependency` flag as the source of truth. Debug builds are untouched, so integration tests still run.

### Improved

* The ad blocker's matching rules are now covered by tests, including the guard that stops a bare TLD from ever being blocked and the case where a lookalike domain merely ends with a blocked name.

### Build Notes

* Android Play AAB built with `--flavor play` (version 14.3.0+1294).
* `flutter analyze` clean; 251 tests pass, 39 of them covering userscript matching, parsing and injection.
* GitHub release tag: v14.3.0
* Release page: [v14.3.0](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v14.3.0)
