Split-per-ABI Guidance

Why split per ABI?
- Native libraries (libmpv, ffmpeg, native extensions) significantly increase APK size.
- Generating per-ABI APKs reduces download size for end users by only shipping the native libs for their CPU architecture.
- Google Play App Bundles (.aab) are preferred for Play distribution since Play generates optimized APKs per device. Use split-per-ABI when distributing APKs directly or for CI testing.

Quick commands
- Flutter (recommended for local builds / CI):

```bash
# Build per-ABI APKs (outputs in build/app/outputs/flutter-apk/)
flutter build apk --split-per-abi --release

# Build an App Bundle (recommended for Play Store)
flutter build appbundle --release
```

- Gradle (native):
```bash
# From android/ folder
./gradlew assembleRelease
# With ABI splits enabled this creates per-ABI APK variants like:
# app-release-armeabi-v7a.apk, app-release-arm64-v8a.apk, app-release-x86_64.apk
```

Notes for Play Store
- Preferred: upload an `.aab` (App Bundle) to Play — Play signs and serves device-optimized APKs.
- If you must upload APKs directly, upload one APK per ABI or use "Multiple APKs" support with device targeting.

CI recommendations
- Use `flutter build apk --split-per-abi` in CI to create artifacts per ABI and upload them as separate artifacts.
- Alternatively, produce an `.aab` and let Play handle splitting.

Packaging caveats
- We already add a `pickFirsts` packaging rule for `libc++_shared.so`. If you add other native libraries, verify packaging rules so Gradle doesn't fail on duplicate symbols.
- Ensure `ndkVersion` and `compileSdk` are consistent across CI runners to avoid ABI mismatches.

Testing
- Test each ABI on a matching emulator or device.
- Use `adb install -r path/to/app-release-arm64-v8a.apk` to install a specific ABI APK.

Troubleshooting
- If a required .so is missing for an ABI, Gradle will produce an APK without that ABI's native libs — check `build/app/intermediates/runtime_library_classes` and `build/app/outputs/apk/` for expected files.
- For Flutter modules using dynamic libraries (e.g., media_kit native libs), prefer App Bundles to avoid manually managing ABI coverage.

If you want, I can also:
- Add a CI job example (GitHub Actions) that builds and uploads per-ABI artifacts.
- Add a small shell script to collect and rename ABI APKs for release.
