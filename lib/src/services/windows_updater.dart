import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Updates the Windows app in place with the release's Setup.exe.
///
/// Downloads ConvertTheSpireReborn-Setup.exe, checks it against the release's
/// SHA256SUMS.txt, runs it and quits. Setup closes anything left of the app,
/// replaces the files and starts the new version. A file the app downloads
/// itself carries no "downloaded from the internet" mark, so Windows shows no
/// SmartScreen screen for it; only the very first Setup.exe from a browser
/// does.
class WindowsUpdater {
  WindowsUpdater._();

  static const String installerName = 'ConvertTheSpireReborn-Setup.exe';

  /// Where Setup installs: %LOCALAPPDATA%\Programs\ConvertTheSpireReborn.
  static String? installedDir([Map<String, String>? environment]) {
    final local = (environment ?? Platform.environment)['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    return p.join(local, 'Programs', 'ConvertTheSpireReborn');
  }

  /// True when [exePath] is the copy Setup installed. That copy updates
  /// silently; one run from an extracted zip gets the normal installer
  /// instead, so the user sees it move to the installed location.
  static bool isInstalledCopy(String exePath, [Map<String, String>? environment]) {
    final dir = installedDir(environment);
    if (dir == null) return false;
    return p.equals(p.dirname(exePath).toLowerCase(), dir.toLowerCase());
  }

  /// The installer's hash from a SHA256SUMS.txt, whose lines look like
  /// `<hash>  ./windows-installer/ConvertTheSpireReborn-Setup.exe`.
  static String? expectedHash(String sums) {
    for (final line in sums.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final name = parts.last.replaceAll('\\', '/').split('/').last;
      if (name.toLowerCase() == installerName.toLowerCase() &&
          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(parts.first)) {
        return parts.first.toLowerCase();
      }
    }
    return null;
  }

  /// Arguments for Setup: silent for the installed copy, none otherwise.
  static List<String> setupArguments(bool silent) => silent
      ? const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']
      : const [];

  /// Downloads and checks the installer, starts it and quits the app.
  /// [onProgress] gets 0..1 while downloading (null when the size is
  /// unknown). Throws when the download or the check fails; nothing is run
  /// then.
  static Future<void> downloadAndInstall({
    required String installerUrl,
    required String checksumsUrl,
    required String version,
    void Function(double? progress)? onProgress,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final sums = await c
          .get(Uri.parse(checksumsUrl))
          .timeout(const Duration(seconds: 30));
      if (sums.statusCode != 200) {
        throw Exception('SHA256SUMS.txt: HTTP ${sums.statusCode}');
      }
      final expected = expectedHash(sums.body);
      if (expected == null) {
        throw Exception('$installerName is not in SHA256SUMS.txt');
      }

      final dir = Directory(p.join(Directory.systemTemp.path,
          'ConvertTheSpireReborn-update'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'ConvertTheSpireReborn-Setup-$version.exe'));

      final response = await c
          .send(http.Request('GET', Uri.parse(installerUrl)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('$installerName: HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(total != null && total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
      }

      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != expected) {
        await file.delete();
        throw Exception('$installerName does not match its checksum');
      }

      final silent = isInstalledCopy(Platform.resolvedExecutable);
      await Process.start(file.path, setupArguments(silent),
          mode: ProcessStartMode.detached);
      // Setup closes anything still running, but leaving first is quicker.
      exit(0);
    } finally {
      if (client == null) c.close();
    }
  }
}
