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
    backgroundColor: Color(0xFF17110B),
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();

    if (installShutdownListener) {
      windowManager.addListener(_CleanShutdownListener());
      await windowManager.setPreventClose(true);
    }
  });
}

Future<void> toggleDesktopFullScreen() async {
  if (await windowManager.isFullScreen()) {
    await windowManager.setFullScreen(false);
    await windowManager.show();
    await windowManager.focus();
    return;
  }

  await windowManager.setFullScreen(true);
  await windowManager.show();
  await windowManager.focus();
}
