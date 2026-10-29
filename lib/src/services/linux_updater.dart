import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'release_checksums.dart';

/// Updates the Linux AppImage in place.
///
/// Downloads the release's AppImage next to the running one, checks it
/// against the release's SHA256SUMS.txt, puts it in the old one's place and
/// starts it. The running copy keeps its old file open until it quits, so
/// replacing it is safe. The tar.gz has no in-place update: its banner opens
/// the release page.
class LinuxUpdater {
  LinuxUpdater._();

  /// The AppImage the app runs from (its runtime sets APPIMAGE), or null
  /// when it does not run as an AppImage.
  static String? runningAppImage([Map<String, String>? environment]) {
    final path = (environment ?? Platform.environment)['APPIMAGE'];
    return path == null || path.isEmpty ? null : path;
  }

  /// Downloads and checks [assetName] from [assetUrl], replaces the running
  /// AppImage with it, starts it and quits the app. [onProgress] gets 0..1
  /// while downloading (null when the size is unknown). Throws when the
  /// download, the check or the replacing fails (a folder the user cannot
  /// write to); the old AppImage is left as it was then.
  static Future<void> downloadAndReplace({
    required String assetUrl,
    required String assetName,
    required String checksumsUrl,
    void Function(double? progress)? onProgress,
    Future<void> Function()? beforeExit,
    http.Client? client,
  }) async {
    final target = runningAppImage();
    if (target == null) throw StateError('Not running as an AppImage');
    final c = client ?? http.Client();
    // In the same folder, so the swap below is one rename.
    final download = File('$target.download');
    try {
      final sums = await c
          .get(Uri.parse(checksumsUrl))
          .timeout(const Duration(seconds: 30));
      if (sums.statusCode != 200) {
        throw Exception('SHA256SUMS.txt: HTTP ${sums.statusCode}');
      }
      final expected = releaseFileHash(sums.body, assetName);
      if (expected == null) {
        throw Exception('$assetName is not in SHA256SUMS.txt');
      }

      final response = await c
          .send(http.Request('GET', Uri.parse(assetUrl)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('$assetName: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = download.openWrite();
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          onProgress
              ?.call(total != null && total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
      }

      final actual = (await sha256.bind(download.openRead()).first).toString();
      if (actual != expected) {
        throw Exception('$assetName does not match its checksum');
      }

      final chmod = await Process.run('chmod', ['755', download.path]);
      if (chmod.exitCode != 0) throw Exception('chmod: ${chmod.stderr}');
      await download.rename(target);

      await beforeExit?.call();
      // Started a moment after this copy has quit: a second start while it
      // still runs would hand its start to it and close (one copy at a time).
      await Process.start('/bin/sh', ['-c', r'sleep 1; exec "$0"', target],
          mode: ProcessStartMode.detached);
      exit(0);
    } finally {
      if (await download.exists()) {
        try {
          await download.delete();
        } catch (_) {}
      }
      if (client == null) c.close();
    }
  }
}
