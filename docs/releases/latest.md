# Release Notes - v13.0.15

## Player tag glitch + button-height clamp fixes

## Fixes

* **Player — genre filter chips overflowing the pinned header into the grid (the "people / blogs / music tags glitch").** The genre chips lived in a `Wrap` inside the search bar, which sits in a **fixed-height pinned `SliverPersistentHeader`**. When the library had many genres (People, Blogs, Music, …) the wrapped chips exceeded the header's fixed height and — nothing clipped them — so they painted *over* the media grid below. The chips are now a single horizontally-scrollable row (every genre reachable, none overflow), the pinned header child is wrapped in a `ClipRect` so any overflow is clipped rather than drawn over the body, and the header height was corrected to actually fit one search row + one chip row (mobile 128 → 72, desktop 88 → 112).
* **Button-height cap clipping intentional taller buttons (regression from v13.0.12).** The unified button theme capped every button at 40 px tall with `maximumSize`, which clamped any button that deliberately sets a larger size via `styleFrom`: the circular play/pause button (minimumSize 48 clipped to 40) and the full-width Search / Preview + Download buttons (padding 16 clipped to 40, cropping their labels). Removed the `maximumSize` cap — keeping only the 40 *floor* — so sibling buttons stay consistent while genuinely taller buttons render at real height again. The v13.0.14 empty-state buttons stay even (all `OutlinedButton.icon`, 18 px icons).

## Confirmed (live run on the main PC)

* `deno-runtime: using provisioned Deno` finds the existing binary on launch (no re-download) — the v13.0.13 fix holds at runtime.
* No `metadata_god` `ZONE ERROR` on startup/library access — the `flutter_rust_bridge` 2.11.1 pin holds at runtime.

## Build Notes

* GitHub release tag: v13.0.15
* Release page: [v13.0.15](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.15)
* flutter analyze passes cleanly; all 30 tests pass; the app launches and runs for 15 s without crashing; Windows release and Play AAB (flavor `play`, `com.torrentspire.ai`, v13.0.15+1278) built locally and verified.
