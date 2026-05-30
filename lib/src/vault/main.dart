import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:convert_the_spire_reborn/src/config/build_flags.dart';
import 'package:convert_the_spire_reborn/src/vault/db/sqlcipher_bootstrap.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/desktop_window.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/hotkeys.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/notifications_desktop.dart';
import 'package:convert_the_spire_reborn/src/vault/services/background_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/identity_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/service_locator.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/startup_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/theme_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_engine_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/tray_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/adaptive_ui_frame.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

// import './screens/home_screen.dart';
import 'router.dart';

Future<bool> _requestAndroidPermissions() async {
  var notificationGranted = true;
  if (!kIsWeb && Platform.isAndroid) {
    final perms = await [
      Permission.storage,
      Permission.photos,
      Permission.mediaLibrary,
      Permission.notification,
    ].request();
    notificationGranted = perms[Permission.notification]?.isGranted ?? false;
    if (kDebugMode) {
      for (final e in perms.entries) {
        debugPrint('Android permission ${e.key}: ${e.value}');
      }
    }
  }
  return notificationGranted;
}

Future<void> _initializeMetadataCache() async {
  try {
    // Set up persistent metadata cache directory for torrent metadata downloads
    if (!kIsWeb) {
      Directory? appCacheDir;
      if (Platform.isAndroid || Platform.isIOS) {
        appCacheDir = await getApplicationCacheDirectory();
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        appCacheDir = await getApplicationSupportDirectory();
      }

      if (appCacheDir != null) {
        final metadataCacheDir =
            Directory('${appCacheDir.path}/torrent_metadata_cache');
        if (!await metadataCacheDir.exists()) {
          await metadataCacheDir.create(recursive: true);
        }
        dt.MetadataDownloader.setCacheDirectory(metadataCacheDir.path);
        debugPrint('Metadata cache initialized: ${metadataCacheDir.path}');
      }
    }
  } catch (e, st) {
    debugPrint('Failed to initialize metadata cache: $e');
    debugPrint(st.toString());
  }
}

Future<void> main() async {
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT PLATFORM ERROR: $error');
    debugPrint(stack.toString());
    return true; // handled
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final errorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB00020),
      brightness: Brightness.light,
    );
    return Material(
      color: errorScheme.errorContainer,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Flutter Error:\n\n'
              '${details.exceptionAsString()}\n\n'
              '${details.stack?.toString().split('\n').take(8).join('\n') ?? ''}',
              style:
                  TextStyle(color: errorScheme.onErrorContainer, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  };
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (!kIsWeb && Platform.isAndroid) {
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
        );
      }
      await setupServiceLocator();
      await _initializeMetadataCache();
      await initSqlCipherOnAndroid();
      await _requestAndroidPermissions();

      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      await ThemeService.instance.load();
      await SettingsService.instance.load();

      if (!kIsWeb &&
          Platform.isAndroid &&
          SettingsService.instance.downloadDestination.isEmpty) {
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            final downloadsDir = Directory('${externalDir.path}/VaultTheSpire');
            if (!await downloadsDir.exists()) {
              await downloadsDir.create(recursive: true);
            }
            await SettingsService.instance.setDownloadDestination(
              downloadsDir.path,
            );
            debugPrint('Android default download dir: ${downloadsDir.path}');
          }
        } catch (e) {
          debugPrint('Could not set Android default download dir: $e');
        }
      }

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await setupDesktopWindow(
          installShutdownListener: !SettingsService.instance.useSystemTray,
        );
      }

      // Render first frame before long-running startup work.
      runApp(const MainApp());

      unawaited(
        Future(() async {
          try {
            if (!kIsWeb && Platform.isAndroid) {
              debugPrint(
                'Android background service startup is disabled to keep the app stable while the foreground notification path is fixed.',
              );
            } else if (!kIsWeb && Platform.isIOS) {
              await initBackgroundService();
            }

            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              await StartupService.ensureDesktopShortcut();

              if (SettingsService.instance.launchOnStartup) {
                await StartupService.enable();
              } else {
                await StartupService.disable();
              }

              if (SettingsService.instance.useSystemTray) {
                await TrayService(
                  shouldMinimiseToTray: () =>
                      SettingsService.instance.minimizeToTrayOnClose,
                  onTrayShow: () async {
                    await windowManager.show();
                  },
                  onTrayQuit: () async {
                    await TorrentEngineService.instance.stopAll();
                    await Future.delayed(const Duration(milliseconds: 200));
                    await windowManager.destroy();
                    exit(0);
                  },
                ).init();
              }

              await setupHotkeys();
              DesktopNotificationPoller.instance.start();
            }

            await IdentityService.instance.initialize();

            await TorrentService.instance.resumeActiveTorrents();
          } catch (error, stack) {
            debugPrint('DEFERRED STARTUP ERROR: $error');
            debugPrint(stack.toString());
          }
        }),
      );
    },
    (error, stack) {
      // Suppress NAT-PMP UDP discovery failures on Android.
      if (!kIsWeb &&
          Platform.isAndroid &&
          error is SocketException &&
          error.osError?.errorCode == 1 &&
          (error.address?.address == '0.0.0.0' ||
              error.address?.address == null)) {
        return;
      }
      debugPrint('UNCAUGHT ZONED ERROR: $error');
      debugPrint(stack.toString());
    },
  );
}

// NOTE: Flutter on Windows may produce ui::AXTree warnings in debug mode
// (AccessibilityBridge internal logging). These are harmless engine diagnostics
// and are suppressed/optimized out in --release mode. No functional action is
// needed in production; this is a known desktop engine issue.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final themeService = ThemeService.instance;

  static const Color _brand = Color(0xFF0C8F66);

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        indicatorColor: scheme.secondaryContainer,
        backgroundColor: scheme.surface,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    themeService.addListener(_onThemeChanged);
    _updateAndroidSystemUiOverlay();
  }

  @override
  void dispose() {
    themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    _updateAndroidSystemUiOverlay();
    setState(() {});
  }

  void _updateAndroidSystemUiOverlay() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final isDark = themeService.themeMode == ThemeMode.dark ||
        (themeService.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: getAppTitle(),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeService.themeMode,
      builder: (context, child) {
        // TODO(next): add route-level overscan overrides for immersive pages.
        return AdaptiveUiFrame(child: child ?? const SizedBox.shrink());
      },
      routerConfig: appRouter,
    );
  }
}
