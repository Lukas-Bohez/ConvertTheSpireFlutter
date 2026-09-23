# Extensions: findings

Issue #10, hard rule 7: every unexpected platform limitation, recorded as it
was hit. This file is research data. Dates are when the finding was made;
versions are what was installed then.

Test machine: Windows 11 Pro 10.0.26200, WebView2 SDK 1.0.4191.47, the
evergreen WebView2 runtime current on 2026-09-23.

## Windows (WebView2)

### It works, and it is the engine doing the work

Measured with `integration_test/webextension_webview2_test.dart` against a
page served from a local fixture server, on a fresh profile:

| Check | Result |
|---|---|
| Environment accepts `AreBrowserExtensionsEnabled` | yes |
| Dark Reader 4.9.132 (Chrome MV3 build) recolours a white page | yes: `data-darkreader-mode` set, body background `rgb(24, 26, 27)` |
| Dark Reader stops when disabled | yes: attribute gone on reload |
| uBlock Origin Lite 2026.920.1710 (Edge build) blocks a tracking pixel | yes, while a control image from an unblocked host loads |
| The app's own document-start script still runs with extensions installed | yes |
| An extension's popup page opens in a plain webview (`chrome-extension://<id>/ui/popup/index.html`) | yes, and it renders |
| Both extensions still installed and active after an app restart | yes |

The raw results line from the install run:

    {"environmentAcceptedExtensions":true,
     "darkReaderMarkedPage":true,"bodyBackground":"rgb(24, 26, 27)",
     "trackingPixel":"blocked","controlImage":"loaded",
     "adsbygoogleScript":"loaded","appDocumentScriptRan":true,
     "darkReaderAfterDisable":false,
     "popupHref":"chrome-extension://mgjkokfehglainjbpemofahjckjffljb/ui/popup/index.html",
     "popupRendered":true}

and from the restart run:

    {"persistedAfterRestart":["Microsoft Clipboard Extension:true",
     "uBlock Origin Lite:true","Dark Reader:true","Microsoft Edge PDF Viewer:true"],
     "darkReaderActiveAfterRestart":true,"adBlockedAfterRestart":"blocked"}

### "The ad script loaded" did not mean the blocker failed

The first probe was a `<script>` for `adsbygoogle.js`, and its `onload` fired
with uBOL installed. uBOL's rulesets were all enabled (`ublock-filters`,
`easylist`, `easyprivacy`, `pgl`, `ublock-badware`, `urlhaus-full`), and all
949 of its session rules were `redirect` rules. uBlock does not block
`adsbygoogle.js`; it redirects it to a harmless surrogate so pages that
expect it do not break, and a surrogate fires `onload`. An ad *script* is a
poor probe for an ad blocker. A tracking pixel, with a control image beside
it, is a good one.

### WebView2 lists its own built-ins as extensions

`GetBrowserExtensions` returns **Microsoft Edge PDF Viewer** and **Microsoft
Clipboard Extension** alongside what the app installed, and they can be
disabled or removed through the same calls. The app never shows them: the
Extensions screen lists only what its own registry says it installed.

### An unpacked extension's id comes from its folder path

Dark Reader loaded from `.../unpacked/darkreader-mv3` got id
`mgjkokfehglainjbpemofahjckjffljb`, not its Chrome Web Store id. Installing the
same extension from another folder gives another id, and an extension's
stored settings are keyed by id. So every extension gets a stable folder,
named after its AMO guid, its Gecko id, or its name, and reinstalling or
updating lands in the same place. Verified: a reinstall kept the id.

### Firefox builds are accepted by WebView2 - which is not the same as working

Both Firefox builds tried were accepted by `AddBrowserExtension` without an
error:

- Dark Reader's Firefox build (MV2, `background.page`)
- Lofi Player 1.0.1 from AMO (MV2, `background.scripts`)

Accepted is not working (hard rule 6), and neither was checked further here;
that is the compatibility study's job. The only up-front refusal the app
makes is the one certain failure: an MV3 manifest with `background.scripts`
and no `background.service_worker` is a Firefox-only build, and Chromium will
not run it.

### A toolbar button without a popup cannot be pressed

An extension whose `action`/`browser_action` has no `default_popup` reacts to
`action.onClicked`, which only a browser toolbar sends. WebView2 has no
toolbar and no API to send that event, so for those extensions the app shows
a note instead of a button. Lofi Player is one of them.

### The environment option is fixed for the process, and shared

The option has to be set before the environment exists, and WebView2 allows
one environment per process. Connecting to a browser process that already
has the same user data folder open with a different value fails. The plugin
now tries with extensions on and falls back to off, so the browser itself
never breaks; the Extensions screen then says to restart.

### Two plugins shared one SDK folder

`nuget install ... -ExcludeVersion` skips the install when a folder of the
same name exists, and `flutter_inappwebview_windows` installs WebView2 SDK
1.0.2792.45 into the same `build/.../packages/Microsoft.Web.WebView2` folder
that `webview_windows` used. Which SDK `webview_windows` compiled against
depended on which plugin built first, and a version bump in one build
directory never took effect. The plugin's package folders now carry their
version.

## Found along the way

### Userscripts never ran on Windows

Hard rule 1 says extensions must not break userscripts. Checking that showed
there was nothing to break on Windows: the Windows adapter never called the
`userScriptsFor` hook the browser gives every adapter, so userscripts have
done nothing there since they shipped in 14.3.0. Fixed, and the Windows
browser integration test now fails against the old adapter.

## The compatibility scanner

`tools/ext_api_scan` counts direct `chrome.X` / `browser.X` references and
reads each manifest. Run on the four fixtures (`results/extensions/pilot/`),
it showed its own blind spot: uBlock Origin Lite's row has no
`declarativeNetRequest`, the API it is built on, because it reaches the API
through a wrapper (`const webext = self.browser || self.chrome`). A static
count undercounts extensions written that way; an empty cell means "not
called directly", not "not used". The study should treat the matrix as a
lower bound and confirm key APIs by running the extension.

Without a namespace allow-list the scanner also counted URLs such as
`chrome.google.com` as an API called `google`; it now only counts the
namespaces in Chrome's and Firefox's API references.

## addons.mozilla.org

- Translated fields come back as a locale map even when `lang` is set, and
  the requested locale can be `null` in it. Lofi Player's name, requested as
  `en-US`: `{"nl": "Lofi Player", "en-US": null, "_default": "nl"}`. The
  client falls back to the add-on's own default locale.
- The file URL depends on the `app` parameter (`/firefox/downloads/...` or
  `/android/downloads/...`) for the same file id.
- `file.hash` is published as `sha256:<hex>`. Downloads are checked against
  it; a tampered hash was refused in the integration test.

Details and sample responses: `amo-api.md`.

## Lofi Player (the owner's fixture) on Android

From the AMO package, version 1.0.1 (44.15 MB, 51 entries, MIT):

    manifest_version: 2
    background: {"scripts": ["background.js"]}
    browser_specific_settings: {"gecko": {"id": "lofi-player@quizthespire.com",
      "strict_min_version": "142.0", ...}}
    permissions: ["storage"]
    browser_action: {"default_title": "Lofi Player"}      (no default_popup)
    commands: absent
    web_accessible_resources: ["player.html", "assets/tracks.json",
      "lofi/*.mp3", "lofi/*.mp4"]

Grep across its JavaScript for `windows.`, `commands` and `onCommand`:

    background.js:13  const window = await browserAPI.windows.get(playerWindowId);
    background.js:15  browserAPI.windows.update(playerWindowId, { focused: true });
    background.js:29  const window = await browserAPI.windows.create({
    background.js:49  browserAPI.windows.onBoundsChanged.addListener(boundsListener);
    background.js:53  browserAPI.windows.onRemoved.addListener((windowId) => {

No `commands` key and no `onCommand`. Keyboard control is an in-page
`keydown` handler (`player.js:963`), which is what a remote's D-pad needs.

What this means on Android, where there is no `windows` API:

1. `background.js:53` calls `browserAPI.windows.onRemoved.addListener` at the
   top level. `browser.windows` is undefined, so the background script throws
   while loading. The click listener registered on line 9 survives, but:
2. its first action is `windows.get` or `windows.create`, which throw too. The
   button does nothing.

The fix is on the extension side (the owner's list already covers it): guard
every `windows.*` use, including the top-level listener, and fall back to
`tabs.create({url: 'player.html'})`. A popup (`default_popup`) would also
make it reachable in WebView2, which cannot press a popup-less button.
