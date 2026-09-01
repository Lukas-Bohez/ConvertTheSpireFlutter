# BitPlayer / Convert the Spire Reborn — Feature Backlog
## Companion reference doc for `masterprompt_extra.md` (the secondary Sept 1 masterprompt). Each item below is tagged with its build status and, where covered by a more detailed plan, a cross-reference to the specific workstream folder — see the directory `README.md` for the full layout.

**Reference doc for the September 1 handoff. Status tags: [EXISTS]** already built, nothing new needed · **[EXISTS — GAP]** built but has a specific known gap · **[VERIFY]** appears to exist or be excluded but isn't confirmed · **[NEW]** not found in the codebase, treat as a real ask.

---

## Compliance & risk

- **[VERIFY] Mining subsystem on the Play build.** `lib/src/services/tray_service.dart` still references a miner/wallet subsystem (`wallet_constants.dart`) from an older release (the `5.0.0` changelog entry describes "miner auto-resume," a native miner subprocess, and a first-run mining-consent dialog). It's desktop-only by virtue of living in `tray_service.dart` (no system tray on Android), but no `kPlayStoreBuild` / `isPlayFlavor` gate was found explicitly excluding it. **Google Play prohibits on-device crypto mining outright.** **Confirm this is unreachable on the `com.torrentspire.ai` Play package with an explicit, defensive check — not just an accident of platform capability — and remove it from that build if it's still functional.** This is the one item here that could get the Play listing pulled, so it comes before anything else.
- **[VERIFY] Torrents on the Play build.** **No gating on torrent screens/routes was found the way `kYouTubeConversionEnabled` gates YouTube conversion.** Worth a deliberate decision: does BitPlayer on Play stay a torrent client, or does that get restricted the same way YouTube conversion was, given Play's stricter stance on apps enabling arbitrary P2P downloads?

---

## AI copilot (Ollama)

- **[EXISTS]** `AiCopilotService` (`lib/src/vault/services/ai_copilot_service.dart`) is a real Ollama REST client — `/api/tags`, `/api/pull` with streaming, model listing/checking.
- **[EXISTS]** The base URL is user-configurable and persisted via `SettingsService` (`aiOllamaUrl`, `setAiOllamaUrl`), with an Android-specific default constant (`kAndroidLocalOllamaUrl`) separate from the desktop `localhost:11434` default.
- **[EXISTS — GAP] Android connectivity UX.** Ollama has no native Android app — on-device it only runs through Termux, which isn't something to bundle into a Play Store app. **The plumbing above already supports pointing the app at a remote Ollama host**, so the actual "Ollama for more platforms, like Android" ask is UX, not architecture:
  - A settings surface for the Ollama connection (URL field, test-connection action using the existing `checkVersion()`, clear error/disconnected states) if one isn't fully built out yet.
  - **LAN auto-discovery** so Android users don't hand-type an IP — `multicast_dns` is already a dependency for DLNA/Chromecast/AirPlay discovery; the same mDNS pattern could discover an Ollama host on the network.
  - Make sure onboarding/docs tell desktop users to set `OLLAMA_HOST=0.0.0.0` so a phone on the same Wi-Fi can actually reach it (Ollama binds to localhost only by default).
- **[NEW, optional]** True on-device inference as a fallback when no LAN host is reachable — a Flutter FFI plugin like `llamadart` (Android/iOS/macOS/Linux/Windows/web, wraps llama.cpp/GGUF) would let a small quantized model run directly on the phone. Lower priority than the LAN story above.

---

## Torrenting

- **[EXISTS]** A genuinely deep BitTorrent implementation: DHT (`bittorrent/dht.dart`), piece manager, isolate-based background transfer, torrent creation (`torrent_creator_service.dart`, has a passing smoke test), a DB-backed torrent list (`torrents_dao.dart`), and dedicated screens (`torrents_screen.dart`, `torrent_detail_screen.dart`, `create_torrent_screen.dart`). Built on `dtorrent_task_v2` / `bittorrent_dht` / `dtorrent_common`, not a from-scratch protocol implementation.
- **[UNAUDITED]** No full pass done on completeness — worth an inventory of what's fully wired vs. stubbed, the seeding story (ratio/time limits, seed-after-download toggle), and per-torrent bandwidth controls before promising anything new here.
- **[NEW]** **Unify magnet-link paste with the existing "paste a link" flow used for YouTube playlists/yt-dlp URLs, if it isn't already, so there's one mental model for "add something to download."** → **covered by `masterprompt_extra.md`** §2 and `playlist-reliability/playlist-reliability-mega-update-plan.md` Tier 1 item 2.1.

---

## Cinematic view

- **[EXISTS — GAP]** Full-screen animated ambient background exists (`assets/shaders/ambient_scene.frag`) but needs rework: star lighting currently reads as predictable/rhythmic blinking and should be non-rhythmic/random instead; sun/moon should stay at least partly visible at all times; add clouds; improve rain with puddle pooling; remove the "bunny" element.
- **[NEW]** Use the finished cinematic view to auto-generate thumbnails for songs/videos that don't have one. → **covered by `MASTERPROMPT.md`** (section 3) + `ambient_scene.frag` + `cinematic_and_player.patch`.
- **[EXISTS — GAP]** Known bug: the now-playing popup thumbnail stretches 16:9 into a square instead of cropping. A fix for the grey-screen-on-transport-controls-fade bug was prepared but pending confirmation as of last check — verify it landed. → **covered by `MASTERPROMPT.md`** (verification checklist) + `cinematic_and_player.patch`.

---

## Browser & onboarding

- **[NEW]** Browser redesign: auto-hide the bottom bar; show the search/URL bar only on explicit tap. → **covered by `browser-onboarding-redesign/BROWSER_UX_REDESIGN.md`** + implementation files.
- **[NEW]** Onboarding redesign: cut down from 14 screens; fix the Android TV layout running off-screen. → **covered by `browser-onboarding-redesign/ONBOARDING_UX_REDESIGN.md`** + implementation files.

---

## Downloading & playlists

- **[NEW]** Get yt-dlp and youtube_explode_dart cooperating more reliably specifically for playlist downloads — fewer failures, an easier UI, better discoverability of the feature across platforms. → **covered by `playlist-reliability/playlist-reliability-mega-update-plan.md`** (Tier 1 items 2.1–2.4)
- **[NEW]** Watched playlists should auto-download missing tracks on app open, not just on manual trigger. → **covered by `playlist-reliability/playlist-reliability-mega-update-plan.md`** (Tier 1 item 2.5)
- **[NEW]** Make favourited/disliked status more visible in the player UI. → **covered by `MASTERPROMPT.md`** (section 4) + `cinematic_and_player.patch`.

---

## Player UX — newer ideas, not yet scoped

Confirmed **not** in the codebase (equalizer, sleep timer, and lyrics already exist, so they're off this list):

- Crossfade / gapless playback between tracks
- Playback speed control and A-B loop, especially for video
- Podcast/RSS subscriptions, separate from one-off downloads
- Cookie import (yt-dlp `cookies.txt`) for gated/private/age-restricted content

---

## Cross-device & platform reach — newer ideas, not yet scoped

- Sync playlists, favourites/dislikes, and playback position between phone, Android TV, and desktop — casting already covers "play on another screen," this is about shared state, not playback
- Android Auto integration
- A storage dashboard (space used by downloads, orphaned-file cleanup) and lightweight listening stats

---

## Platform strategy

- **[CARRIED OVER]** Narrow the gap between the Play build (BitPlayer, `com.torrentspire.ai`) and the GitHub build (Convert the Spire Reborn) where policy allows, so the two diverge only where Play compliance actually requires it — the torrent-gating and mining-gating decisions above are part of this.

---

**This is a companion reference doc for `masterprompt_extra.md` (the secondary Sept 1 masterprompt).** Each item below is tagged with its build status and, where covered by a more detailed plan, a cross-reference to the specific workstream folder — see the directory `README.md` for the full layout.

---

**This is a generation task, not an implementation task.** Do not write the actual Dart/Go/JS code for the fixes — the Sept 1 agent does the coding. Write masterprompts and spec docs that tell the agent what to build.
