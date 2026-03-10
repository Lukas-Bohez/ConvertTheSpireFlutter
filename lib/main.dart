import 'package:flutter/material.dart';
import 'dart:ui' show Size;
import 'dart:ffi';
import 'dart:io' show Platform, Directory;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ensure WebView2 user data folder is short (avoids long-path crashes)
  if (!kIsWeb && Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    final userData = Directory('$local\\ConvertTheSpireReborn\\WebView2');
    if (!userData.existsSync()) userData.createSync(recursive: true);
    // call Win32 SetEnvironmentVariableW via FFI
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setEnv = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)>('SetEnvironmentVariableW');
    final namePtr = 'WEBVIEW2_USER_DATA_FOLDER'.toNativeUtf16();
    final valuePtr = userData.path.toNativeUtf16();
    setEnv(namePtr, valuePtr);
    malloc.free(namePtr);
    malloc.free(valuePtr);
  }

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
    // WindowOptions isn't a const constructor, so use `final` here to avoid
    // analyzer errors on the subsequent lines (they were previously marked
    // around `size`/`minimumSize`).
    final windowOptions = WindowOptions(
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
