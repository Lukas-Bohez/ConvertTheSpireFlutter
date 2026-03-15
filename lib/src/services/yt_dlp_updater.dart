import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Simple updater for the `yt-dlp` binary.
///
/// Features:
/// - Query GitHub releases for latest `yt-dlp` release.
/// - Download a chosen asset to the app support directory.
/// - Optional SHA256 verification.
/// - Replace the existing binary atomically (with a .bak fallback).
class YtDlpUpdater {
  static const _githubLatest = 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';

  /// Fetch the latest release metadata from GitHub.
  /// Returns a map with keys `tag_name` and `assets` (raw JSON) on success.
  static Future<Map<String, dynamic>?> fetchLatestRelease() async {
    try {
      final r = await http.get(Uri.parse(_githubLatest));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      print('yt-dlp: fetchLatestRelease failed: $e');
      return null;
    }
  }

  /// Pick the best-matching asset for the current platform from a GitHub assets list.
  /// Asset objects are the `assets` array items from the GitHub release JSON.
  static Map<String, dynamic>? pickAssetForPlatform(List assets) {
    bool isAndroid = Platform.isAndroid;
    bool isWindows = Platform.isWindows;
    bool isLinux = Platform.isLinux;
    bool isMac = Platform.isMacOS;

    Map<String, dynamic>? chosen;

    // heuristics: prefer platform keyword in filename
    for (final a in assets) {
      final name = (a['name'] ?? '') as String;
      final lname = name.toLowerCase();
      if (isAndroid && lname.contains('android')) {
        chosen = a as Map<String, dynamic>;
        break;
      }
      if (isWindows && (lname.endsWith('.exe') || lname.contains('windows'))) {
        chosen = a as Map<String, dynamic>;
        break;
      }
      if (isLinux && (lname.contains('linux') || lname.contains('manylinux') || lname.endsWith('.xz'))) {
        chosen = a as Map<String, dynamic>;
        break;
      }
      if (isMac && (lname.contains('macos') || lname.contains('darwin'))) {
        chosen = a as Map<String, dynamic>;
        break;
      }
    }

    // fallback: pick first asset that looks executable-ish
    chosen ??= assets.cast<Map<String, dynamic>>().firstWhere(
      (a) {
        final n = (a['name'] ?? '') as String;
        final ln = n.toLowerCase();
        return ln.contains('yt-dlp') || ln.endsWith('.exe') || ln.endsWith('.xz') || ln.endsWith('.zip');
      },
      orElse: () => assets.first as Map<String, dynamic>,
    );

    return chosen;
  }

  /// Download the asset at [url] and replace the target file named [filename]
  /// inside the application's support directory. If [expectedSha256] is provided
  /// the downloaded bytes will be verified.
  static Future<bool> downloadAndReplace(String url, String filename, {String? expectedSha256}) async {
    try {
      final client = http.Client();
      final resp = await client.send(http.Request('GET', Uri.parse(url)));
      if (resp.statusCode != 200) {
        print('yt-dlp: download failed status=${resp.statusCode}');
        return false;
      }

      final appDir = await getApplicationSupportDirectory();
      final outDir = Directory(p.join(appDir.path, 'binaries'));
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final tmpPath = p.join(outDir.path, '$filename.download');
      final tmpFile = File(tmpPath);
      final sink = tmpFile.openWrite();

      await resp.stream.pipe(sink);
      await sink.flush();
      await sink.close();

      if (expectedSha256 != null) {
        final bytes = await tmpFile.readAsBytes();
        final sum = sha256.convert(bytes).toString();
        if (sum != expectedSha256.toLowerCase()) {
          print('yt-dlp: sha256 mismatch (got=$sum expected=$expectedSha256)');
          try {
            await tmpFile.delete();
          } catch (_) {}
          return false;
        }
      }

      final destPath = p.join(outDir.path, filename);
      final destFile = File(destPath);

      // backup existing
      if (await destFile.exists()) {
        final bak = File('$destPath.bak');
        try {
          if (await bak.exists()) await bak.delete();
        } catch (_) {}
        await destFile.rename(bak.path);
      }

      await tmpFile.rename(destPath);

      // ensure executable on platforms that support it
      try {
        if (!Platform.isWindows) {
          final res = await Process.run('chmod', ['+x', destPath]);
          if (res.exitCode != 0) print('yt-dlp: chmod failed: ${res.stderr}');
        }
      } catch (e) {
        print('yt-dlp: chmod not available or failed: $e');
      }

      print('yt-dlp: successfully updated $destPath');
      return true;
    } catch (e) {
      print('yt-dlp: downloadAndReplace failed: $e');
      return false;
    }
  }

  /// High-level convenience: check GitHub latest, pick an asset for the current
  /// platform and download/replace it. Returns true on success.
  static Future<bool> updateFromGithubLatest() async {
    final rel = await fetchLatestRelease();
    if (rel == null) return false;
    final tag = rel['tag_name'] as String? ?? 'latest';
    final assets = rel['assets'] as List? ?? [];
    if (assets.isEmpty) return false;

    final asset = pickAssetForPlatform(assets);
    if (asset == null) return false;

    final url = asset['browser_download_url'] as String?;
    final name = asset['name'] as String? ?? 'yt-dlp';
    if (url == null) return false;

    // GitHub doesn't always publish sha256; we attempt download without verify.
    print('yt-dlp: updating to $tag using asset $name');
    return await downloadAndReplace(url, name);
  }
}
