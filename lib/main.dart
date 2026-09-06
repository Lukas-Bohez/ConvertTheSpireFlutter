import 'dart:async';
import 'dart:io' show Directory, File, FileMode, Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/config/build_flags.dart';
import 'src/config/flavor.dart';
import 'src/config/full_mode_access.dart';
import 'src/services/ad_service.dart';
import 'src/services/purchase_service.dart';
import 'src/services/review_service.dart';
import 'src/services/session_log_service.dart';
import 'src/vault/platform/crash_dump.dart';

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
  File? startupErrorLogFile;

  await runZonedGuarded(() async {
    // Ensure bindings are initialized in the same zone that runs runApp.
    // This avoids `Zone mismatch` errors from Flutter.
    WidgetsFlutterBinding.ensureInitialized();

    // Startup/shutdown breadcrumbs: written to session_log_*.log on close
    // or on error, to diagnose slow starts on low-end hardware.
    SessionLogService.instance.start();
    SessionLogService.instance.mark('widgets_binding_ready');

    // Keep the global image cache conservative so TV devices don't retain too
    // many full-resolution thumbnails at once.
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20;

    // Initialize the runtime flavor detection so kPlayStoreBuild is valid.
    await initAppFlavor();
    SessionLogService.instance.mark('initAppFlavor_done');
    // Propagate into build_flags runtime flag. Only treat the runtime-detected
    // Play flavor as authoritative on Android; otherwise desktop app names
    // that contain the branding string should not enable Play-store-only
    // behaviors. Allow an explicit dart-define to override everything.
    setPlayStoreBuildFlag(kIsPlayStoreBuildDefine ||
        (!kIsWeb && Platform.isAndroid && isPlayFlavor));

    // Track launches for review prompt heuristics.
    await ReviewService.trackLaunch();
    SessionLogService.instance.mark('trackLaunch_done');

    startupErrorLogFile = await _prepareStartupErrorLogFile();

    // Request storage/media permissions on Android (if needed).
    Future<void> requestAndroidPermissions() async {
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
      unawaited(SessionLogService.instance.flush('flutter_error'));
      unawaited(captureCrashDump(
        'flutter_error',
        startupErrorLogFile?.path ?? '',
      ));
    };
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      _logStartupError(startupErrorLogFile, 'PLATFORM ERROR', error, stack);
      unawaited(captureCrashDump(
        'platform_error',
        startupErrorLogFile?.path ?? '',
      ));
      return true;
    };

    await requestAndroidPermissions();
    SessionLogService.instance.mark('permissions_done');

    // Initialize purchase service only on Play Store Android builds.
    // The `in_app_purchase` plugin is not available on desktop builds and
    // calling it there can throw a LateInitializationError. Guard it so
    // desktop builds (Windows/Linux/macOS) skip billing initialization.
    if (!kIsWeb && Platform.isAndroid && kPlayStoreBuild) {
      await PurchaseService.instance.initialize();
    }

    // Initialize AdService to load cached monetization state
    await AdService.instance.initialize();
    SessionLogService.instance.mark('adService_init_done');

    // Handle UMP consent for EU/EEA users and initialize the Google Mobile Ads SDK.
    // This must be called after AdService.instance.initialize() but should replace
    // any raw MobileAds.instance.initialize() calls.
    if (!kIsWeb && Platform.isAndroid && kPlayStoreBuild) {
      if (kDebugMode) {
        debugPrint(
            'main: starting UMP consent flow via AdService.initAdsWithConsent()');
      }
      await AdService.instance.initAdsWithConsent();
      if (kDebugMode) {
        debugPrint('main: AdService.initAdsWithConsent() completed');
      }
    }

    PurchaseService.instance.addListener(() {
      if (PurchaseService.instance.isAdFree) {
        AdService.instance.disposeAllAds();
      }
    });

    // Ensure WebView2 user data folder is short (avoids long-path crashes).
    // Note: setting the environment variable via Win32 APIs was removed for
    // compilation stability in this environment.
    if (!kIsWeb && Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'] ?? '';
      final userData = Directory('$local\\ConvertTheSpireReborn\\WebView2');
      if (!userData.existsSync()) userData.createSync(recursive: true);
    }

    // NOTE: the old flutter_inappwebview `WebViewEnvironment.create()` call
    // was removed here - it eagerly invoked the flutter_inappwebview Windows
    // plugin at startup, which crashed with an illegal instruction on CPUs
    // without BMI2. The Windows browser now uses `webview_windows`
    // (WebView2) via BrowserWebviewFactory, which initializes its own
    // environment lazily with the same short user-data path.

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String? mediaKitError;
    if (!kIsWeb) {
      try {
        MediaKit.ensureInitialized();
        SessionLogService.instance.mark('mediaKit_done');
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
        size: const ui.Size(1100, 750),
        minimumSize: const ui.Size(480, 600),
        center: true,
        title: getAppTitle(),
        backgroundColor: const Color(0xFF17110B),
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      try {
        await windowManager.setPreventClose(true);
      } catch (_) {}
      SessionLogService.instance.mark('window_ready');
    }

    await FullModeAccess.instance.load();
    SessionLogService.instance.mark('fullModeAccess_done');

    SessionLogService.instance.mark('runApp');
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: PurchaseService.instance,
          ),
        ],
        child: MyApp(
          mediaKitInitError: mediaKitError,
        ),
      ),
    );
  }, (error, stack) {
    _logStartupError(startupErrorLogFile, 'ZONE ERROR', error, stack);
    unawaited(SessionLogService.instance.flush('zone_error'));
    unawaited(captureCrashDump(
      'zone_error',
      startupErrorLogFile?.path ?? '',
    ));
  });
}
