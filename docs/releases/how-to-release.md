# How a release goes out

One release ships in two places: the GitHub release (Windows zip, macOS zip, Android APK) and the Play Store (the BitPlayer AAB). Both come from the same commit on `main`.

## 1. Version and notes

On a branch, update together:

| File | What goes in |
|---|---|
| `pubspec.yaml` | `version: X.Y.Z+N`. `N` is one higher than the last build uploaded to Play. |
| `CHANGELOG.md` | A new top section, `## X.Y.Z+N — Title`, with `### Fixed`, `### New` and `### Improved`. The app's **What's new** screen reads this file, so the heading must match the version exactly. |
| `docs/release-notes/release_notes_vX.Y.Z.md` | `# Convert the Spire Reborn vX.Y.Z`, then `## Title`, the same sections, and a last `### Build Notes` section for developers. |
| `docs/releases/latest.md` | The same notes, headed `# Release Notes - vX.Y.Z`. |

Write the notes for the people using the app: what changed for them, in plain words, the most noticeable first.

## 2. Check and merge

* `flutter analyze` must report no issues: the release workflow stops on a single warning.
* `flutter test` must pass.
* Open a PR. CI builds Android and Windows and runs both checks; merge once it is green.

## Where the files to upload are

Everything to upload for the store versions is collected in `upload/` (not in git):

| Folder | What is in it |
|---|---|
| `upload/newest/androidPlayStore/` | The newest `.aab` for the Play Console. |
| `upload/newest/windowsMicrosoftStore/` | The newest `.msix` for Partner Center, and the "what's new" `.csv` for its listings. |
| `upload/older/...` | Earlier builds, kept in case one has to be uploaded again. |

When a new build is put in `newest`, the one that was there moves to `older`: `scripts/publish_local.ps1` does both.

## 3. Google Play

Build, check and upload the AAB as in the [Play AAB build guide](../build/play-store-aab.md). Run `scripts/verify_play_aab.py` before every upload; it catches what Play has turned bundles down for before (TV banner and icon, signing key, version).

## 4. GitHub release

From the repo root, in Git Bash:

```bash
gh workflow run release.yml --ref main \
  -f release_tag=vX.Y.Z \
  -f "release_name=Version X.Y.Z - Title" \
  -f "release_notes=$(sed '1d; /^### Build Notes/,$d' docs/release-notes/release_notes_vX.Y.Z.md)" \
  -f is_prerelease=false
```

The `sed` drops the `#` title line and the Build Notes. The workflow takes about 25 minutes. It runs analyze and the tests, builds the Windows zip, the macOS zip and the APK, checks that the tag matches `pubspec.yaml`, tags the commit and publishes the release with `SHA256SUMS.txt`.

The page is [release_body_template.md](release_body_template.md) with the notes dropped in. The template already has the demo video, the screenshots, the one-line "Nothing to set up" pitch, the **Get it from Microsoft** and **Get it on Google Play** buttons (with the note that the Play version is limited), the **Install in a minute** table right above the downloads, and the footer links, so the notes should not repeat any of them. The buttons link to the official store pages, which `release.yml` takes from this template for every release: if a store link or the list of what the Play version leaves out changes, change it here and in the README's install table. Easy installation is the app's biggest selling point: keep that section accurate when anything about installing changes.

## 5. Afterwards

* Open the release page: four files under Assets (Windows zip, macOS zip, APK, `SHA256SUMS.txt`), screenshots showing, install table in place.
* The README links to "latest release", so it needs no version change.
