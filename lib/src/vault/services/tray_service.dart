import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:convert_the_spire_reborn/src/vault/constants.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';

class TrayService with TrayListener, WindowListener {
  static bool enabled = false;
  static bool shouldMinimiseToTrayOnClose = false;

  bool _initialised = false;
  final bool Function() shouldMinimiseToTray;
  final FutureOr<void> Function()? onTrayShow;
  final Future<void> Function()? onTrayQuit;

  TrayService({
    required this.shouldMinimiseToTray,
    this.onTrayShow,
    this.onTrayQuit,
  });

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (!isDesktop || _initialised) return;
    _initialised = true;
    enabled = true;
    shouldMinimiseToTrayOnClose = shouldMinimiseToTray();

    await windowManager.ensureInitialized();
    await _restoreWindowGeometry();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await _setupTray();
  }

  Future<void> _setupTray() async {
    String iconPath;
    if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final ico = p.join(
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'icons',
        p.basename(kAppIconIco),
      );
      final png = p.join(
        exeDir,
        'data',
        'flutter_assets',
        'assets',
        'icons',
        p.basename(kAppFavicon192),
      );
      iconPath = File(ico).existsSync() ? ico : png;
    } else {
      iconPath = kAppFavicon192;
    }

    try {
      await trayManager.setIcon(iconPath);
    } catch (e) {
      debugPrint('TrayService: setIcon failed ($iconPath): $e');
    }

    try {
      await trayManager.setToolTip('Vault The Spire');
    } catch (e) {
      debugPrint('TrayService: setToolTip failed: $e');
    }

    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: 'Show Vault'),
        MenuItem(key: 'pause_all', label: 'Pause All Torrents'),
        MenuItem(key: 'resume_all', label: 'Resume All Torrents'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Exit'),
      ],
    );

    try {
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('TrayService: setContextMenu failed: $e');
    }

    trayManager.addListener(this);
  }

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        break;
      case 'pause_all':
        TorrentEngineService.instance.pauseAll();
        break;
      case 'resume_all':
        TorrentEngineService.instance.resumeAll();
        break;
      case 'quit':
        unawaited(onTrayQuit?.call() ?? Future<void>.value());
        break;
    }
  }

  @override
  void onWindowClose() {
    _saveWindowGeometry();
    if (shouldMinimiseToTray()) {
      debugPrint('TrayService: minimizing to tray on close');
      windowManager.hide();
    } else {
      unawaited(onTrayQuit?.call() ?? Future<void>.value());
    }
  }

  @override
  void onWindowResized() => _scheduleGeometrySave();

  @override
  void onWindowMoved() => _scheduleGeometrySave();

  @override
  void onWindowFocus() {
    _restartPollingDebounced();
  }

  static const _kWindowX = 'window_x';
  static const _kWindowY = 'window_y';
  static const _kWindowW = 'window_w';
  static const _kWindowH = 'window_h';
  Timer? _geometryDebounce;
  DateTime _lastPollingRestart = DateTime.fromMillisecondsSinceEpoch(0);

  void _restartPollingDebounced() {
    final now = DateTime.now();
    if (now.difference(_lastPollingRestart).inSeconds < 10) {
      return;
    }
    _lastPollingRestart = now;
    TorrentEngineService.instance.restartAllPolling();
  }

  Future<void> _saveWindowGeometry() async {
    try {
      final bounds = await windowManager.getBounds();
      await SettingsService.instance.setWindowGeometry(
        bounds.left,
        bounds.top,
        bounds.width,
        bounds.height,
      );
    } catch (_) {}
  }

  void _scheduleGeometrySave() {
    _geometryDebounce?.cancel();
    _geometryDebounce = Timer(
      const Duration(milliseconds: 500),
      _saveWindowGeometry,
    );
  }

  Future<void> _restoreWindowGeometry() async {
    try {
      final x = SettingsService.instance.windowX;
      final y = SettingsService.instance.windowY;
      final w = SettingsService.instance.windowW;
      final h = SettingsService.instance.windowH;
      if (w <= 0 || h <= 0) return;
      if (w < 100 || h < 100) return;

      const minVisibleX = -200.0;
      const minVisibleY = 0.0;
      const maxSafe = 99999.0;
      final safeX = x.clamp(minVisibleX, maxSafe);
      final safeY = y.clamp(minVisibleY, maxSafe);

      await windowManager.setBounds(
        null,
        position: Offset(safeX, safeY),
        size: Size(w, h),
      );
    } catch (_) {}
  }

  Future<void> _showWindow() async {
    final show = onTrayShow?.call();
    if (show is Future) {
      await show;
    }
    await windowManager.show();
    await windowManager.focus();
    _restartPollingDebounced();
  }

  Future<void> destroy() async {
    if (!_initialised) return;
    enabled = false;
    shouldMinimiseToTrayOnClose = false;

    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _geometryDebounce?.cancel();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
