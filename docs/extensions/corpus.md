# Extensions: proposed corpus for the compatibility study

Issue #10, Phase 2 (Phase 4 in the final plan). **Proposed, waiting for the owner’s approval** - the study does not start on this list until then.

Every row was looked up on addons.mozilla.org through its v5 API on 2026-09-23: the add-on exists, and version, daily users, Android compatibility and licence are what AMO reported that day. All are open source, so the study can be reproduced from their public releases.

Two things this list does **not** yet verify, and the study must:

- **A Chromium build.** The final plan prefers extensions that also ship one, for the WebView2 column. That is not on AMO and needs checking per project.
- **Licences marked "custom".** AMO shows a custom licence text; the project repositories need checking.

Firefox-only by design (Tree Style Tab, Sidebery, Multi-Account Containers, Tridactyl, Greasemonkey, FireMonkey) are included on purpose: they are the negative controls for the WebView2 column.

## Ad and tracker blocking

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| uBlock Origin | [ublock-origin](https://addons.mozilla.org/firefox/addon/ublock-origin/) | 1.75.0 | 11,127,483 | yes | GPL-3.0-only |
| AdGuard AdBlocker | [adguard-adblocker](https://addons.mozilla.org/firefox/addon/adguard-adblocker/) | 5.5.2.3 | 1,784,659 | yes | LGPL-3.0-only |
| Privacy Badger | [privacy-badger17](https://addons.mozilla.org/firefox/addon/privacy-badger17/) | 2026.9.15 | 1,859,295 | yes | GPL-3.0-only |
| Ghostery – Privacy Ad Blocker | [ghostery](https://addons.mozilla.org/firefox/addon/ghostery/) | 10.6.4 | 1,012,559 | yes | GPL-3.0-only |
| ClearURLs | [clearurls](https://addons.mozilla.org/firefox/addon/clearurls/) | 1.27.3 | 514,173 | yes | LGPL-3.0-only |
| LocalCDN | [localcdn-fork-of-decentraleyes](https://addons.mozilla.org/firefox/addon/localcdn-fork-of-decentraleyes/) | 2.6.86 | 19,018 | yes | MPL-2.0 |
| Decentraleyes | [decentraleyes](https://addons.mozilla.org/firefox/addon/decentraleyes/) | 3.0.2 | 248,191 | yes | MPL-2.0 |
| Consent-O-Matic | [consent-o-matic](https://addons.mozilla.org/firefox/addon/consent-o-matic/) | 1.1.5 | 129,923 | yes | MIT |
| I still don't care about cookies | [istilldontcareaboutcookies](https://addons.mozilla.org/firefox/addon/istilldontcareaboutcookies/) | 1.1.9 | 112,411 | yes | GPL-3.0-only |
| SponsorBlock - Skip Sponsorships on YouTube | [sponsorblock](https://addons.mozilla.org/firefox/addon/sponsorblock/) | 6.1.7 | 792,432 | yes | LGPL-3.0-only |
| uBlacklist | [ublacklist](https://addons.mozilla.org/firefox/addon/ublacklist/) | 10.0.4 | 39,668 | yes | MIT |
| NoScript Security Suite | [noscript](https://addons.mozilla.org/firefox/addon/noscript/) | 13.6.34 | 240,467 | yes | GPL-2.0-only |
| uMatrix | [umatrix](https://addons.mozilla.org/firefox/addon/umatrix/) | 1.4.4 | 14,547 | yes | GPL-3.0-only |
| Cookie AutoDelete | [cookie-autodelete](https://addons.mozilla.org/firefox/addon/cookie-autodelete/) | 3.8.2 | 156,744 | yes | MIT |

## Dark mode and appearance

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| Dark Reader | [darkreader](https://addons.mozilla.org/firefox/addon/darkreader/) | 4.9.131 | 1,324,137 | yes | MIT |
| Stylus | [styl-us](https://addons.mozilla.org/firefox/addon/styl-us/) | 2.4.14 | 134,682 | yes | GPL-3.0-only |
| Dark Background and Light Text | [dark-background-light-text](https://addons.mozilla.org/firefox/addon/dark-background-light-text/) | 0.7.7 | 24,229 | yes | MPL-2.0 |
| Midnight Lizard | [midnight-lizard-quantum](https://addons.mozilla.org/firefox/addon/midnight-lizard-quantum/) | 10.7.1 | 6,053 | yes | MIT |

## Userscript managers

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| Violentmonkey | [violentmonkey](https://addons.mozilla.org/firefox/addon/violentmonkey/) | 2.49.0 | 185,273 | yes | MIT |
| Greasemonkey | [greasemonkey](https://addons.mozilla.org/firefox/addon/greasemonkey/) | 4.14 | 155,988 | yes | MIT |
| FireMonkey | [firemonkey](https://addons.mozilla.org/firefox/addon/firemonkey/) | 3.8 | 1,778 | yes | MPL-2.0 |

## Translation

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| Simple Translate | [simple-translate](https://addons.mozilla.org/firefox/addon/simple-translate/) | 3.1.0 | 247,006 | no | MPL-2.0 |
| TWP - Translate Web Pages | [traduzir-paginas-web](https://addons.mozilla.org/firefox/addon/traduzir-paginas-web/) | 10.2.1.0 | 560,568 | no | MPL-2.0 |
| To Google Translate | [to-google-translate](https://addons.mozilla.org/firefox/addon/to-google-translate/) | 4.3.1 | 644,017 | no | MPL-2.0 |

## Password managers

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| Bitwarden Password Manager | [bitwarden-password-manager](https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/) | 2026.9.0 | 996,022 | no | GPL-3.0-only |
| KeePassXC-Browser | [keepassxc-browser](https://addons.mozilla.org/firefox/addon/keepassxc-browser/) | 1.10.3 | 145,112 | no | GPL-3.0-only |
| Proton Pass | [proton-pass](https://addons.mozilla.org/firefox/addon/proton-pass/) | 1.38.0 | 177,087 | no | GPL-3.0-only |

## Accessibility

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| Read Aloud: A Text to Speech Voice Reader | [read-aloud](https://addons.mozilla.org/firefox/addon/read-aloud/) | 1.81.1 | 224,547 | yes | GPL-3.0-only |
| Zoom Page WE | [zoom-page-we](https://addons.mozilla.org/firefox/addon/zoom-page-we/) | 19.13 | 17,968 | no | GPL-2.0-only |
| Video Speed Controller | [videospeed](https://addons.mozilla.org/firefox/addon/videospeed/) | 0.6.3.3 | 103,111 | yes | MIT |

## Page tweaking and productivity

| Extension | AMO | Version | Daily users | Android | Licence |
|---|---|---|---:|:---:|---|
| Vimium | [vimium-ff](https://addons.mozilla.org/firefox/addon/vimium-ff/) | 2.4.2 | 43,888 | no | MIT |
| Tridactyl | [tridactyl-vim](https://addons.mozilla.org/firefox/addon/tridactyl-vim/) | 1.25.1 | 4,927 | no | custom: check the repo |
| SingleFile | [single-file](https://addons.mozilla.org/firefox/addon/single-file/) | 1.26.4 | 89,807 | yes | custom: check the repo |
| Return YouTube Dislike | [return-youtube-dislikes](https://addons.mozilla.org/firefox/addon/return-youtube-dislikes/) | 4.0.6 | 904,321 | no | GPL-3.0-only |
| DeArrow - Better Titles and Thumbnails on YouTube | [dearrow](https://addons.mozilla.org/firefox/addon/dearrow/) | 2.3.10 | 33,774 | yes | LGPL-3.0-only |
| LibRedirect | [libredirect](https://addons.mozilla.org/firefox/addon/libredirect/) | 3.4.0 | 8,595 | yes | GPL-3.0-only |
| Auto Tab Discard | [auto-tab-discard](https://addons.mozilla.org/firefox/addon/auto-tab-discard/) | 0.7.3 | 95,402 | no | MPL-2.0 |
| Redirector | [redirector](https://addons.mozilla.org/firefox/addon/redirector/) | 3.5.3 | 18,340 | yes | MIT |
| FoxyProxy Standard | [foxyproxy-standard](https://addons.mozilla.org/firefox/addon/foxyproxy-standard/) | 9.8 | 216,716 | yes | GPL-2.0-only |
| floccus | [floccus](https://addons.mozilla.org/firefox/addon/floccus/) | 5.10.3 | 9,668 | no | MPL-2.0 |
| Web Scrobbler | [web-scrobbler](https://addons.mozilla.org/firefox/addon/web-scrobbler/) | 3.22.0 | 23,398 | no | MIT |
| Search by Image | [search_by_image](https://addons.mozilla.org/firefox/addon/search_by_image/) | 8.5.3 | 456,619 | yes | GPL-3.0-only |
| Terms of Service; Didn’t Read | [terms-of-service-didnt-read](https://addons.mozilla.org/firefox/addon/terms-of-service-didnt-read/) | 5.1.1 | 11,209 | yes | custom: check the repo |
| Augmented Steam | [augmented-steam](https://addons.mozilla.org/firefox/addon/augmented-steam/) | 4.8.3 | 63,476 | no | GPL-3.0-only |
| Tree Style Tab | [tree-style-tab](https://addons.mozilla.org/firefox/addon/tree-style-tab/) | 4.4.6 | 140,388 | no | custom: check the repo |
| Sidebery | [sidebery](https://addons.mozilla.org/firefox/addon/sidebery/) | 5.6.1 | 53,314 | no | MIT |
| Firefox Multi-Account Containers | [multi-account-containers](https://addons.mozilla.org/firefox/addon/multi-account-containers/) | 8.3.8 | 405,552 | no | MPL-2.0 |
| Joplin Web Clipper | [joplin-web-clipper](https://addons.mozilla.org/firefox/addon/joplin-web-clipper/) | 2.11.2 | 13,426 | no | MIT |
| Lofi Player | [lofi-player](https://addons.mozilla.org/firefox/addon/lofi-player/) | 2.0.0 | 4 | no | MIT |

49 extensions. Lofi Player, the owner’s own, is the first fixture rather than a corpus member and is listed for completeness.
