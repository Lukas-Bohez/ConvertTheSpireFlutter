import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform, Directory;
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';
import 'src/services/yt_dlp_update_controller.dart';
    return MaterialApp(
      title: 'ConvertTheSpire',
      theme: ThemeData(
        import 'dart:async';
        import 'dart:ffi' show DynamicLibrary, Int32, Pointer;
        import 'dart:io' show Platform, Directory;
        import 'dart:ui' as ui;

        import 'package:ffi/ffi.dart';
        import 'package:flutter/foundation.dart'
            show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
        import 'package:flutter/material.dart';
        import 'package:flutter_inappwebview/flutter_inappwebview.dart';
        import 'package:google_fonts/google_fonts.dart';
        import 'package:media_kit/media_kit.dart';
        import 'package:path_provider/path_provider.dart';
        import 'package:permission_handler/permission_handler.dart';
        import 'package:sqflite_common_ffi/sqflite_ffi.dart';
        import 'package:window_manager/window_manager.dart';

        import 'src/app.dart';
        import 'src/services/yt_dlp_update_controller.dart';

        Future<void> main() async {
          WidgetsFlutterBinding.ensureInitialized();

          // Local helper to request Android storage permission if needed.
          Future<void> _requestAndroidPermissions() async {
            if (kIsWeb) return;
            try {
              if (Platform.isAndroid) {
                try {
                  final p = Permission.storage;
                  final st = await p.status;
                  if (st.isDenied || st.isRestricted) await p.request();
                } catch (_) {}
              }
            } catch (e) {
              debugPrint('Android permission request failed: $e');
            }
          }

          // Global error handlers
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
            // ensure WebView2 user data folder is short (avoids long-path crashes)
            if (!kIsWeb && Platform.isWindows) {
              final local = Platform.environment['LOCALAPPDATA'] ?? '';
              final userData = Directory(r'$local\\ConvertTheSpireReborn\\WebView2');
              if (!userData.existsSync()) userData.createSync(recursive: true);
              // call Win32 SetEnvironmentVariableW via FFI
              try {
                final kernel32 = DynamicLibrary.open('kernel32.dll');
                final setEnv = kernel32.lookupFunction<
                    Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
                    int Function(Pointer<Utf16>, Pointer<Utf16>)>(
                  'SetEnvironmentVariableW',
                );
                final namePtr = 'WEBVIEW2_USER_DATA_FOLDER'.toNativeUtf16();
                final valuePtr = userData.path.toNativeUtf16();
                try {
                  setEnv(namePtr, valuePtr);
                } finally {
                  malloc.free(namePtr);
                  malloc.free(valuePtr);
                }
              } catch (e) {
                if (kDebugMode) debugPrint('SetEnvironmentVariable failed: $e');
              }
            }

            WebViewEnvironment? webViewEnvironment;
            // Create WebViewEnvironment on Windows so flutter_inappwebview can initialize.
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

            // Initialize sqflite FFI for desktop platforms (Windows / Linux).
            if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
              sqfliteFfiInit();
              databaseFactory = databaseFactoryFfi;
            }

            // media_kit initialization
            String? mediaKitError;
            if (!kIsWeb) {
              if (Platform.isAndroid) {
                if (kDebugMode) debugPrint('Skipping MediaKit initialization on Android (unsupported)');
              } else {
                try {
                  MediaKit.ensureInitialized(); // required by media_kit (synchronous)
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

            // Desktop window setup
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

            // Start the Flutter app
            runApp(MyApp(
              mediaKitInitError: mediaKitError,
              webViewEnvironment: webViewEnvironment,
            ));

            // Start background yt-dlp update checks while the app is running.
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
