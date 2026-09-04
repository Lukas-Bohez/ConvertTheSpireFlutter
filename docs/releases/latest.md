# Release Notes - v13.0.7

## Hotfix: Updates + Torrent Loading

## Highlights

* **GitHub-build updates install again.** The v13.0.6 release APK was signed with the debug certificate (missing CI signing secrets), so it could not install over a release-signed build. Signing is now configured in CI, guarded, and verified before publishing. Installing v13.0.7 over any previous release works normally — no uninstall needed.
* **Torrents list loads again.** 13.0.6 keyed the vault database while SQLCipher was not loaded, so the database open failed and the torrents screen spun forever. The database opens unencrypted again; DB encryption returns later together with a real SQLCipher dependency and migration.

## Build Notes

* GitHub release tag: `v13.0.7`
* Release page: [v13.0.7](https://github.com/Lukas-Bohez/ConvertTheSpireFlutter/releases/tag/v13.0.7)
* `flutter analyze` passes cleanly.
* Play AAB not required for this hotfix (Play builds were unaffected).
