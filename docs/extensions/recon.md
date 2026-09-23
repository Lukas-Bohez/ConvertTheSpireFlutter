# Extensions: recon (Phase 0)

Issue #10, Phase 0. Where everything relevant lives, what the engines are, and
what the Android track needs before any code is written for it. Every path
below exists in the repo at the commit that added this file.

## Engines, per platform

| Platform | Engine | Selected in | Extension host |
|---|---|---|---|
| Windows | Microsoft Edge WebView2, through the vendored `third_party/webview_windows` | `lib/src/browser/platform/browser_webview_factory.dart` | WebView2's own, implemented (see below) |
| Android, Android TV | Android System WebView, through `flutter_inappwebview` | same | none; GeckoView is the planned route |
| macOS | WKWebView, through `flutter_inappwebview` | same | WKWebExtension, macOS 15.4+, not built |
| Linux | none (not distributed) | same | out of scope |

## Files

**Browser**

- `lib/src/screens/browser_screen.dart` - the browser screen; wires hooks, menu actions, userscripts.
- `lib/src/screens/browser/browser_toolbar.dart` - toolbar and overflow menu; hosts the extension button.
- `lib/src/browser/platform/browser_webview_controller.dart` - the adapter interface and `BrowserWebViewHooks`.
- `lib/src/browser/platform/browser_webview_windows.dart` - WebView2 adapter.
- `lib/src/browser/platform/browser_webview_inappwebview.dart` - Android, iOS and macOS adapter.
- `lib/src/browser/platform/webview2_environment.dart` - the one WebView2 environment per process, shared by the browser and the extension host.

**Userscripts**

- `lib/src/browser/userscripts/userscript.dart` - parsing and `@match`/`@include` matching.
- `lib/src/browser/userscripts/userscript_service.dart` - storage and `injectionsFor(url, runAt:)`.
- `lib/src/screens/browser/userscripts_screen.dart` - management UI.

**Ad and tracker blocking**

- `lib/src/browser/adblock/adblock_service.dart` - EasyList download and domain list.
- Android: `shouldInterceptRequest` in `browser_webview_inappwebview.dart`.
- Windows: a fetch/XHR hook injected at document creation, in `browser_webview_windows.dart`.

**Extensions (added for this issue)**

- `lib/src/browser/extensions/web_extension_host.dart` - the shared `WebExtensionHost` interface and `UnsupportedExtensionHost`.
- `lib/src/browser/extensions/webview2_extension_host.dart` - the Windows backend.
- `lib/src/browser/extensions/extension_package.dart` - CRX3/zip/xpi/folder reading, extraction, Chromium preflight.
- `lib/src/browser/extensions/amo_catalog.dart` - addons.mozilla.org client.
- `lib/src/browser/extensions/extension_hosts.dart` - picks the backend for the platform.
- `lib/src/screens/browser/extensions_screen.dart`, `extension_page_dialog.dart` - UI.
- `third_party/webview_windows/windows/webview.cc`, `webview_host.cc`, `webview_bridge.cc` - native extension calls.

## WebView2 SDK

The vendored plugin built against SDK **1.0.1210.39**, which has neither
`ICoreWebView2EnvironmentOptions6` (`AreBrowserExtensionsEnabled`) nor
`ICoreWebView2Profile7` (`AddBrowserExtension` and friends). Both arrived in
1.0.2210. The plugin now pins **1.0.4191.47**, set in
`third_party/webview_windows/windows/CMakeLists.txt`.

## How userscripts are injected

| Platform | Document start | Document end |
|---|---|---|
| Android | `onLoadStart` evaluates each matching script | `onLoadStop` evaluates each |
| Windows | `LoadingState.loading` executes each matching script | `LoadingState.navigationCompleted` executes each |

On Windows this is new: the adapter never called the hook, so userscripts did
nothing there since they shipped in 14.3.0 (see `findings.md`).

## Android track

- App `minSdk` is **24**; `targetSdk` 36.
- ABIs built: `armeabi-v7a`, `arm64-v8a`, `x86_64` (`android/app/build.gradle.kts`).
- The browser tab ships in **both** the Play AAB and the sideload APK; only
  casting is gated off in the Play build.
- GeckoView to pin: **156.0.20260921121718**, the latest on
  `maven.mozilla.org` on 2026-09-23. Since Firefox 144 it needs Android 8.0
  (API 26) and no longer builds 32-bit x86; 32-bit ARM is kept. The app's
  three ABIs are all available, but GeckoView needs `minSdk` 26, so the
  APK would need `tools:overrideLibrary` plus a runtime API check to keep
  the System WebView browser for Android 7.
- Licence: GeckoView is MPL-2.0. MPL-2.0 is GPL-compatible through its
  Secondary License clause *unless* a file carries the "Incompatible With
  Secondary Licenses" notice. That has to be checked against the pinned
  GeckoView source before shipping it in a GPLv3 app; it has not been yet.
- Baseline tests that already exist for what GeckoView must not break:
  `test/browser/userscript_test.dart`, `test/browser/userscript_service_test.dart`,
  `test/browser/adblock_service_test.dart`.

GeckoView work has not started. The plan puts it on its own branch, APK
flavour only, behind a go/no-go the owner decides from size and memory
numbers, and the Play AAB never changes. See `findings.md` for what the Lofi
Player fixture needs before it can work there.
