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

    if (installShutdownListener) {
      windowManager.addListener(_CleanShutdownListener());
      await windowManager.setPreventClose(true);
    }
  });
}

Future<void> toggleDesktopFullScreen() async {
  if (await windowManager.isFullScreen()) {
    try {
      await windowManager.setFullScreen(false);
    } finally {
      try {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
          windowButtonVisibility: true,
        );
      } catch (_) {}
      try {
        await windowManager.show();
      } catch (_) {}
      try {
        await windowManager.focus();
      } catch (_) {}
    }
    return;
  }

  try {
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
  } catch (_) {}
  final isFull = await windowManager.isFullScreen();
  if (isFull) return;
  try {
    await windowManager.setFullScreen(true);
  } catch (_) {
    try {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.normal,
        windowButtonVisibility: true,
      );
    } catch (_) {}
    rethrow;
  }
  try {
    await windowManager.show();
  } catch (_) {}
  try {
    await windowManager.focus();
  } catch (_) {}
}
