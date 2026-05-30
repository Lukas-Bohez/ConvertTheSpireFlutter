import 'dart:io';

import 'package:path/path.dart' as p;

class StartupService {
  static Future<bool> enable() async {
    if (Platform.isWindows) {
      return _enableWindows();
    }
    if (Platform.isLinux) {
      return _enableLinux();
    }
    if (Platform.isMacOS) {
      // macOS autostart is unsupported in this helper.
      return false;
    }
    return false;
  }

  static Future<bool> disable() async {
    if (Platform.isWindows) {
      return _disableWindows();
    }
    if (Platform.isLinux) {
      return _disableLinux();
    }
    if (Platform.isMacOS) {
      return false;
    }
    return false;
  }

  /// Creates a desktop shortcut/icon if one does not already exist.
  /// Called once on first run so the user can find the app again.
  /// Safe to call on every startup  -  checks for existence before creating.
  static Future<void> ensureDesktopShortcut() async {
    if (Platform.isWindows) {
      await _ensureDesktopShortcutWindows();
    } else if (Platform.isLinux) {
      await _ensureDesktopShortcutLinux();
    }
    // macOS: the app bundle is the icon; no shortcut needed.
  }

  static Future<void> _ensureDesktopShortcutWindows() async {
    try {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) return;
      final desktopPath = p.join(userProfile, 'Desktop');
      final linkPath = p.join(desktopPath, 'VaultTheSpire.lnk');
      // Only create if it does not already exist.
      if (await File(linkPath).exists()) return;
      final exePath = Platform.resolvedExecutable;
      final script = '''
\$w = New-Object -ComObject WScript.Shell
\$s = \$w.CreateShortcut("$linkPath")
\$s.TargetPath = "$exePath"
\$s.WorkingDirectory = "${p.dirname(exePath)}"
\$s.Description = "VaultTheSpire  -  Private Torrent & Messaging"
\$s.Save()
''';
      await Process.run('powershell', ['-NoProfile', '-Command', script]);
    } catch (_) {
      // Non-fatal  -  if shortcut creation fails, the app still runs fine.
    }
  }

  static Future<void> _ensureDesktopShortcutLinux() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final desktopPath = p.join(home, 'Desktop');
      final shortcutPath = p.join(desktopPath, 'vault_the_spire.desktop');
      if (await File(shortcutPath).exists()) return;
      // Only create if the Desktop directory actually exists.
      if (!await Directory(desktopPath).exists()) return;
      final exePath = Platform.resolvedExecutable;
      final content = '''[Desktop Entry]
Type=Application
Name=VaultTheSpire
Comment=Private Torrent and Messaging
Exec=$exePath
Terminal=false
Categories=Network;
''';
      await File(shortcutPath).writeAsString(content);
      // Mark as executable so the desktop environment treats it as a launcher.
      await Process.run('chmod', ['+x', shortcutPath]);
    } catch (_) {
      // Non-fatal.
    }
  }

  static Future<bool> _enableWindows() async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;
      final startupDir = p.join(
        appData,
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'Startup',
      );
      final exePath = Platform.resolvedExecutable;
      final linkPath = p.join(startupDir, 'VaultTheSpire.lnk');
      final script = '''
\$w = New-Object -ComObject WScript.Shell
\$s = \$w.CreateShortcut("$linkPath")
\$s.TargetPath = "$exePath"
\$s.WorkingDirectory = "${p.dirname(exePath)}"
\$s.Save()
''';
      await Process.run('powershell', ['-NoProfile', '-Command', script]);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _disableWindows() async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return false;
      final linkPath = p.join(
        appData,
        'Microsoft',
        'Windows',
        'Start Menu',
        'Programs',
        'Startup',
        'VaultTheSpire.lnk',
      );
      final file = File(linkPath);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _enableLinux() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      final autostartDir = p.join(home, '.config', 'autostart');
      await Directory(autostartDir).create(recursive: true);
      final desktopFile = p.join(autostartDir, 'vault_the_spire.desktop');
      final exePath = Platform.resolvedExecutable;
      final content = '''[Desktop Entry]
Type=Application
Name=VaultTheSpire
Exec=$exePath
X-GNOME-Autostart-enabled=true
''';
      await File(desktopFile).writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _disableLinux() async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return false;
      final desktopFile = p.join(
        home,
        '.config',
        'autostart',
        'vault_the_spire.desktop',
      );
      final file = File(desktopFile);
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
