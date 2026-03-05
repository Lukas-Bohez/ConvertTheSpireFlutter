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
    final desktop = _windowsDesktopPath();
    if (desktop == null) return;

    final shortcutPath = '$desktop\\Convert the Spire Reborn.lnk';
    if (await File(shortcutPath).exists()) {
      debugPrint('ShortcutService: shortcut already exists');
      return;
    }

    final exePath = Platform.resolvedExecutable;
    final workingDir = File(exePath).parent.path;

    // Use PowerShell COM to create a proper .lnk shortcut
    final script = '''
\$ws = New-Object -ComObject WScript.Shell
\$s = \$ws.CreateShortcut('$shortcutPath')
\$s.TargetPath = '$exePath'
\$s.WorkingDirectory = '$workingDir'
\$s.Description = 'Convert the Spire Reborn'
\$s.Save()
''';

    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
    );

    if (result.exitCode == 0) {
      debugPrint('ShortcutService: created Windows desktop shortcut');
    } else {
      debugPrint('ShortcutService: PowerShell shortcut creation failed: ${result.stderr}');
    }
  }

  static String? _windowsDesktopPath() {
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile == null) return null;
    final desktop = '$userProfile\\Desktop';
    if (Directory(desktop).existsSync()) return desktop;
    // Fallback: OneDrive desktop
    final oneDrive = Platform.environment['OneDrive'];
    if (oneDrive != null) {
      final odDesktop = '$oneDrive\\Desktop';
      if (Directory(odDesktop).existsSync()) return odDesktop;
    }
    return null;
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
