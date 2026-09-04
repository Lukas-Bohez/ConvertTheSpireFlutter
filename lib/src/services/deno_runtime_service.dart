// ignore_for_file: prefer_single_quotes
import "dart:io";

import "package:flutter/foundation.dart" show debugPrint, kIsWeb;
import "package:http/http.dart" as http;
import "package:path/path.dart" as p;

import "platform_dirs.dart";

class DenoRuntimeService {
  DenoRuntimeService._();

  static String? _cachedPath;

  static Future<String?> resolveOrDownload() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) return null;
    if (_cachedPath != null && await File(_cachedPath!).exists()) {
      return _cachedPath;
    }
    final existing = await _locateExistingDeno();
    if (existing != null && await File(existing).exists()) {
      _cachedPath = existing;
      return existing;
    }
    try {
      final support = await PlatformDirs.getAppSupportDir();
      if (support == null) return null;
      final binDir = Directory(p.join(support.path, "deno"));
      if (!await binDir.exists()) await binDir.create(recursive: true);

      final bool isWindows = Platform.isWindows;
      final String assetName;
      final bool isArmMac = Platform.isMacOS && (await _cpuArchitecture() == "arm64");
      if (isWindows) {
        assetName = "deno-x86_64-pc-windows-msvc.zip";
      } else if (Platform.isLinux) {
        assetName = "deno-x86_64-unknown-linux-gnu.zip";
      } else if (isArmMac) {
        assetName = "deno-aarch64-apple-darwin.zip";
      } else {
        assetName = "deno-x86_64-apple-darwin.zip";
      }

      final url = "https://github.com/denoland/deno/releases/latest/download/$assetName";
      final destBase = p.join(binDir.path, assetName.replaceAll(".zip", ""));
      final destFile = File(destBase);
      if (await destFile.exists()) {
        _cachedPath = destBase;
        return destBase;
      }

      debugPrint("deno-runtime: downloading Deno ($assetName)");
      final dl = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (dl.statusCode != 200) {
        return null;
      }
      final zipPath = p.join(binDir.path, assetName);
      await File(zipPath).writeAsBytes(dl.bodyBytes, flush: true);

      if (isWindows) {
        final out = await Process.run("tar", ["-xf", zipPath, "-C", binDir.path], runInShell: true);
        if (out.exitCode != 0) {
          await Process.run("powershell", ["-NoProfile", "-Command", "Expand-Archive -Force '$zipPath' -DestinationPath '$binDir.path'"], runInShell: true);
        }
      } else {
        await Process.run("tar", ["-xf", zipPath, "-C", binDir.path], runInShell: true);
        await Process.run("chmod", ["+x", destBase]);
      }
      try { await File(zipPath).delete(); } catch (_) {}

      if (await destFile.exists()) {
        _cachedPath = destBase;
        return destBase;
      }
      return null;
    } catch (e) {
      debugPrint("deno-runtime: failed to provision Deno: $e");
      return null;
    }
  }

  static Future<String?> _locateExistingDeno() async {
    const paths = [
      "C:\\Program Files\\deno\\deno.exe",
      "/usr/bin/deno",
      "/usr/local/bin/deno",
      "/opt/homebrew/bin/deno",
      "/root/.deno/bin/deno",
    ];
    for (final pPath in paths) {
      if (await File(pPath).exists()) return pPath;
    }
    try {
      final result = await Process.run(Platform.isWindows ? "where" : "which", ["deno"], runInShell: true).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final candidate = result.stdout.toString().trim().split(RegExp(r"\r?\n")).firstWhere((l) => l.trim().isNotEmpty, orElse: () => "");
        if (candidate.isNotEmpty && await File(candidate).exists()) return candidate;
      }
    } catch (_) {}
    return null;
  }

  static Future<String> _cpuArchitecture() async {
    try {
      final r = await Process.run(Platform.isWindows ? "echo" : "uname", Platform.isWindows ? ["%PROCESSOR_ARCHITECTURE%"] : ["-m"], runInShell: true);
      return r.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return "x86_64";
    }
  }
}
