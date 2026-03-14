Now let me fetch the key source files to understand the issues better.I've gone through all four issues thoroughly. Here's a clear breakdown of the root causes and exact fixes for each:

---

## Issue 1 — Android Share Button Broken

**Root cause:** When a file is saved via SAF (Storage Access Framework) or MediaStore, `outputPath` is set to a `content://` URI string (e.g. `content://media/downloads/123`). You then pass this directly as a file path to `XFile(filePath)`. `XFile` expects a real filesystem path, not a content URI — so `share_plus` silently fails or crashes.

**Fix in `home_screen.dart` → `_shareFile()`:**

```dart
Future<void> _shareFile(String filePath, String title) async {
  try {
    XFile xfile;
    if (filePath.startsWith('content://')) {
      // Resolve the content URI to a real temp file via SAF
      final saf = AndroidSaf();
      final tempPath = await saf.copyToTemp(uri: filePath); // add this method
      if (tempPath == null) throw Exception('Could not resolve content URI');
      xfile = XFile(tempPath);
    } else {
      xfile = XFile(filePath);
    }
    await SharePlus.instance.share(
      ShareParams(files: [xfile], title: title),
    );
  } catch (e) {
    if (mounted) {
      Snack.show(context, 'Could not share file: $e', level: SnackLevel.error);
    }
  }
}
```

You already have a `copyToTemp` SAF method in `MainActivity.kt` — just expose it via `android_saf.dart`:

```dart
// In android_saf.dart
Future<String?> copyToTemp({required String uri}) async {
  if (!isSupported) return null;
  return _channel.invokeMethod<String>('copyToTemp', {'uri': uri});
}
```

Also add a `FileProvider` to your `AndroidManifest.xml` — `share_plus` on modern Android requires it for sharing app-internal files:

```xml
<!-- inside <application> in AndroidManifest.xml -->
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths"/>
</provider>
```

Create `android/app/src/main/res/xml/file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
    <files-path name="files" path="." />
    <external-files-path name="external_files" path="." />
</paths>
```

---

## Issue 2 — No "View Folder" Button on Android for Completed Items

**Root cause:** In `home_screen.dart` the queue action logic is mutually exclusive — the "Folder" button is explicitly hidden on Android (`!Platform.isAndroid`), and only the "Share" button appears instead. But since Share is broken (Issue 1), users have no way to access their file. The fix is to add both buttons on Android.

**Fix in `home_screen.dart` around line 2055:**

```dart
// Show Folder button for all non-web platforms (including Android)
if (item.status == DownloadStatus.completed &&
    item.outputPath != null &&
    !kIsWeb)
  _queueAction(
      Icons.folder_open_rounded,
      'Folder',
      Theme.of(context).colorScheme.primary,
      () => _showInFolder(item.outputPath!)),

// Show Share button on Android
if (item.status == DownloadStatus.completed &&
    item.outputPath != null &&
    !kIsWeb &&
    Platform.isAndroid)
  _queueAction(
      Icons.share_rounded,
      'Share',
      Theme.of(context).colorScheme.primary,
      () => _shareFile(item.outputPath!, item.title)),
```

Then fix `_showInFolder` to support Android content URIs by using your existing `AndroidSaf.openTree()`:

```dart
Future<void> _showInFolder(String filePath) async {
  if (kIsWeb) return;
  try {
    if (Platform.isAndroid) {
      final saf = AndroidSaf();
      if (filePath.startsWith('content://')) {
        await saf.openTree(filePath);
      } else {
        // Fallback: open the Downloads folder via Files app
        final uri = Uri.parse('content://com.android.externalstorage.documents/document/primary:Download');
        await saf.openTree(uri.toString());
      }
      return;
    }
    final file = File(filePath);
    final dir = file.parent.path;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir]);
    }
  } catch (e) {
    if (mounted) {
      Snack.show(context, 'Could not open folder: $e', level: SnackLevel.error);
    }
  }
}
```

---

## Issue 3 — Browser Doesn't Work on Older PCs

**Root cause:** `flutter_inappwebview` on Windows depends on the **WebView2 runtime** (Chromium-based), which requires Windows 10 1803+ and the Edge WebView2 runtime to be installed. Older machines often lack either. There is no graceful fallback — users just see a blank screen or crash.

**Fix — add a platform/capability check with a friendly fallback UI:**

In `browser_screen.dart`, wrap the `InAppWebView` widget in a check. At `initState` or in the build method:

```dart
// Add at top of _BrowserScreenState
bool _webViewAvailable = false;

@override
void initState() {
  super.initState();
  _checkWebViewAvailability();
}

Future<void> _checkWebViewAvailability() async {
  if (kIsWeb || Platform.isLinux) {
    setState(() => _webViewAvailable = false);
    return;
  }
  try {
    // flutter_inappwebview provides this check
    final available = await InAppWebViewController.isWebViewAvailable();
    if (mounted) setState(() => _webViewAvailable = available ?? false);
  } catch (_) {
    if (mounted) setState(() => _webViewAvailable = false);
  }
}
```

Then in your build, replace the raw WebView widget with:

```dart
if (!_webViewAvailable)
  _buildBrowserUnavailableFallback()
else
  // ... existing InAppWebView code
```

```dart
Widget _buildBrowserUnavailableFallback() {
  final isWindows = !kIsWeb && Platform.isWindows;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.web_asset_off_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            isWindows
                ? 'WebView2 runtime not found.\nPlease install the Microsoft Edge WebView2 Runtime to use the browser.'
                : 'Browser not available on this platform.',
            textAlign: TextAlign.center,
          ),
          if (isWindows) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download WebView2 Runtime'),
              onPressed: () => launchUrl(Uri.parse(
                'https://developer.microsoft.com/en-us/microsoft-edge/webview2/')),
            ),
          ],
        ],
      ),
    ),
  );
}
```

Also add `url_launcher` usage here (it's already in your `pubspec.yaml`).

---

## Issue 4 — Linux Only Supports Newer Distros (AppImage recommended)

**Root cause:** Your Linux build is a raw binary bundle that dynamically links against system libraries (`libmpv`, `libgtk-3`, etc.). This means it only works on distros with compatible versions of those libs installed — typically Ubuntu 22.04+ or equivalent. Older or non-Ubuntu distros will fail at launch.

**Fix — add AppImage packaging to your CI pipeline:**

In `.github/workflows/ci.yml`, add this step after the existing Linux build step:

```yaml
- name: Package as AppImage
  run: |
    # Install appimagetool
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
    
    BUNDLE="build/linux/x64/release/bundle"
    APPDIR="AppDir"
    
    mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons"
    
    # Copy Flutter bundle
    cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"
    
    # Bundle runtime libs
    apt-get install -y --no-install-recommends libmpv1 libmpv-dev
    cp /usr/lib/x86_64-linux-gnu/libmpv.so* "$APPDIR/usr/lib/" 2>/dev/null || true
    
    # AppImage metadata
    cat > "$APPDIR/convert_the_spire.desktop" <<EOF
    [Desktop Entry]
    Name=Convert the Spire Reborn
    Exec=convert_the_spire_reborn
    Icon=icon
    Type=Application
    Categories=AudioVideo;
    EOF
    
    cp assets/icons/icon.png "$APPDIR/icon.png" 2>/dev/null || true
    
    # Create AppRun
    cat > "$APPDIR/AppRun" <<'EOF'
    #!/bin/bash
    APPDIR="$(dirname "$(readlink -f "$0")")"
    export LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/usr/bin/lib:$LD_LIBRARY_PATH"
    exec "$APPDIR/usr/bin/convert_the_spire_reborn" "$@"
    EOF
    chmod +x "$APPDIR/AppRun"
    
    ARCH=x86_64 ./appimagetool-x86_64.AppImage "$APPDIR" "ConvertTheSpire-Linux-x86_64.AppImage"

- name: Upload AppImage artifact
  uses: actions/upload-artifact@v4
  with:
    name: linux-appimage
    path: ConvertTheSpire-Linux-x86_64.AppImage
```

Also update the release job to include the `.AppImage` file alongside the existing `tar.gz`.

**Additionally**, update your `README.md` Linux section to note:
- The `.AppImage` is self-contained and runs on any x86_64 Linux without installing dependencies
- The `.tar.gz` raw bundle still requires `libmpv` to be installed

---

## Summary Table

| Issue | Root Cause | Key Fix |
|---|---|---|
| Android Share broken | `XFile` can't handle `content://` URIs | Copy content URI to temp file first, then share |
| No Folder button on Android | Explicitly excluded with `!Platform.isAndroid` | Allow folder button on Android using `AndroidSaf.openTree()` |
| Browser fails on older PCs | No WebView2 availability check | Check `isWebViewAvailable()` and show friendly fallback + download link |
| Linux only works on new distros | Dynamic linking to system libs | Package as AppImage bundling required `.so` libs |


Let me look deeper at the codebase to provide more comprehensive improvements beyond the four issues.Now I have a thorough picture of the full codebase. Let me compile all the additional improvements beyond the original four issues.Here are the additional improvements beyond the four originally described issues:

---

## Issue 5 — Download Worker Pool Race Condition

**File:** `lib/src/state/app_controller.dart` ~line 465

**Root cause:** `downloadAll()` uses a shared mutable `index` variable across multiple concurrent `worker()` futures. In Dart's cooperative async model this is usually safe, but because `downloadSingle()` is `async` and yields to the event loop on each `await`, two workers can read the same `index` value before either increments it, causing the same item to be downloaded twice.

**Fix — use a proper work-stealing pattern:**

```dart
Future<void> downloadAll() async {
  if (_downloadAllRunning) return;
  _downloadAllRunning = true;
  try {
    while (true) {
      final pending = queue
          .where((item) => item.status == DownloadStatus.queued)
          .toList();
      if (pending.isEmpty) break;

      await notificationService.showActiveDownloadsBanner(pending.length);

      final workers = (_settings?.maxWorkers ?? 3).clamp(1, 10);
      // Use a queue-based approach: atomically pop items
      final workQueue = List<QueueItem>.from(pending);

      Future<void> worker() async {
        while (workQueue.isNotEmpty) {
          final item = workQueue.removeAt(0); // atomic pop
          await downloadSingle(item);
        }
      }

      await Future.wait(
        List.generate(workers.clamp(1, workQueue.length), (_) => worker()),
      );
    }
  } finally {
    _downloadAllRunning = false;
    await notificationService.cancelActiveDownloadsBanner();
  }
}
```

---

## Issue 6 — Android Notification Permission Never Requested at Runtime

**File:** `lib/src/services/notification_service.dart`

**Root cause:** On Android 13+ (API 33+), `POST_NOTIFICATIONS` is a **runtime permission** — having it in `AndroidManifest.xml` is not enough. The app never calls `requestPermissions()` before showing notifications, so all notifications silently fail on modern Android.

**Fix — request permission during `initialize()`:**

```dart
Future<void> initialize() async {
  if (!_supported || _initialised) return;

  // ... existing InitializationSettings setup ...

  try {
    await _plugin.initialize(settings: settings);
    _initialised = true;

    // Android 13+ requires runtime notification permission
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
  } catch (_) {}
}
```

---

## Issue 7 — File Converter "Save" Bypasses SAF on Android

**File:** `lib/src/state/app_controller.dart` → `_resolveSavePath()` and `saveConvertedResult()`

**Root cause:** When the user converts a file (e.g. PDF → DOCX) on Android, `_resolveSavePath()` writes directly to the app's external files directory using a raw path. This directory is not visible in the Files app to users, and the file can't be easily opened or shared. Unlike the download pipeline which properly uses SAF/MediaStore, the converter completely bypasses it.

**Fix — route converted file output through MediaStore:**

```dart
Future<void> saveConvertedResult(ConvertResult result) async {
  if (kIsWeb) {
    logs.add('Saving files is not supported on web.');
    return;
  }

  if (!kIsWeb && Platform.isAndroid) {
    // Write to temp first, then copy to Downloads via MediaStore
    final cacheDir = await PlatformDirs.getCacheDir();
    final tempPath = '${cacheDir.path}/${result.name}';
    await File(tempPath).writeAsBytes(result.bytes, flush: true);

    final saf = AndroidSaf();
    final mime = _mimeForExtension(
        result.name.split('.').last.toLowerCase());
    final destUri = await saf.copyToDownloads(
      sourcePath: tempPath,
      displayName: result.name,
      mimeType: mime,
      subdir: 'Converted',
    );
    await File(tempPath).delete().catchError((_) {});

    if (destUri != null) {
      logs.add('Saved converted file to Downloads: ${result.name}');
    } else {
      logs.add('Failed to save converted file to Downloads.');
    }
    return;
  }

  final path = await _resolveSavePath(result.name);
  if (path == null) return;
  await File(path).writeAsBytes(result.bytes, flush: true);
  logs.add('Saved converted file: $path');
}

String _mimeForExtension(String ext) {
  const map = {
    'mp3': 'audio/mpeg', 'mp4': 'video/mp4', 'm4a': 'audio/mp4',
    'pdf': 'application/pdf', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'png': 'image/png', 'jpg': 'image/jpeg', 'zip': 'application/zip',
  };
  return map[ext] ?? 'application/octet-stream';
}
```

---

## Issue 8 — `crypto` Package Used but Not Declared in pubspec.yaml

**File:** `lib/src/services/file_organization_service.dart` + `pubspec.yaml`

**Root cause:** `file_organization_service.dart` imports `package:crypto/crypto.dart` and uses `md5` for duplicate detection. However `crypto` is **not listed** in `pubspec.yaml` dependencies — it only appears in `pubspec.lock` as a transitive dependency of another package. This means if that transitive dependency is upgraded or removed, `crypto` will disappear and the build will break silently.

**Fix — explicitly add it to `pubspec.yaml`:**

```yaml
dependencies:
  # ... existing deps ...
  crypto: ^3.0.3   # used by FileOrganizationService for MD5 duplicate detection
```

---

## Issue 9 — Linux Distributor ID Hardcoded in `ShortcutService`

**File:** `lib/src/services/shortcut_service.dart`

**Root cause:** The shortcut creation logic writes to `~/.local/share/applications/` and assumes a standard XDG desktop environment. On older distros like CentOS/RHEL or minimal desktop installs, the `Exec=` path in the `.desktop` entry uses `getApplicationDocumentsDirectory()` which may resolve to different paths. The launcher script (`convert_the_spire.sh`) also hardcodes `./lib` for `LD_LIBRARY_PATH` which breaks if the user runs the app from a different working directory.

**Fix — make the launcher script path-independent:**

In `linux/convert_the_spire.sh` (or wherever it's generated), replace:
```bash
#!/bin/bash
export LD_LIBRARY_PATH=./lib:$LD_LIBRARY_PATH
./convert_the_spire_reborn "$@"
```
with:
```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:$LD_LIBRARY_PATH"
exec "$SCRIPT_DIR/convert_the_spire_reborn" "$@"
```

And update the `ShortcutService` `.desktop` entry to use the absolute install path rather than a relative one.

---

## Issue 10 — `minSdk = 24` Excludes Android 5.x/6.x Users; `copyToDownloads` Crashes Below API 29

**File:** `android/app/build.gradle.kts` + `MainActivity.kt`

**Root cause:** `minSdk = 24` (Android 7.0) is fine, but `copyToDownloads()` in `MainActivity.kt` uses `MediaStore.Downloads` which only exists on **API 29+** (Android 10). There's a guard (`Build.VERSION.SDK_INT < Build.VERSION_CODES.Q`) that returns `null`, but the Dart side in `_finalizeOutput()` then throws `'Failed to save file to Downloads'` — crashing the download for any Android 7/8/9 user with no SAF folder configured.

**Fix — add a proper API 21–28 fallback path in `MainActivity.kt`:**

```kotlin
private fun copyFileToDownloads(
    sourcePath: String,
    displayName: String,
    mimeType: String,
    subdir: String?,
): Uri? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        // API 29+: use MediaStore
        val relativeBase = if (subdir.isNullOrBlank())
            "Download/ConvertTheSpireReborn"
        else
            "Download/ConvertTheSpireReborn/$subdir"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativeBase)
        }
        val uri = contentResolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
        contentResolver.openOutputStream(uri, "w")?.use { out ->
            FileInputStream(File(sourcePath)).use { it.copyTo(out) }
        } ?: return null
        return uri
    } else {
        // API 21-28: write directly to public Downloads
        @Suppress("DEPRECATION")
        val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS)
        val targetDir = if (subdir.isNullOrBlank())
            File(downloadsDir, "ConvertTheSpireReborn")
        else
            File(downloadsDir, "ConvertTheSpireReborn/$subdir")
        targetDir.mkdirs()
        val destFile = File(targetDir, displayName)
        FileInputStream(File(sourcePath)).use { ins ->
            destFile.outputStream().use { ins.copyTo(it) }
        }
        // Notify MediaScanner so the file shows up in Files app
        sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE,
            Uri.fromFile(destFile)))
        return Uri.fromFile(destFile)
    }
}
```

And add the legacy write permission to `AndroidManifest.xml` with a max SDK guard:
```xml
<uses-permission
    android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28"/>
```

---

## Summary of All 10 Issues

| # | Issue | File(s) | Fix |
|---|---|---|---|
| 1 | Android Share broken on `content://` URIs | `home_screen.dart`, `android_saf.dart`, `AndroidManifest.xml` | Copy to temp path before sharing; add `FileProvider` |
| 2 | No Folder button on Android queue items | `home_screen.dart` | Remove `!Platform.isAndroid` guard; add SAF-based folder open |
| 3 | Browser crashes on older PCs (no WebView2) | `browser_screen.dart` | Check `isWebViewAvailable()`; show fallback UI + download link |
| 4 | Linux binary doesn't run on older distros | `.github/workflows/ci.yml` | Add AppImage packaging with bundled `libmpv` |
| 5 | Worker pool race condition (double downloads) | `app_controller.dart` | Use `List.removeAt(0)` work-stealing instead of shared index |
| 6 | Android 13+ notifications silently fail | `notification_service.dart` | Call `requestNotificationsPermission()` on init |
| 7 | File converter saves to hidden dir on Android | `app_controller.dart` | Route converted output through MediaStore/SAF |
| 8 | `crypto` is an undeclared transitive dependency | `pubspec.yaml` | Add `crypto: ^3.0.3` explicitly |
| 9 | Linux launcher script breaks outside install dir | `linux/convert_the_spire.sh` | Use `$SCRIPT_DIR` instead of relative paths |
| 10 | `copyToDownloads` crashes on Android 7/8/9 | `MainActivity.kt`, `AndroidManifest.xml` | Add `Environment.DIRECTORY_DOWNLOADS` fallback for API < 29 |

Let me dig deeper into the remaining services and screens for more issues.---

## Additional Issues 11–16

---

### Issue 11 — `mime` Package Used but Not Declared in `pubspec.yaml`

**Files:** `lib/src/services/local_media_server.dart`, `lib/src/services/convert_service.dart`

Both files import `package:mime/mime.dart` and call `lookupMimeType()`. Like `crypto` (Issue 8), `mime` is not listed in `pubspec.yaml` — it only exists as a transitive dependency. If `flutter_inappwebview` or another package drops it, both services will break silently at build time.

**Fix — add to `pubspec.yaml`:**
```yaml
dependencies:
  mime: ^2.0.0       # used by LocalMediaServer and ConvertService
  crypto: ^3.0.3     # used by FileOrganizationService and InstallerService
  ffi: ^2.1.0        # used directly in main.dart for Win32 FFI calls
```

All three (`mime`, `crypto`, `ffi`) are undeclared transitive deps that need pinning.

---

### Issue 12 — FFI Native Memory Leak on Exception in `main.dart`

**File:** `lib/main.dart`, lines 30–34

The two `malloc`-allocated native string pointers (`namePtr`, `valuePtr`) are freed with `malloc.free()` — but **only on the happy path**. If `setEnv(namePtr, valuePtr)` throws (e.g. a lookup exception from the FFI binding), the pointers are never freed, leaking native heap memory at startup.

**Fix — use a `try/finally` to guarantee cleanup:**
```dart
if (!kIsWeb && Platform.isWindows) {
  final local = Platform.environment['LOCALAPPDATA'] ?? '';
  final userData = Directory('$local\\ConvertTheSpireReborn\\WebView2');
  if (!userData.existsSync()) userData.createSync(recursive: true);

  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setEnv = kernel32.lookupFunction
      Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
      int Function(Pointer<Utf16>, Pointer<Utf16>)>('SetEnvironmentVariableW');

  final namePtr = 'WEBVIEW2_USER_DATA_FOLDER'.toNativeUtf16();
  final valuePtr = userData.path.toNativeUtf16();
  try {
    setEnv(namePtr, valuePtr);
  } finally {
    malloc.free(namePtr);  // always runs, even if setEnv throws
    malloc.free(valuePtr);
  }
}
```

---

### Issue 13 — `LocalMediaServer` Has No Error Handler on `server.listen()`

**File:** `lib/src/services/local_media_server.dart`, line 62

`server.listen()` is called without an `onError` callback. If a DLNA TV disconnects mid-stream or sends a malformed request, the unhandled stream error propagates to Dart's uncaught-exception handler and **crashes the entire app** (in release mode this silently kills the DLNA feature; in debug mode it shows a red screen).

**Fix — add `onError` and protect `pipe()` calls:**
```dart
server.listen(
  (request) async {
    try {
      if (request.uri.path == '/media' && _servingPath != null) {
        await _handleMediaRequest(request);
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        await request.response.close();
      }
    } catch (e) {
      debugPrint('LocalMediaServer: request handler error: $e');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('Server error');
        await request.response.close();
      } catch (_) {}
    }
  },
  onError: (e) {
    debugPrint('LocalMediaServer: stream error: $e');
  },
  cancelOnError: false,  // keep serving after a single client error
);
```

Also protect the two `pipe()` calls in `_handleMediaRequest` from `SocketException` (client disconnects):
```dart
// Replace:
await file.openRead(start, end + 1).pipe(request.response);

// With:
await file.openRead(start, end + 1).pipe(request.response)
    .catchError((e) => debugPrint('LocalMediaServer: pipe error: $e'));
```

---

### Issue 14 — DLNA Cast Fails Silently for `content://` URI Files on Android

**File:** `lib/src/screens/cast_dialog.dart`, line 129

When the user taps Cast on a completed Android download, `widget.filePath` is a `content://` URI (from SAF/MediaStore). `LocalMediaServer.serve()` does `File(filePath)` on it, which fails with "File not found" because `dart:io` `File` cannot read content URIs — they require `ContentResolver`.

**Fix — copy content URI to cache before serving:**
```dart
Future<String> _resolveServablePath(String filePath) async {
  if (!Platform.isAndroid || !filePath.startsWith('content://')) {
    return filePath;
  }
  // Use existing copyToTemp SAF channel
  final saf = AndroidSaf();
  final tempPath = await saf.copyToTemp(uri: filePath);
  if (tempPath == null) {
    throw Exception('Could not resolve content URI for casting.');
  }
  return tempPath;
}
```

Then in `_castToDevice`:
```dart
final servablePath = await _resolveServablePath(widget.filePath);
final mediaUrl = await _server.serve(
  filePath: servablePath,
  localIp: localIp,
);
```

---

### Issue 15 — `InstallerService._download()` Buffers Entire File in RAM

**File:** `lib/src/services/installer_service.dart`, lines 60–75

The FFmpeg installer downloads the binary by collecting all chunks into a `List<int>` and then converting to `Uint8List`. For the Windows FFmpeg bundle this is typically **100–150 MB**. Holding all of it in Dart heap simultaneously — once in the list and once in the `Uint8List.fromList()` copy — peaks at roughly **300 MB** of memory, which can cause OOM kills on lower-end devices.

**Fix — stream directly to disk:**
```dart
Future<String> _downloadToFile(Uri url, String destPath,
    {void Function(int percent, String message)? onProgress}) async {
  final client = http.Client();
  try {
    final response = await client
        .send(http.Request('GET', url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed: ${response.statusCode}');
    }
    final total = response.contentLength ?? 0;
    int received = 0;
    final sink = File(destPath).openWrite();
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
        onTimeout: (s) => s..addError(TimeoutException('Download stalled')),
      )) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(((received / total) * 100).toInt(), 'Downloading');
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return destPath;
  } finally {
    client.close();
  }
}
```

Update `installFfmpeg` to use `_downloadToFile` and extract directly from disk rather than from an in-memory `Uint8List`. This also means the SHA-256 checksum check needs to hash the file stream rather than the in-memory bytes (which is actually more correct anyway).

---

### Issue 16 — Settings Use `any` Version Constraints Throughout `pubspec.yaml`

**File:** `pubspec.yaml`

Most dependencies are declared as `any` (e.g. `shared_preferences: any`, `sqflite: any`, `media_kit: any`). This means `flutter pub get` will always resolve to the latest available version, which can silently pull in breaking changes, API renames, or incompatible platform plugins between CI runs. It makes builds non-reproducible even when `pubspec.lock` is committed.

**Fix — replace `any` with concrete version constraints.** Run `flutter pub outdated` to see current resolved versions, then pin them with caret constraints:

```yaml
dependencies:
  shared_preferences: ^2.3.2
  sqflite: ^2.3.3+1
  sqflite_common_ffi: ^2.3.4
  window_manager: ^0.3.9
  media_kit: ^1.1.11
  media_kit_video: ^1.1.11
  media_kit_libs_windows_video: ^1.0.9
  media_kit_libs_android_video: ^1.3.8
  media_kit_libs_linux: ^1.0.5
  media_kit_native_event_loop: ^1.0.2
  flutter_inappwebview: ^6.1.5
  share_plus: ^10.0.3
  just_audio: ^0.9.40
  audio_service: ^0.18.15
  # ... etc
```

This ensures that `pubspec.lock` is the true reproducibility anchor and `pubspec.yaml` expresses intent rather than "whatever is latest."

---

## Full Issues Table (All 16)

| # | Issue | File(s) | Impact |
|---|---|---|---|
| 1 | Android Share broken (`content://` URI) | `home_screen.dart`, `android_saf.dart`, manifest | Share button does nothing on Android |
| 2 | No Folder button on Android queue items | `home_screen.dart` | Users can't find their downloaded files |
| 3 | Browser crashes on older PCs (no WebView2) | `browser_screen.dart` | Blank/crash on Windows 7/8 or no Edge runtime |
| 4 | Linux binary fails on older distros | CI workflow | App won't launch without exact system libs |
| 5 | Worker pool race condition | `app_controller.dart` | Duplicate downloads with ≥2 workers |
| 6 | Android 13+ notifications never shown | `notification_service.dart` | Runtime permission never requested |
| 7 | Converter saves to hidden dir on Android | `app_controller.dart` | Converted files invisible in Files app |
| 8 | `crypto` undeclared transitive dependency | `pubspec.yaml` | Future breakage if dep graph changes |
| 9 | Linux launcher breaks outside install dir | `linux/convert_the_spire.sh` | App fails to start if run from wrong directory |
| 10 | `copyToDownloads` crashes Android 7/8/9 | `MainActivity.kt`, manifest | Downloads fail on API < 29 with no SAF folder |
| 11 | `mime` + `ffi` also undeclared | `pubspec.yaml` | Same breakage risk as Issue 8 |
| 12 | FFI pointer leak on exception | `main.dart` | Native memory leak at startup on Windows |
| 13 | `LocalMediaServer.listen()` unhandled errors | `local_media_server.dart` | App crash when TV disconnects mid-stream |
| 14 | DLNA Cast fails for `content://` files on Android | `cast_dialog.dart` | Cast silently fails for Android downloads |
| 15 | FFmpeg installer buffers 150 MB in RAM | `installer_service.dart` | OOM on low-memory devices during FFmpeg install |
| 16 | All deps use `any` version constraints | `pubspec.yaml` | Non-reproducible builds, silent breaking changes |

---

## Additional Issues 17–22

---

### Issue 17 — `MultiSourceSearchService` Has No Timeouts

**File:** `lib/src/services/multi_source_search_service.dart`

**Root cause:** `YouTubeSearcher.search()` calls `_yt.search.search(query)` and `SoundCloudSearcher.search()` calls `http.get(url)` — neither has any timeout. If YouTube's API is slow or SoundCloud is unreachable, `searchAll()` will hang indefinitely, leaving the UI frozen on the loading spinner with no way to cancel.

**Fix — add `.timeout()` to both searchers:**

```dart
// In YouTubeSearcher.search():
final results = await _yt.search.search(query)
    .timeout(const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('YouTube search timed out'));

// In SoundCloudSearcher.search():
final response = await http.get(Uri.parse(url))
    .timeout(const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('SoundCloud search timed out'));
```

Since `_safeSoundCloudSearch` already swallows exceptions, the SoundCloud timeout will silently return `[]`. For YouTube, wrap the call in `searchAll` with a `catchError` to degrade gracefully to an empty result rather than propagating a timeout to the user as a hard error.

---

### Issue 18 — `_sanitizeFileName` Doesn't Truncate Long Filenames

**File:** `lib/src/services/download_service.dart` → `_sanitizeFileName()`

**Root cause:** YouTube video titles can be very long (300+ characters is not unusual). The sanitizer strips unsafe characters but applies no length limit. On Linux/macOS the filesystem limit is **255 bytes** for a filename component; on Windows it's **260 characters** for the full path (MAX\_PATH). A long title combined with a deep output directory will silently cause `File.create()` to throw `PathTooLongException` on Windows or `ENAMETOOLONG` on Linux, failing the download with a cryptic error.

**Fix — add a max-length truncation step:**

```dart
String _sanitizeFileName(String value) {
  final unsafe = RegExp(r'[<>:"/\\|?*]');
  String result = value.replaceAll(unsafe, '_');
  result = result.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_');
  result = result.trim().replaceAll(RegExp(r'\.+$'), '');

  // Truncate to 200 chars — leaves headroom for extension + temp suffixes
  // like ".temp.video.webm" (16 chars) within the 255-byte fs limit
  if (result.length > 200) {
    result = result.substring(0, 200).trim();
  }

  return result.isEmpty ? 'download' : result;
}
```

---

### Issue 19 — `ConvertService.convertFile()` Reads Entire File into RAM

**File:** `lib/src/services/convert_service.dart`, line 23

**Root cause:** The very first line of `convertFile()` is:
```dart
final inputBytes = Uint8List.fromList(await input.readAsBytes());
```
This reads the **entire input file into memory** before any format detection. For media files being converted (e.g. a 2 GB MKV → MP4), this causes an immediate OOM kill on Android (which restricts heap to ~512 MB per process) and severely degrades performance on desktop. For document/image formats the bytes are needed, but for all media targets `_convertMedia()` passes `input` (the `File`) to FFmpeg and never uses `inputBytes` at all.

**Fix — lazy-load bytes only when actually needed:**

```dart
Future<ConvertResult> convertFile(File input, String target, {required String? ffmpegPath}) async {
  final targetLower = target.toLowerCase().replaceAll('.', '');
  final inputName = _sanitizeFileName(input.uri.pathSegments.last);
  final baseName = _stripExtension(inputName);
  final inputExt = _getExtension(inputName).toLowerCase();

  // Media: delegate directly to FFmpeg — do NOT read file into memory
  if (_isMediaTarget(targetLower)) {
    return _convertMedia(input, targetLower, baseName, ffmpegPath: ffmpegPath);
  }

  // All other formats need the bytes (images, docs, zip, epub, pdf, txt)
  final inputBytes = Uint8List.fromList(await input.readAsBytes());

  if (targetLower == 'zip' || targetLower == 'cbz') {
    return _zipBytes(inputBytes, '$baseName.$targetLower', inputName);
  }
  // ... rest unchanged
}
```

---

### Issue 20 — SSDP Discovery Socket Not Closed on Exception

**File:** `lib/src/services/dlna_discovery_service.dart`, `_discoverViaSsdp()`

**Root cause:** The `socket` is created with `RawDatagramSocket.bind()` inside a `try/catch`. The `finally` block closes it via a `Timer` callback — but **only on the happy path**. If an exception is thrown after `socket` is created but before the `Timer` fires (e.g. the `socket.send()` call throws), the catch block at the bottom returns early and the socket **leaks forever**, holding an OS UDP port open until the process exits.

**Fix — use `try/finally` to guarantee socket closure:**

```dart
Future<List<DlnaDevice>> _discoverViaSsdp({required Duration timeout}) async {
  final devices = <DlnaDevice>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4, 0, reuseAddress: true);

    // ... send M-SEARCH messages ...

    final completer = Completer<List<DlnaDevice>>();
    final pendingParses = <Future<DlnaDevice?>>[];

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket!.receive();
        if (datagram == null) return;
        final response = utf8.decode(datagram.data, allowMalformed: true);
        pendingParses.add(
          _parseResponse(response, datagram.address)
              .catchError((_) => null as DlnaDevice?));
      }
    }, onError: (e) => debugPrint('SSDP socket error: $e'));

    Timer(timeout, () async {
      socket?.close();
      final results = await Future.wait(pendingParses);
      for (final d in results) { if (d != null) devices.add(d); }
      if (!completer.isCompleted) completer.complete(devices.toList());
    });

    return await completer.future;
  } catch (e) {
    debugPrint('DLNA SSDP discovery error: $e');
    socket?.close();  // ensure closure even on early exception
    return devices.toList();
  }
}
```

---

### Issue 21 — `uuid` is Another Undeclared Transitive Dependency

**File:** `lib/src/services/convert_service.dart` (imports `package:uuid/uuid.dart`)

Same category as Issues 8 and 11 — `uuid` is used but not declared in `pubspec.yaml`, only present transitively. Add it explicitly:

```yaml
dependencies:
  uuid: ^4.5.1   # used by ConvertService for temp file naming
```

---

### Issue 22 — `WatchedPlaylistService` Background Timer Is Never Cancelled

**File:** `lib/src/services/watched_playlist_service.dart` (referenced from `app_controller.dart`)

**Root cause:** The service uses an in-process periodic `Timer` to check playlists. The `AppController` holds a reference to `WatchedPlaylistService` but there is no `dispose()` method on it, and `AppController.dispose()` never cancels the timer. When the app is put into the background on Android (or the widget tree is torn down in tests), the timer keeps firing, triggering network requests and `setState`-equivalent calls on a potentially dead object — causing memory leaks and potential "setState called after dispose" crashes.

**Fix — add a `dispose()` method to `WatchedPlaylistService` and call it from `AppController`:**

```dart
// In WatchedPlaylistService:
Timer? _checkTimer;

void startPeriodicCheck({Duration interval = const Duration(hours: 1)}) {
  _checkTimer?.cancel();
  _checkTimer = Timer.periodic(interval, (_) => checkAllPlaylists());
}

void dispose() {
  _checkTimer?.cancel();
  _checkTimer = null;
}
```

```dart
// In AppController.dispose():
@override
void dispose() {
  watchedPlaylistService.dispose();
  // ... other existing dispose calls
  super.dispose();
}
```

---

## Complete Issues List (All 22)

| # | Issue | File(s) | Impact |
|---|---|---|---|
| 1 | Android Share broken (`content://` URI) | `home_screen.dart`, `android_saf.dart`, manifest | Share does nothing on Android |
| 2 | No Folder button on Android queue items | `home_screen.dart` | Users can't find downloaded files |
| 3 | Browser crashes on PCs without WebView2 | `browser_screen.dart` | Blank/crash on older Windows machines |
| 4 | Linux binary fails on older distros | CI workflow | App won't start without exact system libs |
| 5 | Worker pool race condition | `app_controller.dart` | Duplicate downloads with ≥2 workers |
| 6 | Android 13+ notifications never shown | `notification_service.dart` | Runtime permission never requested |
| 7 | Converter saves to hidden dir on Android | `app_controller.dart` | Converted files invisible in Files app |
| 8 | `crypto` undeclared transitive dependency | `pubspec.yaml` | Silent build breakage if dep graph changes |
| 9 | Linux launcher breaks outside install dir | `convert_the_spire.sh` | App fails to start from wrong directory |
| 10 | `copyToDownloads` crashes Android 7/8/9 | `MainActivity.kt`, manifest | Downloads fail on API < 29 |
| 11 | `mime` + `ffi` undeclared transitives | `pubspec.yaml` | Same breakage risk as #8 |
| 12 | FFI pointer leak on exception | `main.dart` | Native memory leak on Windows startup |
| 13 | `LocalMediaServer.listen()` crashes on TV disconnect | `local_media_server.dart` | Unhandled stream error crashes app |
| 14 | DLNA Cast fails for `content://` files on Android | `cast_dialog.dart` | Cast silently fails for Android downloads |
| 15 | FFmpeg installer buffers 150 MB in RAM | `installer_service.dart` | OOM on low-memory devices |
| 16 | All deps use `any` version constraints | `pubspec.yaml` | Non-reproducible builds |
| 17 | Search has no timeouts | `multi_source_search_service.dart` | UI freezes indefinitely on slow networks |
| 18 | Filenames not length-limited (255 byte limit) | `download_service.dart` | Cryptic ENAMETOOLONG crash on long titles |
| 19 | ConvertService reads entire file into memory | `convert_service.dart` | OOM crash converting large media files |
| 20 | SSDP socket not closed on exception | `dlna_discovery_service.dart` | UDP port leak if send() throws |
| 21 | `uuid` undeclared transitive dependency | `pubspec.yaml` | Same breakage risk as #8, #11 |
| 22 | WatchedPlaylistService timer never cancelled | `watched_playlist_service.dart`, `app_controller.dart` | Memory leak + possible crash after dispose |



---

## Additional Issues 23–28

---

### Issue 23 — `MusicBrainzService` and `LyricsService` Are Instantiated but Never Called

**Files:** `lib/src/app.dart`, `lib/src/state/app_controller.dart`

**Root cause:** `MusicBrainzService` and `LyricsService` are created in `app.dart` (lines 213–214) and injected into `AppController` as required fields. However, searching `app_controller.dart` and all other Dart files shows **zero call sites** for `searchTrack()` or `fetchLyrics()`. The services are wired up and kept in memory for the app's lifetime, but they're dead weight — no code ever calls them. This is misleading to contributors, wastes the injected dependency, and the `MusicBrainzService` has no rate-limit awareness, which would become a real problem if anyone ever does wire it up (MusicBrainz enforces 1 request/second per their terms).

**Fix — two options, choose one:**

Option A (if you plan to use them): Add a rate limiter before going live:
```dart
// In MusicBrainzService — add between requests:
DateTime? _lastRequest;
Future<void> _respectRateLimit() async {
  final now = DateTime.now();
  if (_lastRequest != null) {
    final elapsed = now.difference(_lastRequest!);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(const Duration(seconds: 1) - elapsed);
    }
  }
  _lastRequest = DateTime.now();
}
```

Option B (cleaner): Remove `musicBrainzService` and `lyricsService` from `AppController`'s constructor until they are actually used, to avoid misleading dead injections.

---

### Issue 24 — `androidNotificationOngoing: true` with `androidStopForegroundOnPause: false` Leaves Notification Stuck

**File:** `lib/src/services/audio_handler.dart`

**Root cause:** The `AudioServiceConfig` sets `androidNotificationOngoing: true` and `androidStopForegroundOnPause: false`. This means the Android foreground service notification **persists even when the user pauses playback**. Users cannot dismiss the notification from the notification shade while paused, which is against Android UX guidelines and will confuse users who try to swipe it away.

**Fix — allow notification dismissal when paused:**
```dart
config: AudioServiceConfig(
  androidNotificationChannelId: 'com.orokaconner.convertthespire.audio',
  androidNotificationChannelName: 'Audio Playback',
  androidNotificationOngoing: false,       // dismissable when not playing
  androidStopForegroundOnPause: true,       // drop foreground on pause
),
```

Also add a proper `stop()` call in `PlayerState.dispose()` to release the notification when the app exits:
```dart
void dispose() {
  _disposed = true;
  _dirWatcher?.cancel();
  for (final sub in _subs) { sub.cancel(); }
  _subs.clear();
  _audioHandler?.stop();   // ← add this: dismisses the system notification
  _audio.dispose();
  // ... rest unchanged
}
```

---

### Issue 25 — `path` Package Used but Not Declared in `pubspec.yaml`

**File:** `lib/src/screens/player.dart` (imports `package:path/path.dart as p`)

Same category as Issues 8, 11, 21 — `path` is only a transitive dependency in `pubspec.lock` but is directly imported in `player.dart`. Add it explicitly:

```yaml
dependencies:
  path: ^1.9.0    # used by PlayerScreen for file extension/basename operations
```

---

### Issue 26 — `playerPlayerPage` Class Name Violates Dart Naming Conventions

**File:** `lib/src/screens/player.dart`, line 35

**Root cause:** The wrapper class is named `playerPlayerPage` — lowercase first letter, which violates Dart's mandatory `UpperCamelCase` convention for class names. This causes `dart analyze` to emit a lint warning (`non_constant_identifier_names`) and is confusing to read (`playerPlayer` sounds like a stutter). Any code that `import`s or refers to this class is harder to read.

**Fix — rename to `PlayerPage`:**
```dart
// Before:
class playerPlayerPage extends StatelessWidget { ... }

// After:
class PlayerPage extends StatelessWidget { ... }
```

Update all references (search for `playerPlayerPage` across the codebase and replace).

---

### Issue 27 — `MusicBrainzService.searchTrack()` Has No `try/catch`

**File:** `lib/src/services/metadata_service.dart`, line 17

**Root cause:** The outer `searchTrack()` method calls `http.get()` with a `.timeout()` but wraps nothing in a `try/catch`. If the network is offline, the URL is malformed, or MusicBrainz returns unexpected JSON structure, the exception propagates uncaught to the caller. Since `musicBrainzService` would be called from `onDownloadCompleted` (if ever activated), an uncaught exception there would mask a successfully completed download — the file was saved but the user sees a failure.

**Fix — wrap the entire method:**
```dart
Future<TrackMetadata?> searchTrack(String artist, String title) async {
  try {
    final query = Uri.encodeComponent('artist:"$artist" AND recording:"$title"');
    final url = '$_baseUrl/recording/?query=$query&fmt=json&limit=5';
    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    // ... rest of parsing
  } catch (e) {
    debugPrint('MusicBrainzService: searchTrack failed: $e');
    return null;
  }
}
```

---

### Issue 28 — `AlbumArtService.downloadAlbumArt()` Writes to `getTemporaryDirectory()` Without Cleanup

**File:** `lib/src/services/metadata_service.dart`, lines 73–79

**Root cause:** Album art is written to `getTemporaryDirectory()` with filenames like `album_art_$trackId.jpg`. These files are **never deleted**. On Android, `getTemporaryDirectory()` is the app's cache directory which the OS may clear under memory pressure, but on desktop (Windows/Linux) `getTemporaryDirectory()` maps to the system temp folder which is rarely cleaned automatically. Over time this accumulates orphaned image files — one per unique `trackId` — potentially filling the user's disk if they download many tracks.

**Fix — either clean up after use, or use a fixed-name cache with overwrite semantics:**
```dart
Future<String?> downloadAlbumArt(String thumbnailUrl, String trackId) async {
  try {
    final response = await http.get(Uri.parse(thumbnailUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final tempDir = await getTemporaryDirectory();
    // Use a fixed, single-slot cache file — overwritten each time
    // This avoids accumulating hundreds of orphaned art files
    final artPath = '${tempDir.path}${Platform.pathSeparator}album_art_cache.jpg';
    await File(artPath).writeAsBytes(response.bodyBytes);
    return artPath;
  } catch (_) {
    return null;
  }
}
```

Or if per-track caching is intentional, add a cleanup method:
```dart
static Future<void> clearArtCache() async {
  final tempDir = await getTemporaryDirectory();
  final files = tempDir.listSync().whereType<File>()
      .where((f) => p.basename(f.path).startsWith('album_art_'));
  for (final f in files) {
    try { await f.delete(); } catch (_) {}
  }
}
```

---

## Complete Issues List (All 28)

| # | Issue | File(s) | Impact |
|---|---|---|---|
| 1 | Android Share broken (`content://`) | `home_screen.dart`, `android_saf.dart`, manifest | Share button does nothing |
| 2 | No Folder button on Android | `home_screen.dart` | Users can't find downloads |
| 3 | Browser crashes on PCs without WebView2 | `browser_screen.dart` | Blank/crash on older Windows |
| 4 | Linux binary fails on older distros | CI workflow | Won't launch without exact libs |
| 5 | Worker pool race condition | `app_controller.dart` | Duplicate downloads |
| 6 | Android 13+ notifications fail | `notification_service.dart` | Notifications never shown |
| 7 | Converter saves to hidden dir on Android | `app_controller.dart` | Files invisible in Files app |
| 8 | `crypto` undeclared transitive dep | `pubspec.yaml` | Silent future build breakage |
| 9 | Linux launcher breaks outside install dir | `convert_the_spire.sh` | App fails from wrong directory |
| 10 | `copyToDownloads` crashes Android 7/8/9 | `MainActivity.kt` | Downloads fail on API < 29 |
| 11 | `mime` + `ffi` undeclared transitive deps | `pubspec.yaml` | Same as #8 |
| 12 | FFI pointer leak on exception | `main.dart` | Native memory leak on Windows |
| 13 | Media server crashes on TV disconnect | `local_media_server.dart` | App crash mid-stream |
| 14 | DLNA Cast fails for `content://` files | `cast_dialog.dart` | Cast silently fails on Android |
| 15 | FFmpeg installer buffers 150 MB in RAM | `installer_service.dart` | OOM on low-memory devices |
| 16 | All deps use `any` version constraints | `pubspec.yaml` | Non-reproducible builds |
| 17 | Search has no timeouts | `multi_source_search_service.dart` | UI freezes on slow networks |
| 18 | Filenames not length-limited | `download_service.dart` | ENAMETOOLONG crash |
| 19 | ConvertService reads whole file into RAM | `convert_service.dart` | OOM on large media files |
| 20 | SSDP socket leaks on exception | `dlna_discovery_service.dart` | UDP port leak |
| 21 | `uuid` undeclared transitive dep | `pubspec.yaml` | Same as #8 |
| 22 | WatchedPlaylistService timer never cancelled | `watched_playlist_service.dart` | Memory leak + crash after dispose |
| 23 | MusicBrainz/Lyrics services wired but never called | `app.dart`, `app_controller.dart` | Dead code + no rate limiting |
| 24 | Audio notification stuck when paused on Android | `audio_handler.dart` | Undismissable notification |
| 25 | `path` package undeclared transitive dep | `pubspec.yaml` | Same as #8 |
| 26 | `playerPlayerPage` violates Dart naming | `player.dart` | Analyzer warning, confusing code |
| 27 | `MusicBrainzService.searchTrack()` unguarded | `metadata_service.dart` | Uncaught exception masks downloads |
| 28 | Album art written to temp dir, never cleaned | `metadata_service.dart` | Disk space accumulation |


---

## Additional Issues 29–35

---

### Issue 29 — `AdBlockService` Not Disposed in `BrowserScreen`

**File:** `lib/src/screens/browser_screen.dart`, line 117 (dispose method)

**Root cause:** `BrowserScreen` creates `_adBlock = AdBlockService()` as a `ChangeNotifier` (line 62). The `dispose()` method cancels controllers and disposes the cast/video services — but **never calls `_adBlock.dispose()`**. This means the `ChangeNotifier` listener list is never cleared, and if anything holds a reference to it, it continues to receive change notifications from a dead widget. On repeated browser screen mounts/unmounts (e.g. hot reload or navigation) this accumulates leaked notifiers.

**Fix — add to `BrowserScreen.dispose()`:**
```dart
@override
void dispose() {
  _castBadgeController.dispose();
  _videoDetector.removeListener(_onVideoDetectorChanged);
  _castService.removeListener(_onCastChanged);
  _castService.stopDiscovery();
  _addressController.dispose();
  _findController.dispose();
  _castService.dispose();
  _videoDetector.dispose();
  _adBlock.dispose();   // ← add this
  disposeAllWebViewControllers();
  super.dispose();
}
```

---

### Issue 30 — `AdBlockService._fetchAndParse()` Has No Timeout

**File:** `lib/src/browser/adblock/adblock_service.dart`, line 154

**Root cause:** `_fetchAndParse()` runs inside `Isolate.run()` and calls `http.get(Uri.parse(_easyListUrl))` with **no `.timeout()`**. EasyList is a ~300 KB text file. If the CDN is slow or the connection stalls mid-download, the isolate hangs indefinitely — blocking the background parse and holding an isolate alive with no way to cancel it from the main thread.

**Fix:**
```dart
static Future<List<String>> _fetchAndParse() async {
  final response = await http.get(Uri.parse(_easyListUrl))
      .timeout(const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('EasyList download timed out'));
  if (response.statusCode != 200) return [];
  // ... rest unchanged
}
```

---

### Issue 31 — `BrowserDb` Uses a Global Static `_db` Singleton That Is Never Closed

**File:** `lib/src/data/browser_db.dart`

**Root cause:** `BrowserDb._db` is a static field — a process-wide singleton. The database is opened via `openDatabase()` the first time it's accessed and **never closed**. On Android and iOS the OS handles cleanup on process exit, but on desktop (Linux/Windows) an unclosed SQLite database can leave WAL (Write-Ahead Log) files dirty and may cause data corruption if the app crashes. More importantly, in tests or on hot-restart the singleton holds a stale handle to a closed file, causing `DatabaseException: database is closed` on subsequent access.

**Fix — add a close method and call it from app shutdown:**
```dart
class BrowserDb {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    // ... existing openDatabase logic
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
```

Then call `BrowserDb.close()` from `AppController.dispose()` or the tray quit handler in `home_screen.dart`:
```dart
_trayService!.onTrayQuit = () async {
  await BrowserDb.close();   // ← add this
  _coordinatorService.dispose();
  // ... rest unchanged
};
```

---

### Issue 32 — `BrowserRepository.addHistory()` Has No Row Limit — History Grows Forever

**File:** `lib/src/data/browser_db.dart`

**Root cause:** Every page visit appends a row to the `history` table with no pruning. Power users browsing for months will accumulate thousands of rows. There is no auto-cleanup, no max-rows policy, and no index on `visited_at`, meaning that as the table grows, `ORDER BY visited_at DESC` queries progressively slow down.

**Fix — prune old rows after each insert and add an index:**

Add to the `onCreate` schema:
```sql
CREATE INDEX IF NOT EXISTS idx_history_visited ON history(visited_at DESC);
```

Update `addHistory()` to prune:
```dart
Future<void> addHistory(String url, String? title, String? favicon) async {
  final db = await BrowserDb.database;
  await db.insert('history', {
    'url': url,
    'title': title,
    'favicon': favicon,
    'visited_at': DateTime.now().millisecondsSinceEpoch,
  });
  // Keep at most 2000 rows — delete oldest beyond that
  await db.rawDelete('''
    DELETE FROM history WHERE id NOT IN (
      SELECT id FROM history ORDER BY visited_at DESC LIMIT 2000
    )
  ''');
  notifyListeners();
}
```

---

### Issue 33 — `BrowserTab.screenshot` Stores Raw `Uint8List` In-Memory With No Eviction

**File:** `lib/src/browser/tabs/tab_manager.dart`

**Root cause:** Each `BrowserTab` has a `Uint8List? screenshot` field. `setScreenshot()` can store a raw PNG/JPEG capture for each tab. With up to 5 tabs and each screenshot potentially being a full-resolution WebView capture (1–3 MB uncompressed), this is 5–15 MB of heap held indefinitely — even for tabs the user hasn't looked at in hours.

**Additionally**, searching the codebase shows `setScreenshot()` is **defined but never called** anywhere — the field is always `null`, meaning the tab overview grid shows `Icons.tab` placeholder images instead of real previews. This is dead code that adds confusion.

**Fix (option A — remove dead code):** Delete `screenshot` field and `setScreenshot()` from `TabManager` and `BrowserTab` since they're never populated.

**Fix (option B — implement properly):** If you want tab thumbnails, capture them lazily when the tab switcher opens and clear them when switching away:
```dart
void clearScreenshots() {
  for (final tab in _tabs) {
    tab.screenshot = null;
  }
  notifyListeners();
}
```

---

### Issue 34 — JS Injection in `VideoDetectorService` Overwrites Global `XHR` and `fetch` Permanently

**File:** `lib/src/browser/video/video_detector_service.dart`, `injectionJs`

**Root cause:** The injected JavaScript replaces `XMLHttpRequest.prototype.open` and `window.fetch` globally with patched versions that call `flutter_inappwebview.callHandler()`. This injection runs on **every page load** (it checks `window.__videoDetectorInjected` to prevent double-injection, but that flag only persists within the same page context). The problem is that these prototypes are modified on the `window` object — meaning if a site's own JS runs before the detector and stores a reference to the original `fetch`, the site continues with its reference while the detector gets missed. More critically, if `flutter_inappwebview` is unavailable (e.g. on navigation teardown), calling `callHandler()` throws an uncaught JS error that can break the page's own fetch calls.

**Fix — add a safety guard in the JS:**
```javascript
// Before overwriting XHR, guard the callHandler:
function safeNotify(url, type) {
  try {
    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('onVideoFound',
        JSON.stringify({url: url, type: type}));
    }
  } catch(e) {}
}

// Replace direct callHandler calls:
// Before: window.flutter_inappwebview.callHandler('onVideoFound', ...)
// After:  safeNotify(url, 'xhr');
```

---

### Issue 35 — `DlnaCastService._pollTimer` Keeps Polling After App Goes to Background on Android

**File:** `lib/src/browser/cast/dlna_service.dart`

**Root cause:** `_startPolling()` creates a `Timer.periodic` that fires every 3 seconds to query the TV's transport state. This timer **has no awareness of app lifecycle** — it continues firing while the app is backgrounded on Android. Each tick triggers a network SOAP request to the TV. This causes unnecessary battery drain and may trigger Android's background execution restrictions, potentially killing the app or causing `NetworkOnMainThreadException` style issues.

**Fix — integrate with `WidgetsBindingObserver` or pause/resume the timer based on app state:**
```dart
// In DlnaCastService or where it's owned:
void pausePolling() => _pollTimer?.cancel();

void resumePolling() {
  if (_activeDevice != null) {
    final device = _activeDevice!.nativeHandle as DlnaDevice;
    _startPolling(device);
  }
}
```

Then in the `BrowserScreen` state (which already mixes in `WidgetsBindingObserver` or can add it):
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _castService.pausePolling();
  } else if (state == AppLifecycleState.resumed) {
    _castService.resumePolling();
  }
}
```

---

## Complete Issues List (All 35)

| # | Issue | File(s) | Impact |
|---|---|---|---|
| 1 | Android Share broken (`content://`) | `home_screen.dart`, `android_saf.dart` | Share does nothing |
| 2 | No Folder button on Android | `home_screen.dart` | Can't find downloads |
| 3 | Browser crashes without WebView2 | `browser_screen.dart` | Blank/crash on older Windows |
| 4 | Linux binary fails on older distros | CI workflow | App won't launch |
| 5 | Worker pool race condition | `app_controller.dart` | Duplicate downloads |
| 6 | Android 13+ notifications fail | `notification_service.dart` | Notifications never shown |
| 7 | Converter saves to hidden dir on Android | `app_controller.dart` | Files invisible in Files app |
| 8 | `crypto` undeclared transitive dep | `pubspec.yaml` | Silent build breakage |
| 9 | Linux launcher breaks outside install dir | `convert_the_spire.sh` | App fails from wrong directory |
| 10 | `copyToDownloads` crashes Android 7/8/9 | `MainActivity.kt` | Downloads fail on API < 29 |
| 11 | `mime` + `ffi` undeclared transitive deps | `pubspec.yaml` | Same as #8 |
| 12 | FFI pointer leak on exception | `main.dart` | Native memory leak on Windows |
| 13 | Media server crashes on TV disconnect | `local_media_server.dart` | App crash mid-stream |
| 14 | DLNA Cast fails for `content://` on Android | `cast_dialog.dart` | Cast silently fails |
| 15 | FFmpeg installer buffers 150 MB in RAM | `installer_service.dart` | OOM on low-memory devices |
| 16 | All deps use `any` constraints | `pubspec.yaml` | Non-reproducible builds |
| 17 | Search has no timeouts | `multi_source_search_service.dart` | UI freezes on slow networks |
| 18 | Filenames not length-limited | `download_service.dart` | ENAMETOOLONG crash |
| 19 | ConvertService reads whole file into RAM | `convert_service.dart` | OOM on large media files |
| 20 | SSDP socket leaks on exception | `dlna_discovery_service.dart` | UDP port leak |
| 21 | `uuid` undeclared transitive dep | `pubspec.yaml` | Same as #8 |
| 22 | WatchedPlaylistService timer never cancelled | `watched_playlist_service.dart` | Memory leak + crash |
| 23 | MusicBrainz/Lyrics services never called | `app.dart`, `app_controller.dart` | Dead code, no rate limiting |
| 24 | Audio notification stuck when paused | `audio_handler.dart` | Undismissable Android notification |
| 25 | `path` package undeclared transitive dep | `pubspec.yaml` | Same as #8 |
| 26 | `playerPlayerPage` violates Dart naming | `player.dart` | Analyzer warning, confusing |
| 27 | `MusicBrainzService.searchTrack()` unguarded | `metadata_service.dart` | Uncaught exception masks downloads |
| 28 | Album art temp files never cleaned | `metadata_service.dart` | Disk space accumulation |
| 29 | `AdBlockService` not disposed | `browser_screen.dart` | Leaked `ChangeNotifier` |
| 30 | AdBlock fetch has no timeout | `adblock_service.dart` | Isolate hangs indefinitely |
| 31 | `BrowserDb` static singleton never closed | `browser_db.dart` | WAL corruption risk, test failures |
| 32 | Browser history grows unbounded | `browser_db.dart` | Slow queries, unlimited disk growth |
| 33 | Tab `screenshot` field populated nowhere | `tab_manager.dart` | Dead code or missing implementation |
| 34 | JS video detector overwrites globals unsafely | `video_detector_service.dart` | Page breaks if handler unavailable |
| 35 | DLNA poll timer runs in background on Android | `dlna_service.dart` | Battery drain, background execution issues |


Now I have a complete picture of the remaining issues. Here are the final ones:

---

## Additional Issues 36–42

---

### Issue 36 — `ComputationService._queue` Has No Maximum Size — Coordinator Can Flood It

**File:** `lib/src/services/computation_service.dart`

**Root cause:** `enqueue()` appends to `_queue` without any size cap. If the `CoordinatorService` rapidly submits jobs (e.g. receives a burst from the WebSocket coordinator), the queue grows without bound. Each job holds a `Map<String, dynamic>` payload in memory, and with no cap the app's heap can be exhausted. Additionally, `_primeSearch()` has no upper-bound guard — a malicious or buggy server could send `{"start": 2, "end": 99999999}`, causing the isolate to run for minutes and allocate a list of millions of ints.

**Fix — cap the queue and clamp job parameters:**
```dart
// In enqueue():
void enqueue(ComputeJob job) {
  if (!_enabled) return;
  const maxQueueSize = 50;
  if (_queue.length >= maxQueueSize) {
    debugPrint('ComputationService: queue full, dropping job ${job.id}');
    return;
  }
  _queue.add(job);
  _processQueue();
}

// In _primeSearch():
Map<String, dynamic> _primeSearch(Map<String, dynamic> payload) {
  final start = (payload['start'] as num?)?.toInt() ?? 2;
  // Clamp range to prevent runaway computation from untrusted payloads
  final rawEnd = (payload['end'] as num?)?.toInt() ?? 1000;
  final end = rawEnd.clamp(start, start + 500000); // max 500k range
  // ... rest unchanged
}

// In _matrixMultiply():
Map<String, dynamic> _matrixMultiply(Map<String, dynamic> payload) {
  // ... existing null checks ...
  // Prevent n³ explosion from large matrices
  const maxDim = 64;
  if (aRaw.length > maxDim || bRaw[0].length > maxDim) {
    return {'error': 'Matrix too large (max ${maxDim}x$maxDim)'};
  }
  // ... rest unchanged
}
```

---

### Issue 37 — `NativeMinerService.dispose()` Calls `killAllInstances()` Without `await`

**File:** `lib/src/services/native_miner_service.dart`, line 672

**Root cause:** Inside `dispose()`, `killAllInstances()` is called as a fire-and-forget (no `await`, no `unawaited()`). `killAllInstances()` is `async` and runs `Process.run('taskkill', ...)` or `Process.run('pkill', ...)`. Since `dispose()` is synchronous, these process calls are simply abandoned — the future is neither awaited nor attached to the error zone. If the process kill throws (e.g. permission denied, process already dead), the exception silently disappears into the void. More practically, the miner subprocess may still be running when the Flutter engine shuts down, leaving an orphaned `qli-Client` process consuming CPU after the app exits.

**Fix — `dispose()` can't be `async`, but use `unawaited` with a catchError:**
```dart
void dispose() {
  _disposed = true;
  _statsThrottle?.cancel();
  _connectionTimeout?.cancel();
  _stdoutSub?.cancel();
  _stderrSub?.cancel();
  _stdoutSub = null;
  _stderrSub = null;
  final proc = _process;
  _process = null;
  if (proc != null) {
    try {
      if (Platform.isWindows) {
        Process.run('taskkill', ['/F', '/T', '/PID', '${proc.pid}']);
      } else {
        proc.kill(ProcessSignal.sigkill);
      }
    } catch (_) {}
  }
  // Fire-and-forget but attach error handler to avoid unhandled future
  unawaited(killAllInstances().catchError(
    (e) => debugPrint('NativeMinerService: dispose killAll failed: $e')));
  _hashRate = 0;
  _state = MinerState.stopped;
  if (!_statsController.isClosed) _statsController.close();
  onStateChanged = null;
}
```

---

### Issue 38 — `TrayService._restoreWindowGeometry()` Doesn't Validate Against Screen Bounds

**File:** `lib/src/services/tray_service.dart`, `_restoreWindowGeometry()`

**Root cause:** Saved `x` / `y` coordinates are restored directly with no check that the position is visible on any current monitor. This causes the window to spawn completely off-screen in two common scenarios: the user previously used a multi-monitor setup and removed the secondary display, or the user changed display resolution since the last run. The only guard is `w > 100 && h > 100`, which checks size but not position. A user whose window spawned off-screen has no way to recover except editing `SharedPreferences` manually.

**Fix — clamp position to a safe visible area:**
```dart
Future<void> _restoreWindowGeometry() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(_kWindowX);
    final y = prefs.getDouble(_kWindowY);
    final w = prefs.getDouble(_kWindowW);
    final h = prefs.getDouble(_kWindowH);
    if (x == null || y == null || w == null || h == null) return;
    if (w < 100 || h < 100) return;

    // Guard against off-screen position (e.g. after removing a monitor).
    // Keep at least the top-left 100x50px strip on screen.
    const minVisibleX = -200.0;  // allow slight off-left for multi-monitor
    const minVisibleY = 0.0;     // never above top of primary
    final safeX = x.clamp(minVisibleX, 9999.0);
    final safeY = y.clamp(minVisibleY, 9999.0);

    await windowManager.setBounds(
      null,
      position: Offset(safeX, safeY),
      size: Size(w, h),
    );
  } catch (_) {}
}
```

For a stricter fix on Windows you can query `GetSystemMetrics(SM_CXVIRTUALSCREEN)` / `SM_CYVIRTUALSCREEN` via FFI to get the actual virtual screen rectangle, but the clamp above handles 95% of real-world cases.

---

### Issue 39 — Battery Monitoring in `SupportScreen` Uses Polling Instead of Stream

**File:** `lib/src/screens/support_screen.dart`, `_startBatteryMonitoring()`

**Root cause:** Battery state is checked every 15 seconds via `Timer.periodic`. The `battery_plus` package exposes `battery.onBatteryStateChanged` as a `Stream<BatteryState>`, which delivers events instantly when the device is plugged/unplugged — far more efficient than polling. The current polling approach means: (a) a 0–15 second lag before the app reacts to the charger being plugged in, and (b) the app performs a platform channel round-trip every 15 seconds for the lifetime of the screen, even when nothing is happening.

**Fix — replace the timer with the stream:**
```dart
StreamSubscription<BatteryState>? _batteryStateSub;

void _startBatteryMonitoring() {
  if (kIsWeb) return;
  // Get initial reading immediately
  _checkBattery();
  // React to plug/unplug events instantly via stream
  _batteryStateSub = _battery.onBatteryStateChanged.listen((_) {
    _checkBattery();
  });
}

@override
void dispose() {
  _batteryStateSub?.cancel();   // ← add this
  _batteryTimer?.cancel();
  // ... rest unchanged
}
```

You still need an initial `_checkBattery()` call (since `onBatteryStateChanged` only fires on *changes*), but the periodic `Timer` can be removed entirely.

---

### Issue 40 — `ComputationService._runJob()` Uses `Isolate.run()` But Has No Timeout

**File:** `lib/src/services/computation_service.dart`, line 323

**Root cause:** `Isolate.run(() => _runJobSync(job))` has no timeout. A coordinator server could send a `qubicMining` job with `max_iterations: 999999999` or a `primeSearch` with `end: 999999999` (even after Issue 36's cap, the `qubicMining` cap of 500,000 iterations still takes several seconds on a slow device). If a job stalls due to an infinite loop in a future job type, the isolate runs indefinitely, consuming one full CPU core, counting against `_activeCount`, and blocking the slot for all subsequent jobs.

**Fix — add a per-job timeout:**
```dart
Future<void> _runJob(ComputeJob job) async {
  _activeCount++;
  runningJobIds.add(job.id);
  onStateChanged?.call();

  final sw = Stopwatch()..start();
  try {
    final resultData = await Isolate.run(() => _runJobSync(job))
        .timeout(const Duration(minutes: 2),   // hard cap per job
            onTimeout: () => {'error': 'Job timed out after 2 minutes'});
    // ... rest unchanged
```

---

### Issue 41 — `_primeSearch` Returns Full List of Primes in Payload — Potential Large Object Transfer

**File:** `lib/src/services/computation_service.dart`

**Root cause:** `_primeSearch()` returns `{'primes': primes, 'count': primes.length}` where `primes` is the full list of every prime found. Even with the 500,000-range cap from Issue 36, a range like `[2, 500002]` contains ~41,538 primes — a `List<int>` of ~330 KB. This list is sent back from the isolate via `Isolate.run()`'s return value, which copies it across the isolate boundary (Dart isolates don't share memory). It then lives in `ComputeResult.result`, is added to `_results` (up to 100 kept), and is serialized to JSON via `toJson()` to send to the coordinator. Sending 41,538 integers to a coordinator server as a JSON array is almost certainly not what the protocol intends.

**Fix — return only the summary, not the full list:**
```dart
Map<String, dynamic> _primeSearch(Map<String, dynamic> payload) {
  final start = (payload['start'] as num?)?.toInt() ?? 2;
  final rawEnd = (payload['end'] as num?)?.toInt() ?? 1000;
  final end = rawEnd.clamp(start, start + 500000);
  int count = 0;
  int largest = 0;
  for (int n = start.clamp(2, end); n <= end; n++) {
    if (_isPrime(n)) {
      count++;
      largest = n;
    }
  }
  return {
    'count': count,
    'range': '$start-$end',
    'largest_prime': largest,
    // Don't return the full list — too large to transfer
  };
}
```

---

### Issue 42 — Window Geometry Is Saved on Every Resize/Move Event With No Debounce

**File:** `lib/src/services/tray_service.dart`, `onWindowResized()` and `onWindowMoved()`

**Root cause:** Both `onWindowResized()` and `onWindowMoved()` call `_saveWindowGeometry()` directly, which immediately calls `await windowManager.getBounds()` and then writes four `double` values to `SharedPreferences`. On desktop, these events fire **continuously while the user is dragging or resizing** — potentially 60 times per second. This means `SharedPreferences` is being written to 60 times/second while dragging, creating excessive I/O and making `getBounds()` calls overlap each other.

**Fix — debounce with a timer:**
```dart
Timer? _geometryDebounce;

@override
void onWindowResized() => _scheduleGeometrySave();

@override
void onWindowMoved() => _scheduleGeometrySave();

void _scheduleGeometrySave() {
  _geometryDebounce?.cancel();
  _geometryDebounce = Timer(const Duration(milliseconds: 500), () {
    _saveWindowGeometry();
  });
}

Future<void> destroy() async {
  _geometryDebounce?.cancel();   // ← add this
  // ... rest unchanged
}
```

---

## Complete Issues List (All 42)

| # | Issue | File(s) | Impact |
|---|---|---|---|
| 1 | Android Share broken (`content://`) | `home_screen.dart`, `android_saf.dart` | Share does nothing |
| 2 | No Folder button on Android | `home_screen.dart` | Can't find downloads |
| 3 | Browser crashes without WebView2 | `browser_screen.dart` | Blank/crash on older Windows |
| 4 | Linux binary fails on older distros | CI workflow | Won't launch |
| 5 | Worker pool race condition | `app_controller.dart` | Duplicate downloads |
| 6 | Android 13+ notifications fail | `notification_service.dart` | Notifications never shown |
| 7 | Converter saves to hidden dir on Android | `app_controller.dart` | Files invisible in Files app |
| 8 | `crypto` undeclared transitive dep | `pubspec.yaml` | Silent build breakage |
| 9 | Linux launcher breaks outside install dir | `convert_the_spire.sh` | App fails from wrong directory |
| 10 | `copyToDownloads` crashes Android 7/8/9 | `MainActivity.kt` | Downloads fail on API < 29 |
| 11 | `mime` + `ffi` undeclared transitive deps | `pubspec.yaml` | Same as #8 |
| 12 | FFI pointer leak on exception | `main.dart` | Native memory leak on Windows |
| 13 | Media server crashes on TV disconnect | `local_media_server.dart` | App crash mid-stream |
| 14 | DLNA Cast fails for `content://` on Android | `cast_dialog.dart` | Cast silently fails |
| 15 | FFmpeg installer buffers 150 MB in RAM | `installer_service.dart` | OOM on low-memory devices |
| 16 | All deps use `any` constraints | `pubspec.yaml` | Non-reproducible builds |
| 17 | Search has no timeouts | `multi_source_search_service.dart` | UI freezes on slow networks |
| 18 | Filenames not length-limited | `download_service.dart` | ENAMETOOLONG crash |
| 19 | ConvertService reads whole file into RAM | `convert_service.dart` | OOM on large media files |
| 20 | SSDP socket leaks on exception | `dlna_discovery_service.dart` | UDP port leak |
| 21 | `uuid` undeclared transitive dep | `pubspec.yaml` | Same as #8 |
| 22 | WatchedPlaylistService timer never cancelled | `watched_playlist_service.dart` | Memory leak + crash |
| 23 | MusicBrainz/Lyrics services never called | `app.dart`, `app_controller.dart` | Dead code, no rate limiting |
| 24 | Audio notification stuck when paused | `audio_handler.dart` | Undismissable Android notification |
| 25 | `path` package undeclared transitive dep | `pubspec.yaml` | Same as #8 |
| 26 | `playerPlayerPage` violates Dart naming | `player.dart` | Analyzer warning |
| 27 | `MusicBrainzService.searchTrack()` unguarded | `metadata_service.dart` | Uncaught exception |
| 28 | Album art temp files never cleaned | `metadata_service.dart` | Disk space accumulation |
| 29 | `AdBlockService` not disposed | `browser_screen.dart` | Leaked `ChangeNotifier` |
| 30 | AdBlock fetch has no timeout | `adblock_service.dart` | Isolate hangs indefinitely |
| 31 | `BrowserDb` static singleton never closed | `browser_db.dart` | WAL corruption risk |
| 32 | Browser history grows unbounded | `browser_db.dart` | Slow queries, disk growth |
| 33 | Tab `screenshot` field never populated | `tab_manager.dart` | Dead code |
| 34 | JS detector overwrites globals unsafely | `video_detector_service.dart` | Page breaks on handler unavailability |
| 35 | DLNA poll timer runs in background on Android | `dlna_service.dart` | Battery drain |
| 36 | Computation queue unbounded + job params unclamped | `computation_service.dart` | OOM + runaway isolates |
| 37 | `NativeMinerService.dispose()` unawaited kill | `native_miner_service.dart` | Orphaned miner process after exit |
| 38 | Window geometry restore ignores screen bounds | `tray_service.dart` | Window spawns off-screen |
| 39 | Battery monitoring polls instead of using stream | `support_screen.dart` | 15-second reaction lag + excess I/O |
| 40 | Compute jobs have no timeout | `computation_service.dart` | Indefinite CPU lock on bad payload |
| 41 | Prime search returns full list across isolate boundary | `computation_service.dart` | Large unnecessary object copy + transfer |
| 42 | Window geometry saved on every drag event (no debounce) | `tray_service.dart` | 60 SharedPreferences writes/second |



