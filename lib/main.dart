import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      debugPrint('Skipping MediaKit initialization on Android (unsupported)');
    } else {
      try {
        MediaKit.ensureInitialized(); // required by media_kit (synchronous)
      } catch (e, st) {
        final msg = '$e';
        if (msg.contains('Unsupported platform')) {
          // treat as non‑fatal; video will simply stay disabled
          debugPrint('MediaKit not supported: $msg');
        } else {
          mediaKitError = msg;
          debugPrint('MediaKit initialization failed: $e');
          debugPrint('$st');
        }
      }
    }
  }

  runApp(MyApp(mediaKitInitError: mediaKitError));
}
