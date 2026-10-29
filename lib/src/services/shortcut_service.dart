import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import 'platform_dirs.dart';

/// Puts a shortcut to the app on the desktop, and on Linux in the app menu.
///
/// The desktop shortcut is made on the first start; one the user deletes
/// stays deleted. A shortcut that no longer starts the app is put right on
/// every start: the Microsoft Store version used to point its shortcut at
/// its exe inside WindowsApps, which Windows does not let anyone start
/// ("you do not have permission"), and whose folder changes with every
/// update.
class ShortcutService {
  static const _madeKey = 'desktop_shortcut_made';

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Ensure a desktop shortcut exists.  Does nothing on non-desktop platforms.
  static Future<void> ensureDesktopShortcut() async {
    // A development build would put its own shortcut on the desktop.
    if (!_isDesktop || kDebugMode) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final create = prefs.getBool(_madeKey) != true;
      final ok = Platform.isWindows
          ? await _ensureWindowsShortcut(create: create)
          : await _ensureLinuxEntries(create: create);
      if (ok && create) await prefs.setBool(_madeKey, true);
    } catch (e) {
      debugPrint('ShortcutService: failed to create desktop shortcut: $e');
    }
  }

  // -- Windows (.lnk via PowerShell) ------------------------------------─

  static Future<bool> _ensureWindowsShortcut({required bool create}) async {
    final script = windowsScript(
      name: getAppTitle(),
      exePath: Platform.resolvedExecutable,
      appId: packagedAppId(),
      create: create,
    );
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
    );

    if (result.exitCode == 0) {
      debugPrint('ShortcutService: desktop shortcut OK');
      return true;
    }
    debugPrint('ShortcutService: PowerShell shortcut failed: '
        '${result.stderr}');
    return false;
  }

  /// The app's id in Windows when it runs from its Microsoft Store package,
  /// such as `OrokaConner.ConvertTheSpireReborn_zbvcx9hwcv0q2!convertthespirereborn`;
  /// null for every other build.
  static String? packagedAppId() {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final getId = DynamicLibrary.open('kernel32.dll').lookupFunction<
          Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
          int Function(Pointer<Uint32>,
              Pointer<Utf16>)>('GetCurrentApplicationUserModelId');
      const capacity = 256;
      final length = calloc<Uint32>()..value = capacity;
      final buffer = calloc<Uint16>(capacity).cast<Utf16>();
      try {
        // Anything but ERROR_SUCCESS: the process has no package.
        if (getId(length, buffer) != 0) return null;
        final id = buffer.toDartString();
        return id.contains('!') ? id : null;
      } finally {
        calloc.free(length);
        calloc.free(buffer);
      }
    } catch (_) {
      return null;
    }
  }

  /// The PowerShell that puts the shortcut on the desktop. It exits with 0
  /// when the desktop has a working shortcut, or none because [create] is
  /// false and the user deleted it.
  ///
  /// With [appId] (the Microsoft Store version) the shortcut opens the app
  /// through Windows, `shell:AppsFolder\<appId>`, as one dragged from the
  /// Start menu does: it shows the app's icon and keeps working after
  /// updates. Other builds point at their exe.
  ///
  /// A shortcut already there stays, unless it points at an exe inside
  /// WindowsApps or at a file that is gone. [desktop] is for tests.
  @visibleForTesting
  static String windowsScript({
    required String name,
    required String exePath,
    String? appId,
    required bool create,
    String? desktop,
  }) {
    // All values go in as single-quoted PowerShell strings.
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final target = appId != null ? 'shell:AppsFolder\\$appId' : exePath;
    return [
      if (desktop != null)
        '\$desktop = ${quote(desktop)}'
      else
        r"$desktop = [Environment]::GetFolderPath('Desktop')",
      r'if (-not $desktop) { exit 1 }',
      '\$lnk = Join-Path \$desktop ${quote('$name.lnk')}',
      r'$ws = New-Object -ComObject WScript.Shell',
      r'if (Test-Path -LiteralPath $lnk) {',
      // No file path: it opens an app from the Apps folder, as the Store
      // version's does.
      r'  $old = $ws.CreateShortcut($lnk).TargetPath',
      r'  if (-not $old) { exit 0 }',
      r"  if (($old -notlike '*\WindowsApps\*') -and (Test-Path -LiteralPath $old)) { exit 0 }",
      r'  Remove-Item -LiteralPath $lnk -Force',
      if (!create) r'} else { exit 0 }' else '}',
      r'$s = $ws.CreateShortcut($lnk)',
      '\$s.TargetPath = ${quote(target)}',
      if (appId == null)
        '\$s.WorkingDirectory = ${quote(p.windows.dirname(exePath))}',
      '\$s.Description = ${quote(name)}',
      r'$s.Save()',
      '',
    ].join('\n');
  }

  // -- Linux (.desktop files) -------------------------------------------─

  /// The file name of the app's menu entry. It matches the app's id (the
  /// runner's APPLICATION_ID), which Wayland desktops use to find the
  /// entry, and so the icon, of a window.
  static const _entryName = 'com.example.convert_the_spire_reborn.desktop';

  /// The name of the desktop shortcut that older versions made.
  static const _oldDesktopName = 'vault-spire.desktop';

  /// The menu entry is written on every start, so it follows the app when
  /// it moves (a new AppImage); the desktop shortcut as on Windows.
  static Future<bool> _ensureLinuxEntries({required bool create}) async {
    final env = Platform.environment;
    final home = env['HOME'];
    if (home == null || home.isEmpty) return false;

    // An AppImage runs from a temporary folder: start the AppImage itself.
    final exec = env['APPIMAGE'] ?? Platform.resolvedExecutable;
    final icon = await _linuxIcon();
    final entry = linuxDesktopEntry(
      name: getAppTitle(),
      exec: exec,
      icon: icon,
    );

    final dataHome = env['XDG_DATA_HOME']?.isNotEmpty == true
        ? env['XDG_DATA_HOME']!
        : p.join(home, '.local', 'share');
    final applications = Directory(p.join(dataHome, 'applications'));
    await applications.create(recursive: true);
    final menuEntry = File(p.join(applications.path, _entryName));
    if (await _writeIfChanged(menuEntry, entry)) {
      // So "Open with" lists the app at once; not every system has it.
      try {
        await Process.run('update-desktop-database', [applications.path]);
      } catch (_) {}
    }

    final desktop = await _linuxDesktopDir(home);
    if (desktop == null) return true;
    final old = File(p.join(desktop, _oldDesktopName));
    if (await old.exists()) {
      try {
        await old.delete();
      } catch (_) {}
    }
    final shortcut = File(p.join(desktop, 'convert-the-spire-reborn.desktop'));
    if (!create && !await shortcut.exists()) return true;
    if (await _writeIfChanged(shortcut, entry)) {
      await Process.run('chmod', ['+x', shortcut.path]);
      // GNOME starts a desktop launcher only once it is marked trusted.
      try {
        await Process.run(
            'gio', ['set', shortcut.path, 'metadata::trusted', 'true']);
      } catch (_) {}
    }
    debugPrint('ShortcutService: Linux menu entry and desktop shortcut OK');
    return true;
  }

  /// The contents of the app's .desktop file.
  @visibleForTesting
  static String linuxDesktopEntry({
    required String name,
    required String exec,
    required String? icon,
  }) {
    // Quoted as the Desktop Entry spec asks, for paths with spaces.
    final quoted = exec
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('`', r'\`')
        .replaceAll(r'$', r'\$');
    return [
      '[Desktop Entry]',
      'Type=Application',
      'Name=$name',
      'GenericName=Media player and downloader',
      'Comment=Download, convert, play and cast music and videos',
      // %U: what the app is asked to open (files, magnet links), which the
      // runner passes to OpenRequestService.
      'Exec="${quoted.replaceAll('%', '%%')}" %U',
      if (icon != null) 'Icon=$icon',
      'Terminal=false',
      'Categories=AudioVideo;Player;',
      'MimeType=${linuxMimeTypes.join(';')};',
      'StartupWMClass=com.example.convert_the_spire_reborn',
      'StartupNotify=true',
      '',
    ].join('\n');
  }

  /// What the app offers to open on Linux: the same as on the other
  /// platforms (OpenRequestService.mediaExtensions, torrents and magnet
  /// links).
  @visibleForTesting
  static const linuxMimeTypes = [
    'x-scheme-handler/magnet',
    'application/x-bittorrent',
    'audio/mpeg',
    'audio/mp4',
    'audio/x-m4a',
    'audio/flac',
    'audio/x-flac',
    'audio/wav',
    'audio/x-wav',
    'audio/ogg',
    'audio/x-vorbis+ogg',
    'audio/opus',
    'audio/x-opus+ogg',
    'audio/aac',
    'audio/x-ms-wma',
    'video/mp4',
    'video/x-matroska',
    'video/x-msvideo',
    'video/webm',
    'video/quicktime',
    'video/x-ms-wmv',
    'video/x-flv',
    'video/x-m4v',
  ];

  /// The app's icon, copied out of the app: an AppImage's own files are
  /// gone once it closes.
  static Future<String?> _linuxIcon() async {
    try {
      final support = await PlatformDirs.getAppSupportDir();
      if (support == null) return null;
      final icon = File(p.join(support.path, 'app_icon.png'));
      final data = await rootBundle.load('assets/icons/app_logo_384.png');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (!await icon.exists() || await icon.length() != bytes.length) {
        await icon.parent.create(recursive: true);
        await icon.writeAsBytes(bytes, flush: true);
      }
      return icon.path;
    } catch (e) {
      debugPrint('ShortcutService: no icon for the menu entry: $e');
      return null;
    }
  }

  /// The user's desktop folder, or null when there is none (a desktop that
  /// shows no icons has none, and one is not made for it).
  static Future<String?> _linuxDesktopDir(String home) async {
    String? dir;
    try {
      final result = await Process.run('xdg-user-dir', ['DESKTOP']);
      if (result.exitCode == 0) dir = result.stdout.toString().trim();
    } catch (_) {}
    dir ??= p.join(home, 'Desktop');
    // xdg-user-dir answers the home folder when no desktop is set.
    if (dir.isEmpty || p.equals(dir, home)) return null;
    return await Directory(dir).exists() ? dir : null;
  }

  static Future<bool> _writeIfChanged(File file, String content) async {
    try {
      if (await file.exists() && await file.readAsString() == content) {
        return false;
      }
    } catch (_) {}
    await file.writeAsString(content, flush: true);
    return true;
  }
}
