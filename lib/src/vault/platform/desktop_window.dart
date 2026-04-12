import 'package:flutter/material.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:window_manager/window_manager.dart';

class _CleanShutdownListener extends WindowListener {
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    await TorrentEngineService.instance.stopAll();
    await Future.delayed(const Duration(milliseconds: 400));
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }
}

Future<void> setupDesktopWindow({required bool installShutdownListener}) async {
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1100, 700),
    minimumSize: Size(800, 600),
    center: true,
    title: 'Vault The Spire',
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
    try {
      // Try to set the native window icon from the app icon asset (Windows/Linux)
      // This requires the window_manager plugin to support setIcon.
      await windowManager.setIcon('assets/icons/app_icon.ico');
    } catch (e) {
      // Not all platforms/plugins support runtime icon changes.
    }

    if (installShutdownListener) {
      windowManager.addListener(_CleanShutdownListener());
      await windowManager.setPreventClose(true);
    }
  });
}

Future<void> toggleDesktopFullScreen() async {
  final isFull = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!isFull);
}
