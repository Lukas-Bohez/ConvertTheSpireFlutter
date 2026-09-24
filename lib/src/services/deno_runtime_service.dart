// ignore_for_file: prefer_single_quotes
import "dart:io";

import "package:flutter/foundation.dart" show debugPrint, kIsWeb;
import "package:http/http.dart" as http;
import "package:path/path.dart" as p;

import "../utils/process_runner.dart";
import "platform_dirs.dart";
import "session_log_service.dart";

class DenoRuntimeService {
  DenoRuntimeService._();

  static String? _cachedPath;

  static Future<String?> resolveOrDownload() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) return null;
    if (_cachedPath != null && await File(_cachedPath!).exists()) {
      if (await _verifyDenoRuns(_cachedPath!)) {
        return _cachedPath;
      }
      _note(
        "verify_failed_cached",
        "deno-runtime: cached binary at $_cachedPath failed verification, re-provisioning",
      );
    }
    final existing = await _locateExistingDeno();
    if (existing != null && await File(existing).exists()) {
      if (await _verifyDenoRuns(existing)) {
        _cachedPath = existing;
        _note("ok", "deno-runtime: using existing Deno at $existing");
        return existing;
      }
      _note(
        "verify_failed_existing",
        "deno-runtime: existing Deno at $existing failed verification",
      );
    }
    try {
      final support = await PlatformDirs.getAppSupportDir();
      if (support == null) {
        _note("no_support_dir",
            "deno-runtime: no app support dir, cannot provision Deno");
        return null;
      }
      final binDir = Directory(p.join(support.path, "deno"));
      if (!await binDir.exists()) await binDir.create(recursive: true);

      final bool isWindows = Platform.isWindows;
      final String assetName;
      final bool isArmMac =
          Platform.isMacOS && (await _cpuArchitecture() == "arm64");
      if (isWindows) {
        assetName = "deno-x86_64-pc-windows-msvc.zip";
      } else if (Platform.isLinux) {
        assetName = "deno-x86_64-unknown-linux-gnu.zip";
      } else if (isArmMac) {
        assetName = "deno-aarch64-apple-darwin.zip";
      } else {
        assetName = "deno-x86_64-apple-darwin.zip";
      }

      final url =
          "https://github.com/denoland/deno/releases/latest/download/$assetName";
      final destBase = p.join(binDir.path, assetName.replaceAll(".zip", ""));

      // Check for the *actual* extracted binary BEFORE downloading. Official
      // Deno zips unpack a single `deno.exe` (Windows) / `deno` (Unix) at the
      // archive root — never a file named like the asset. Earlier versions
      // only checked `destBase` (extension-less on Windows), so a successful
      // download+extract was invisible on every subsequent call:
      // resolveOrDownload() returned null forever and re-downloaded the whole
      // zip on each attempt, leaving yt-dlp without a JS runtime and downloads
      // failing with "page needs to be reloaded".
      final found = await _findProvisionedBinary(binDir, destBase);
      if (found != null) {
        if (await _verifyDenoRuns(found)) {
          _cachedPath = found;
          _note("ok", "deno-runtime: using provisioned Deno at $found");
          return found;
        }
        _note(
          "verify_failed_provisioned",
          "deno-runtime: provisioned Deno at $found exists but failed to run",
        );
      }

      _note("downloading", "deno-runtime: downloading Deno ($assetName)");
      final dl =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
      if (dl.statusCode != 200) {
        _note(
          "download_failed_http_${dl.statusCode}",
          "deno-runtime: download failed, HTTP ${dl.statusCode} from $url",
        );
        return null;
      }
      final zipPath = p.join(binDir.path, assetName);
      await File(zipPath).writeAsBytes(dl.bodyBytes, flush: true);

      if (isWindows) {
        final out = await Process.run(
            "tar", ["-xf", zipPath, "-C", binDir.path],
            runInShell: true);
        if (out.exitCode != 0) {
          await Process.run(
              "powershell",
              [
                "-NoProfile",
                "-Command",
                "Expand-Archive -Force '$zipPath' -DestinationPath '${binDir.path}'"
              ],
              runInShell: true);
        }
      } else {
        await Process.run("tar", ["-xf", zipPath, "-C", binDir.path],
            runInShell: true);
      }
      try {
        await File(zipPath).delete();
      } catch (_) {}

      final downloaded = await _findProvisionedBinary(binDir, destBase);
      if (downloaded != null) {
        if (await _verifyDenoRuns(downloaded)) {
          _cachedPath = downloaded;
          _note("ok", "deno-runtime: provisioned Deno at $downloaded");
          return downloaded;
        }
        _note(
          "verify_failed_downloaded",
          "deno-runtime: downloaded Deno at $downloaded exists but failed to run",
        );
      }
      _note(
        "binary_not_found",
        "deno-runtime: downloaded and extracted but binary not found in ${binDir.path}",
      );
      return null;
    } catch (e) {
      _note("provision_failed", "deno-runtime: failed to provision Deno: $e");
      return null;
    }
  }

  /// Locates the Deno binary inside [binDir], before or after extraction.
  ///
  /// Official Deno release zips contain a single `deno.exe` (Windows) or
  /// `deno` (Unix) at the archive root. The asset-derived [destBase] name is
  /// also accepted so binaries from other layouts keep resolving.
  static Future<String?> _findProvisionedBinary(
      Directory binDir, String destBase) async {
    final candidates = <String>[
      if (Platform.isWindows) ...[
        p.join(binDir.path, "deno.exe"),
        "$destBase.exe",
      ] else ...[
        p.join(binDir.path, "deno"),
      ],
      destBase,
    ];
    for (final candidate in candidates) {
      final f = File(candidate);
      if (await f.exists()) {
        if (!Platform.isWindows) {
          await Process.run("chmod", ["+x", candidate]);
        }
        return candidate;
      }
    }
    return null;
  }

  /// Best-effort breadcrumb into session_log_*.log (flushed on exit/error).
  ///
  /// debugPrint output is invisible for a released Windows GUI app, so the
  /// failure modes below were previously unobservable in the field. Each
  /// distinct [key] is recorded once per session; repeated download attempts
  /// must not spam the log.
  static void _note(String key, String message) {
    debugPrint(message);
    try {
      SessionLogService.instance.markOnce("deno-$key", message);
    } catch (_) {}
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
      final result = await Process.run(
              Platform.isWindows ? "where" : "which", ["deno"],
              runInShell: true)
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final candidate = result.stdout
            .toString()
            .trim()
            .split(RegExp(r"\r?\n"))
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => "");
        if (candidate.isNotEmpty && await File(candidate).exists()) {
          return candidate;
        }
      }
    } catch (_) {}
    _note(
      "not_on_path",
      "deno-runtime: no existing Deno found on PATH or in known locations",
    );
    return null;
  }

  /// Verifies the Deno binary at [path] actually runs by checking its
  /// version string. Catches cases where the binary exists on disk but
  /// crashes immediately (e.g. CPU instruction-set baseline mismatch on
  /// older machines) - resolveOrDownload() only checks file existence,
  /// not that the binary is executable on this CPU.
  static Future<bool> _verifyDenoRuns(String path) async {
    try {
      final r = await runProcess(path, const ["--version"],
          timeout: const Duration(seconds: 10));
      if (r.ok) {
        debugPrint(
            "deno-runtime: verified Deno at $path: ${r.stdout.toString().trim()}");
        return true;
      }
      debugPrint(
          "deno-runtime: Deno at $path exited with code ${r.exitCode}: ${r.stderr}");
      return false;
    } catch (e) {
      debugPrint("deno-runtime: Deno at $path failed to run: $e");
      return false;
    }
  }

  static Future<String> _cpuArchitecture() async {
    try {
      final r = await Process.run(Platform.isWindows ? "echo" : "uname",
          Platform.isWindows ? ["%PROCESSOR_ARCHITECTURE%"] : ["-m"],
          runInShell: true);
      return r.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return "x86_64";
    }
  }
}
