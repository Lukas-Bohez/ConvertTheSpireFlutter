# Google Play store assets

Everything the Play Console listing serves lives here, so updating the store
page is a one-stop job. **All images are generated from the real logo and the
real screenshots by one script**, so they can never drift apart.

| File | Purpose | Play Console slot |
|---|---|---|
| `app-icon-512.png` | Store icon (opaque, 512x512) | Main store listing -> App icon |
| `tv-banner-1280x720.png` | Android TV banner | Graphics -> TV banner |
| `tv-screenshot-1-1920x1080.png`, `tv-screenshot-2-...png` | TV screenshots | Graphics -> TV screenshots |
| `tv-promo-banner-1920x1080.png` | Promo image | optional promo graphic |
| `build_store_assets.py` | Regenerates everything | - |

## Updating the store graphics
1. To change wording, edit the constants at the top of `build_store_assets.py`
   (`TITLE`, `BULLETS`, ...). To change which screenshots are used, edit
   `promo_banner()` / `main()`.
2. From the repo root run `python store/google-play/build_store_assets.py`
   (needs `pip install pillow`).
3. Upload the PNGs from this folder in Play Console.

The script also rewrites, in one go:
- `docs/screenshots/banner.png` - a copy of the promo image. GitHub releases
  deliberately do **not** show a banner; they open with the demo video.
- `android/app/src/main/play_tv_assets/` - copies of the TV images.
- `android/app/src/play/res/` - the **launcher icons** (adaptive foreground with
  the logo inside the safe zone + opaque background colour + legacy icons) and the
  in-app **Android TV banner** (`android:banner`). The TV banner is also written
  to `android/app/src/main/res/` for the GitHub (full) flavor.

Rebuild the AAB after running it so the new launcher icon/banner ship in the app.

## Where the source material lives
- **Logo (source of truth):** `assets/icons/bitplayer-source-1024.png`
- **Real app screenshots:** `screenshots/*.webp`
- **Windows/desktop app icon:** `assets/icons/app_icon_fixed.png` (via `flutter_launcher_icons.yaml`)
- **GitHub release layout:** `docs/releases/release_body_template.md`
- **Demo video:** https://youtu.be/66Rx8PDY_r0

## Not covered here
The GitHub (full) flavor keeps its own launcher icon in `android/app/src/full/res/`.
