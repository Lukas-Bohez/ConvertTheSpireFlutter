import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show VoidCallback, debugPrint, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Manages the system-tray icon and close-to-tray behaviour on desktop.
///
/// When [shouldMinimiseToTray] returns `true` the window is hidden instead
/// of destroyed, so background downloads and mining continue.
class TrayService with TrayListener, WindowListener {
  bool _initialised = false;
  bool Function() shouldMinimiseToTray;
  VoidCallback? onTrayShow;
  VoidCallback? onTrayQuit;

  TrayService({required this.shouldMinimiseToTray});

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (!isDesktop || _initialised) return;
    _initialised = true;

    await windowManager.ensureInitialized();
    await _restoreWindowGeometry();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await _setupTray();
  }

  Future<void> _setupTray() async {
    // Use the app icon for the tray.
    String iconPath;
    if (Platform.isWindows) {
      // tray_manager on Windows requires .ico format.
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final ico = p.join(exeDir, 'data', 'flutter_assets', 'assets',
          'icons', 'app_icon.ico');
      final png = p.join(exeDir, 'data', 'flutter_assets', 'assets',
          'icons', 'favicon-192x192.png');
      iconPath = File(ico).existsSync() ? ico : png;
    } else {
      iconPath = 'assets/icons/favicon-192x192.png';
    }

    try {
      await trayManager.setIcon(iconPath);
    } catch (e) {
      debugPrint('TrayService: setIcon failed ($iconPath): $e');
    }
    try {
      await trayManager.setToolTip('Convert the Spire Reborn');
    } catch (e) {
      debugPrint('TrayService: setToolTip failed: $e');
    }

    final menu = Menu(items: [
      MenuItem(key: 'show', label: 'Show'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]);
    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('TrayService: setContextMenu failed: $e');
    }
    trayManager.addListener(this);
  }

  // ── TrayListener ────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        break;
      case 'quit':
        onTrayQuit?.call();
        break;
    }
  }

  // ── WindowListener ──────────────────────────────────────────────────────

  @override
  void onWindowClose() {
    _saveWindowGeometry();
    if (shouldMinimiseToTray()) {
      debugPrint('TrayService: minimising to tray instead of closing');
      windowManager.hide();
    } else {
      onTrayQuit?.call();
    }
  }

  @override
  void onWindowResized() => _saveWindowGeometry();

  @override
  void onWindowMoved() => _saveWindowGeometry();

  // ── Window geometry persistence ─────────────────────────────────────────

  static const _kWindowX = 'window_x';
  static const _kWindowY = 'window_y';
  static const _kWindowW = 'window_w';
  static const _kWindowH = 'window_h';

  Future<void> _saveWindowGeometry() async {
    try {
      final bounds = await windowManager.getBounds();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kWindowX, bounds.left);
      await prefs.setDouble(_kWindowY, bounds.top);
      await prefs.setDouble(_kWindowW, bounds.width);
      await prefs.setDouble(_kWindowH, bounds.height);
    } catch (_) {}
  }

  Future<void> _restoreWindowGeometry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_kWindowX);
      final y = prefs.getDouble(_kWindowY);
      final w = prefs.getDouble(_kWindowW);
      final h = prefs.getDouble(_kWindowH);
      if (x != null && y != null && w != null && h != null && w > 100 && h > 100) {
        await windowManager.setBounds(
          null,
          position: Offset(x, y),
          size: Size(w, h),
        );
      }
    } catch (_) {}
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<void> _showWindow() async {
    onTrayShow?.call();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> destroy() async {
    if (!_initialised) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
