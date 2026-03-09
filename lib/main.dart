import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite FFI for desktop platforms (Windows / Linux).
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // media_kit needs to perform some setup on supported platforms.  if the
  // call fails we capture the error message and hand it to the app so that the
  // UI can show something friendlier than a crash later on when a `Player`
  // instance is created.
  String? mediaKitError;
  if (!kIsWeb) {
    // Android is not supported by the current media_kit release; calling
    // ensureInitialized will throw and we prefer to silently continue with
    // audio‑only behaviour rather than presenting an error screen.  The
    // plugin itself checks `Platform.isAndroid` and will emit
    // "Unsupported platform: android".
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
    const windowOptions = WindowOptions(
      size: Size(1100, 750),
      minimumSize: Size(480, 600),
      center: true,
      title: 'Convert the Spire Reborn',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(MyApp(mediaKitInitError: mediaKitError));
}
