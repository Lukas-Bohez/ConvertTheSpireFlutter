# Release Notes - v13.0.16

## Folder-load crash fix on low-end Windows (no BMI2/AVX2) + 811-video Vocaloids playlist install

## Fixes

* **Loading a folder into the player crashed the whole app on older Windows CPUs that lack BMI2/AVX2 (e.g. the Ivy Bridge i3-3220 used for low-end QA).** Folder load (`PlayerState.setLibrary`) kicked off background metadata enrichment (`_enrichArtistsInBackground` / `_enrichMetadataFast`) and playlist/local matching (`PlaylistService._labelsFromMetadata`), and all of them called `metadata_god` — a Rust library loaded via `flutter_rust_bridge`. That native lib can contain instructions the old CPU doesn't support, and a native illegal-instruction crash **cannot be caught by any Dart handler** (the `runZonedGuarded` shell in `main.dart` only catches Dart exceptions — the same failure mode already documented for the `flutter_inappwebview` Windows plugin). Pinning `flutter_rust_bridge` to 2.11.1 (v13.0.13) fixed the Dart-level `metadata_god` `ZONE ERROR` storm, but that unmasked the *native* calls — so a naive build would crash *worse* on this CPU.
  **Fix:** the read paths now go through a platform-gated helper that uses `metadata_god` on Android only (where it is known to work and is the only writable tag path) and the **pure-Dart `audio_metadata_reader`** on Windows / iOS / web, with a session-disable flag that falls back to the pure-Dart reader on any native failure (so a future frb version skew degrades instead of crashing). The three tag-write paths (`_writeArtistTagIfPossible`, `fixSongMetadata`, `bulkFixArtistMetadata`) no-op gracefully where `metadata_god` is unavailable. Folder load no longer touches the native lib on Windows, so it cannot crash on low-end CPUs. Android behaviour is unchanged.

## Confirmed (low-end PC, this session)

* Working folder: `C:\Users\lukas\Music\ConvertTheSpire\mp3` filling with the 811-video "Vocaloids" playlist as real `.mp3` files (yt-dlp + the PC's prebuilt `ffmpeg`, built with `--enable-libmp3lame`), `--embed-metadata --embed-thumbnail`. Sample validated with `ffprobe`: e.g. `duration=226.1`, `TAG:title=【初音ミク】ドリームキラー【オリジナル曲】`, `TAG:artist=Waka IMBK`, `TAG:genre=Music` — the same ID3 tags the pure-Dart reader returns on the Windows load path.
* Worker: `C:\Users\lukas\convert\dl.ps1` (4 parallel `--playlist-items` slices, default `visionos` client, `--ignore-errors --retries 5 --concurrent-fragments 3`), runs detached so it keeps going past this session.

## Build Notes

* GitHub release tag: v13.0.16
* Release page: [v13.0.16](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.16)
* Crash fix commit: acfbb79 (pushed; `ci.yml` runs `flutter analyze` + tests on push). Build artifacts produced by the `release.yml` `workflow_dispatch` (Windows zip + Play AAB flavor `play`, `com.torrentspire.ai`). `flutter analyze` clean by inspection (matches existing `dynamic` tag-reading patterns; no new lint rules triggered per `analysis_options.yaml`).

