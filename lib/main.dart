import 'dart:async';
import 'dart:io' show Directory, Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/services/yt_dlp_update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request storage permission on Android (if needed).
  Future<void> _requestAndroidPermissions() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    try {
      // Android 13+ requires granular media permissions (audio/video/photos).
      // Request both storage and media permissions to cover older and newer OS versions.
      final statuses = await [
        Permission.storage,
        Permission.audio,
        Permission.videos,
      ].request();

      if (kDebugMode) {
        for (final entry in statuses.entries) {
          debugPrint('Android permission ${entry.key}: ${entry.value}');
        }
      }
    } catch (e) {
      debugPrint('Android permission request failed: $e');
    }
  }

  // Global error handlers.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      debugPrint('UNCAUGHT FLUTTER ERROR: ${details.exception}');
      debugPrint(details.stack?.toString() ?? 'no stack');
    }
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT PLATFORM ERROR: $error');
    debugPrint(stack.toString());
    return true;
  };

  await _requestAndroidPermissions();

  runZonedGuarded(() async {
    // Ensure WebView2 user data folder is short (avoids long-path crashes).
    // Note: setting the environment variable via Win32 APIs was removed for
    // compilation stability in this environment.
    if (!kIsWeb && Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      final userData = Directory('$local\\ConvertTheSpireReborn\\WebView2');
      if (!userData.existsSync()) userData.createSync(recursive: true);
    }

    WebViewEnvironment? webViewEnvironment;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final available = await WebViewEnvironment.getAvailableVersion();
        if (available != null) {
          final appSupport = await getApplicationSupportDirectory();
          final webViewDataDir = '${appSupport.path}\\WebView2UserData';
          webViewEnvironment = await WebViewEnvironment.create(
            settings: WebViewEnvironmentSettings(userDataFolder: webViewDataDir),
          );
          if (kDebugMode) debugPrint('[WebView] created environment at $webViewDataDir');
        } else {
          if (kDebugMode) debugPrint('[WebView] WebView2 runtime not available');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[WebView] environment init failed: $e');
      }
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String? mediaKitError;
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        if (kDebugMode) debugPrint('Skipping MediaKit initialization on Android (unsupported)');
      } else {
        try {
          MediaKit.ensureInitialized();
        } catch (e, st) {
          final msg = '$e';
          if (msg.contains('Unsupported platform')) {
            if (kDebugMode) debugPrint('MediaKit not supported: $msg');
          } else {
            mediaKitError = msg;
            if (kDebugMode) {
              debugPrint('MediaKit initialization failed: $e');
              debugPrint('$st');
            }
          }
        }
      }
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      final windowOptions = WindowOptions(
        size: ui.Size(1100, 750),
        minimumSize: ui.Size(480, 600),
        center: true,
        title: 'Convert the Spire Reborn',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      try {
        await windowManager.setPreventClose(true);
      } catch (_) {}
    }

    runApp(MyApp(
      mediaKitInitError: mediaKitError,
      webViewEnvironment: webViewEnvironment,
    ));

    try {
      YtDlpUpdateController.start();
    } catch (e) {
      debugPrint('yt-dlp updater controller failed to start: $e');
    }
  }, (error, stack) {
    debugPrint('UNCAUGHT ZONED ERROR: $error');
    debugPrint(stack.toString());
  });
}
