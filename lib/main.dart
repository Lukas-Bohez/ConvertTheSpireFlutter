import 'dart:async';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/config/build_flags.dart';
import 'src/config/full_mode_access.dart';

import 'src/app.dart';
import 'src/services/yt_dlp_update_controller.dart';

Future<File?> _prepareStartupErrorLogFile() async {
  try {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return File(
      '${documentsDirectory.path}${Platform.pathSeparator}startup_errors.log',
    );
  } catch (e) {
    debugPrint('Failed to prepare startup error log file: $e');
    return null;
  }
}

void _logStartupError(
  File? logFile,
  String label,
  Object error,
  StackTrace stack,
) {
  final timestamp = DateTime.now().toIso8601String();
  final entry = '[$timestamp] $label:\n$error\n$stack\n\n';
  debugPrint(entry);
  if (logFile == null) return;
  unawaited(
    () async {
      try {
        await logFile.writeAsString(entry, mode: FileMode.append, flush: true);
      } catch (writeError) {
        debugPrint('Failed to write startup error log entry: $writeError');
      }
    }(),
  );
}

Future<void> main() async {
  // Ensure bindings are initialized in the same zone that runs runApp.
  // This avoids `Zone mismatch` errors from Flutter.
  WidgetsFlutterBinding.ensureInitialized();
  final startupErrorLogFile = await _prepareStartupErrorLogFile();

  await runZonedGuarded(() async {
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
      _logStartupError(
        startupErrorLogFile,
        'FLUTTER ERROR',
        details.exceptionAsString(),
        details.stack ?? StackTrace.current,
      );
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      _logStartupError(startupErrorLogFile, 'PLATFORM ERROR', error, stack);
      return true;
    };

    await _requestAndroidPermissions();

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
            settings:
                WebViewEnvironmentSettings(userDataFolder: webViewDataDir),
          );
          if (kDebugMode)
            debugPrint('[WebView] created environment at $webViewDataDir');
        } else {
          if (kDebugMode)
            debugPrint('[WebView] WebView2 runtime not available');
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
      try {
        MediaKit.ensureInitialized();
      } catch (e, st) {
        final msg = '$e';
        if (msg.contains('Unsupported platform')) {
          if (kDebugMode) debugPrint('MediaKit not supported: $msg');
        } else {
          mediaKitError = msg;
          _logStartupError(startupErrorLogFile, 'MEDIA KIT ERROR', e, st);
          if (kDebugMode) {
            debugPrint('MediaKit initialization failed: $e');
            debugPrint('$st');
          }
        }
      }
    }

    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      final windowOptions = WindowOptions(
        size: ui.Size(1100, 750),
        minimumSize: ui.Size(480, 600),
        center: true,
        title: getAppTitle(),
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      try {
        await windowManager.setPreventClose(true);
      } catch (_) {}
    }

    await FullModeAccess.instance.load();

    // Initialize AdMob
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await MobileAds.instance.initialize();
        if (kDebugMode) debugPrint('MobileAds initialized');
      } catch (e) {
        _logStartupError(
          startupErrorLogFile,
          'ADMOB INIT ERROR',
          e,
          StackTrace.current,
        );
      }
    }

    runZonedGuarded(
      () {
        runApp(MyApp(
          mediaKitInitError: mediaKitError,
          webViewEnvironment: webViewEnvironment,
        ));
      },
      (error, stack) {
        _logStartupError(startupErrorLogFile, 'ZONE ERROR', error, stack);
      },
    );

    try {
      YtDlpUpdateController.start();
    } catch (e) {
      _logStartupError(
        startupErrorLogFile,
        'YT-DLP STARTUP ERROR',
        e,
        StackTrace.current,
      );
    }
  }, (error, stack) {
    _logStartupError(startupErrorLogFile, 'ZONE ERROR', error, stack);
  });
}
