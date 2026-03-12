import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Creates a desktop shortcut for the application if one does not already exist.
class ShortcutService {
  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Ensure a desktop shortcut exists.  Does nothing on non-desktop platforms.
  static Future<void> ensureDesktopShortcut() async {
    if (!_isDesktop) return;

    try {
      if (Platform.isWindows) {
        await _ensureWindowsShortcut();
      } else if (Platform.isLinux) {
        await _ensureLinuxDesktopEntry();
      }
    } catch (e) {
      debugPrint('ShortcutService: failed to create desktop shortcut: $e');
    }
  }

  // ── Windows (.lnk via PowerShell) ─────────────────────────────────────

  static Future<void> _ensureWindowsShortcut() async {
    final exePath = Platform.resolvedExecutable;
    final workingDir = File(exePath).parent.path;

    // Use PowerShell to resolve the real Desktop path (locale-independent)
    // and create the shortcut in one script.  All Dart values are injected
    // via single-quoted PowerShell strings with internal quotes escaped.
    final safeExe = exePath.replaceAll("'", "''");
    final safeWork = workingDir.replaceAll("'", "''");

    final script = '''
\$desktop = [Environment]::GetFolderPath('Desktop')
if (-not \$desktop) { exit 1 }
\$lnk = Join-Path \$desktop 'Convert the Spire Reborn.lnk'
if (Test-Path \$lnk) { exit 0 }
\$ws = New-Object -ComObject WScript.Shell
\$s  = \$ws.CreateShortcut(\$lnk)
\$s.TargetPath       = '$safeExe'
\$s.WorkingDirectory  = '$safeWork'
\$s.Description       = 'Convert the Spire Reborn'
\$s.Save()
''';

    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
    );

    if (result.exitCode == 0) {
      debugPrint('ShortcutService: desktop shortcut OK');
    } else {
      debugPrint('ShortcutService: PowerShell shortcut failed: '
          '${result.stderr}');
    }
  }

  // ── Linux (.desktop file) ─────────────────────────────────────────────

  static Future<void> _ensureLinuxDesktopEntry() async {
    final home = Platform.environment['HOME'];
    if (home == null) return;

    final desktopDir = '$home/Desktop';
    final shortcutPath = '$desktopDir/convert-the-spire-reborn.desktop';
    if (await File(shortcutPath).exists()) {
      debugPrint('ShortcutService: desktop entry already exists');
      return;
    }

    // Ensure ~/Desktop exists
    await Directory(desktopDir).create(recursive: true);

    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    // Look for an icon next to the exe
    final iconPath = '$exeDir/data/flutter_assets/assets/icons/favicon-192x192.png';

    final content = '''[Desktop Entry]
Type=Application
Name=Convert the Spire Reborn
Exec=$exePath
Icon=$iconPath
Terminal=false
Categories=AudioVideo;Audio;
Comment=Download, convert & play media
''';

    await File(shortcutPath).writeAsString(content);
    // Make executable so the DE recognizes it
    await Process.run('chmod', ['+x', shortcutPath]);
    debugPrint('ShortcutService: created Linux desktop entry');
  }
}
