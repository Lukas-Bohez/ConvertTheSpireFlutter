yt-dlp Updater

This lightweight updater provides helper functions to update the `yt-dlp` binary from GitHub releases.

Usage (Dart):

```dart
import 'package:your_app/src/services/yt_dlp_updater.dart';

// Check and perform update using GitHub latest release
final ok = await YtDlpUpdater.updateFromGithubLatest();
if (ok) print('yt-dlp updated');
```

Notes & limitations:
- The updater chooses a release asset heuristically based on platform keywords in asset names.
- SHA256 verification is supported if you supply a checksum; GitHub releases do not always provide checksums.
- On non-Windows platforms the updater attempts to run `chmod +x` on the downloaded file; this may fail on restricted environments.
- Files are stored under the application's support directory in a `binaries/` subfolder.
