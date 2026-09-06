import 'dart:io';

import 'crash_dump_windows.dart';

Future<void> captureCrashDump(String reason, String logPath) {
  if (Platform.isWindows) {
    return captureWindowsMiniDump(reason, logPath);
  }
  return Future<void>.value();
}
