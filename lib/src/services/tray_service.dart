import 'dart:io';

import 'package:flutter/foundation.dart' show VoidCallback, debugPrint, kIsWeb;
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
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await _setupTray();
  }

  Future<void> _setupTray() async {
    // Use the app icon for the tray. On Windows .ico is ideal; we fall back
    // to the PNG icon bundled in the assets.
    String iconPath;
    if (Platform.isWindows) {
      // The runner embeds an ICO as the exe resource; tray_manager on
      // Windows can use the exe path directly to pick up the embedded icon.
      iconPath = Platform.resolvedExecutable;
    } else {
      iconPath = 'assets/icons/favicon-192x192.png';
    }

    await trayManager.setIcon(iconPath);
    await trayManager.setToolTip('Convert the Spire Reborn');

    final menu = Menu(items: [
      MenuItem(key: 'show', label: 'Show'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]);
    await trayManager.setContextMenu(menu);
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
    if (shouldMinimiseToTray()) {
      debugPrint('TrayService: minimising to tray instead of closing');
      windowManager.hide();
    } else {
      onTrayQuit?.call();
    }
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
