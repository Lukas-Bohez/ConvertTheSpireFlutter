# Play Console — Data Safety declaration (authoritative)

**This file is the source of truth for what the app collects.** If you add,
remove or upgrade an SDK that touches user data, update this file *and* the
Play Console form in the same change. A mismatch between the two is what got
version code 1286 rejected ("Apparaat- of andere ID's niet aangegeven" /
"Device or other IDs not declared").

Guarded by `test/play_data_safety_test.dart`, which fails the build if the
`AD_ID` permission moves out of the Play flavor.

---

## What actually collects data

| SDK / feature | Flavor | Leaves the device? | Data type |
|---|---|---|---|
| **google_mobile_ads** (AdMob) | **play only** | **Yes** | **Advertising ID**, ad interactions, coarse device info |
| in_app_purchase | play only | Handled by Play Billing | Purchase state (not collected by us) |
| in_app_review / in_app_update | both | No user data | — |
| Downloads, browser history, playlists, player stats | both | **No** — local SQLite / SharedPreferences only | — |
| Torrent engine | both | Peer IPs are exchanged P2P, not collected by the developer | — |

Everything except AdMob stays on the device. There is no analytics SDK, no
crash-reporting SDK, and no first-party telemetry endpoint — verified by
sweeping the codebase for outbound POSTs (none to developer-controlled hosts).

**The GitHub / `full` flavor is ad-free** and collects nothing.

> **Gotcha worth knowing:** deleting `AD_ID` from `src/main/AndroidManifest.xml`
> is *not* enough to keep it out of the ad-free build. The `google_mobile_ads`
> AAR merges `com.google.android.gms.permission.AD_ID` and
> `android.permission.ACCESS_ADSERVICES_AD_ID` in from its own manifest, into
> every flavor, because the dependency is not flavor-scoped. The `full` flavor
> strips them with `tools:node="remove"` in `src/full/AndroidManifest.xml`.
> Confirm what actually ships by inspecting the *merged* manifest, never the
> source:
>
> ```
> cd android && ./gradlew processPlayReleaseManifest processFullReleaseManifest
> M=../build/app/intermediates/merged_manifests
> grep -c "permission.AD_ID" $M/playRelease/processPlayReleaseManifest/AndroidManifest.xml   # expect 1
> grep -c "permission.AD_ID" $M/fullRelease/processFullReleaseManifest/AndroidManifest.xml   # expect 0
> ```

Only the `play` flavor needs a Data Safety declaration with collected data.

---

## Exact answers for the Play Console form

Play Console → **App content** → **Data safety**.

### Step 1 — Data collection and security
- *Does your app collect or share any of the required user data types?* → **Yes**
- *Is all of the user data collected by your app encrypted in transit?* → **Yes**
  (AdMob uses HTTPS.)
- *Do you provide a way for users to request that their data be deleted?* → **Yes**,
  and link the privacy policy. Users can also reset or delete the advertising ID
  in Android Settings → Google → Ads.

### Step 2 — Data types
Tick **only** this, under **Device or other IDs**:

- [x] **Device or other IDs**

Leave Location, Personal info, Financial info, Messages, Photos and videos,
Audio files, Files and docs, Calendar, Contacts, and Health unticked — none of
those leave the device.

> AdMob may also report **App activity → App interactions** and
> **App info and performance → Diagnostics** depending on your ad configuration.
> Check the current AdMob entry in the
> [Google Play SDK Index](https://play.google.com/sdks) before submitting and
> tick those too if listed. Over-declaring is safe; under-declaring is what
> causes a rejection.

### Step 3 — For "Device or other IDs"
- *Collected* → **Yes**
- *Shared* → **Yes** (sent to Google AdMob and its advertising partners)
- *Processed ephemerally* → **No**
- *Required or optional?* → **Users can choose** — EEA/UK users can decline via
  the UMP consent form, and the in-app "Remove Ads" purchase stops ad requests.
- *Purposes* → **Advertising or marketing**. (Also tick *Analytics* only if you
  enable AdMob reporting features that require it.)

### Step 4 — Submit
Send for review from the **Publishing overview**. Review takes up to 7 days.

---

## If you ever want to answer "No data collected"

That requires removing ads entirely from the Play build:

1. Drop `google_mobile_ads` from `pubspec.yaml`.
2. Delete `<uses-permission android:name="com.google.android.gms.permission.AD_ID" />`
   from `android/app/src/play/AndroidManifest.xml`.
3. Remove `lib/src/services/ad_service.dart` and its call sites.
4. Delete the AdMob `APPLICATION_ID` meta-data from `android/app/src/main/AndroidManifest.xml`.
5. Update `test/play_data_safety_test.dart`, which asserts the current layout.

This removes the ad revenue from the Play build, so it is a product decision,
not just a compliance one.

---

## In-app claims must match this file

The app shows privacy copy in three places. In the Play (ad-serving) build these
must **not** claim there is no advertising — a reviewer seeing "No advertising or
analytics" in a build that serves AdMob is a second rejection waiting to happen.
All three are branched on `kPlayStoreBuild`:

- `lib/src/vault/screens/about_screen.dart` — the "Data Safety:" block
- `lib/src/screens/support_screen.dart` — the "Privacy First" card
- `lib/src/screens/onboarding_screen.dart` — the privacy line during onboarding
