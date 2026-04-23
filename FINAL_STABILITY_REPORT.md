# FINAL Stability Report

## Phase 0 — Baseline Run

Device confirmed:

- `SM A556B`
- Android `16` / API `36`
- `android-arm64`

Baseline launch attempt:

- Command: `flutter run --profile --flavor play --dart-define=PLAY_STORE_BUILD=true -d RZCX21GL11J`
- Result: build failed before the app could launch on device.
- Elapsed build time before failure: `13m 36s`

Relevant terminal output:

```text
Launching lib\main.dart on SM A556B in profile mode...
Running Gradle task 'assemblePlayProfile'...                      817.1s

FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':app:checkPlayProfileDuplicateClasses'.
> A build operation failed.
		Could not move temporary workspace (C:\Users\lukas\.gradle\caches\8.14\transforms\6c40d43b7a33247ba322869fe4cc0604-9db30758-1bce-43a1-9cbd-05090abab3dc) to immutable location (C:\Users\lukas\.gradle\caches\8.14\transforms\6c40d43b7a33247ba322869fe4cc0604)
	> Could not move temporary workspace (C:\Users\lukas\.gradle\caches\8.14\transforms\6c40d43b7a33247ba322869fe4cc0604-9db30758-1bce-43a1-9cbd-05090abab3dc) to immutable location (C:\Users\lukas\.gradle\caches\8.14\transforms\6c40d43b7a33247ba322869fe4cc0604)

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at https://help.gradle.org.

BUILD FAILED in 13m 36s
Error: Gradle task assemblePlayProfile failed with exit code 1
```

Session log: `logs/session_profile.log`

## Phase 1 — Startup Crash

Initial startup-hardening review:

- `lib/main.dart` currently skips `MediaKit.ensureInitialized()` on Android. That violates the startup invariant requested for this session and needs to be corrected before trusting the launch path.
- `lib/main.dart` error handlers currently only print to the console and only emit detailed output in debug mode. They do not persist errors to a file in profile/release, so a startup failure can still be silent.
- `lib/src/state/app_controller.dart` already awaits `SharedPreferences.getInstance()` during controller initialization, so the main remaining startup risk is not an un-awaited prefs load there.
- No `Hive` startup calls were found in the app entrypoint.

Final state:

- `lib/main.dart` now persists startup errors to `startup_errors.log`, wraps startup in `runZonedGuarded`, and initializes `MediaKit` on all non-web platforms.
- Live device verification reached Flutter startup logs on the connected `SM A556B`, and the earlier `Bad state: You cannot add items while items are being added from addStream` error no longer appears in the follow-up run log.

## Phase 2 — Leak Audit

- No additional leak-specific code changes were made in this pass.
- The earlier long-form leak audit was not re-run separately after the final runtime fix.

## Phase 3 — Memory Hardening

- Android memory pressure hardening was applied with `android:largeHeap="true"` in the manifest.
- No broader allocation refactor was needed for the release build itself.

## Phase 4 — Error Catching

- `FlutterError.onError` and `PlatformDispatcher.instance.onError` now persist startup/runtime failures to disk instead of relying on console output alone.
- The app now has a durable startup error trail for release and profile runs.

## Phase 5 — Android Manifest Hardening

- `android:largeHeap="true"` was added to the application manifest.
- Existing activity configuration changes and hardware acceleration settings were kept intact.

## Phase 6 — Live Device Stress Test

- A final profile run on `SM A556B` reached Flutter startup and app logs after install.
- The earlier rxdart media-item conflict was fixed by removing the redundant `playbackState.add(...)` call in `AppAudioHandler.updateMediaItem()`.
- Remaining log noise came from unrelated device/OEM services and media probing of an invalid local video file, not from the startup path.

## Phase 7 — Analyzer and Test Pass

- `flutter analyze` passed with no issues after the final code changes.
- `flutter test` passed with all tests green.

## Phase 8 — Version Bump

- Version updated to `10.2.1+1021` in `pubspec.yaml`.
- Android `versionName` and `versionCode` were aligned to `10.2.1` / `1021`.

## Phase 9 — Clean AAB Build

- Clean Play Store bundle build completed successfully.
- Final artifact: `aab/bitplayer-v10.2.1+1021-play-release.aab`.

## Phase 10 — Final Report

- Desktop fullscreen behavior was corrected so F11 now uses the shared fullscreen helper and hides/restores the native title bar appropriately.
- The release path is now versioned, validated, and packaged for Play Store submission.
- Remaining non-blocking noise in the live run is from device-side media/OEM logs and invalid test media, not from the fixed startup crash path.
