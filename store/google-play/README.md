# Google Play store assets

Everything the Play Console listing serves lives here, so updating the store
page is a one-stop job.

| File | Purpose | Play Console slot |
|---|---|---|
| `tv-promo-banner-1920x1080.png` | Android TV promo image (real logo + real screenshot) | Graphics -> TV banner / promo |
| `build_tv_banner.py` | Regenerates the banner from the repo's real assets | - |

## Updating the banner
1. Edit the copy (`TITLE`, `BULLETS`, ...) or swap the screenshot path at the top of `build_tv_banner.py`.
2. From the repo root run `python store/google-play/build_tv_banner.py` (needs `pip install pillow`).
3. It rewrites `tv-promo-banner-1920x1080.png` **and** `docs/screenshots/banner.png`
   (the image shown at the top of every GitHub release), so both stay identical.
4. Upload the PNG in Play Console.

## Other assets and where they live
- **Logo source (proper logo):** `assets/icons/bitplayer-source-1024.png`
- **App/launcher icon:** `assets/icons/app_icon_fixed.png` (via `flutter_launcher_icons.yaml`)
- **Real app screenshots (README + releases):** `screenshots/*.webp`
- **Android TV assets currently bundled in the app:** `android/app/src/main/play_tv_assets/`
  (`tv_banner_1280x720.png`, `tv_screenshot_1/2_1920x1080.png`).
  **TODO:** the two `tv_screenshot_*` images still use the old AI-generated logo
  and should be replaced with images made from real screenshots before the next
  Play listing update.
- **Release notes shown on GitHub:** `docs/releases/release_body_template.md`
