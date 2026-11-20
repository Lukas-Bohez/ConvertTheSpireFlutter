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
| `feature-graphic-1024x500.png` | Feature graphic, from the phone screenshots (`scripts/play_feature_graphic.py`) | Main store listing -> Feature graphic |
| `screenshots/phone/*.png` (1080x1920) | Phone screenshots | Main store listing -> Phone screenshots |
| `screenshots/tablet/*.png` (2560x1440) | Tablet screenshots | 7-inch and 10-inch tablet screenshots |
| `screenshots/chromebook/*.png` (1920x1080) | Chromebook screenshots | Chromebook screenshots |
| `screenshots/tv/*.png` (1920x1080) | Android TV screenshots | Android TV screenshots |
| `listing/` | Title, short and full description and release notes in 18 languages (`scripts/play_listing.py`) | Main store listing, per language; the release's notes |

The screenshots and the trailer come from the real Play build on an
emulator: `scripts/play_tour.py` (see `docs/publishing/store-trailer.md`).
The trailer goes on YouTube and its link in Main store listing -> Video.

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
  the logo in the centre 69dp + a white background colour + legacy icons)
  and the in-app **Android TV banner** (`android:banner="@mipmap/banner"`). The TV
  banner is also written to `android/app/src/main/res/` for the GitHub (full) flavor.

Both follow Google's [Android TV icon and banner sizes](https://developer.android.com/design/ui/tv/guides/system/tv-app-icon-guidelines):
the banner is `mipmap-<density>/banner.png` from 160x90 (mdpi) to 640x360
(xxxhdpi), so 320x180 at xhdpi, and the legacy icon is 160x160 at xhdpi. Play
review rejects the TV app as having "no full-size app banner and/or icon" when
they are smaller, and the banner shows only the logo and the app name.

The app icon (a play button with a download arrow, riding two waves on a
blue-to-green tile) is drawn by `python scripts/make_app_icons.py`, which
writes the logo, the launcher icons of all three Android flavors, the Windows
`.ico`, the Linux/Flathub SVG and PNGs and `assets/icons/full-bleed-1024.png`.
Run it before this script when the icon changes. The launcher icon fills its
whole space: Play review turned down an earlier logo sitting small in a wide
margin ("Your icon does not fill the entire icon space"); CI checks the icon
and the adaptive layers (`scripts/play_tv_checks.py`). Upload the new
`app-icon-512.png` in Play Console along with the build that has the new icon.

Only the banners and screenshots have text. The icons can be regenerated on any
OS; the text needs the Windows fonts to look right.

Rebuild the AAB after running it so the new launcher icon/banner ship in the app,
then check it with `python scripts/verify_play_aab.py <aab>` (see the
[Play AAB build guide](../../docs/build/play-store-aab.md)).

## Where the source material lives
- **Logo (source of truth):** `scripts/make_app_icons.py` (it writes `assets/icons/app-icon.svg` and the PNGs)
- **Real app screenshots:** `screenshots/*.webp`
- **Windows/desktop app icon:** `assets/icons/app_icon_fixed.png` (MSIX) and `windows/runner/resources/app_icon.ico`, both from `make_app_icons.py`
- **GitHub release layout:** `docs/releases/release_body_template.md`
- **Trailer (the Windows app):** https://youtu.be/JfT052dU5mg

## Not covered here
The GitHub (full) flavor has the same launcher icon, in `android/app/src/full/res/`;
`make_app_icons.py` writes it too.
