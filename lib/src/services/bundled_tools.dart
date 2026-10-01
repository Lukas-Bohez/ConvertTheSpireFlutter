import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path/path.dart' as p;

/// Programs that come with the app.
///
/// The Microsoft Store package has FFmpeg, yt-dlp and Deno in folders next
/// to the app's exe (`ffmpeg\ffmpeg.exe`, `yt-dlp\yt-dlp.exe`,
/// `deno\deno.exe`; the msstore workflow puts them there), so it works
/// without downloading programs on first use. Other Windows builds download
/// them as before; nothing is bundled there and these paths do not exist.
class BundledTools {
  BundledTools._();

  static String? get ffmpeg => pathOf('ffmpeg', 'ffmpeg.exe');
  static String? get ytDlp => pathOf('yt-dlp', 'yt-dlp.exe');
  static String? get deno => pathOf('deno', 'deno.exe');

  /// `<folder>\<exe>` next to the app's exe; null off Windows.
  @visibleForTesting
  static String? pathOf(String folder, String exe,
      {String? executable, bool? windows}) {
    if (kIsWeb || !(windows ?? Platform.isWindows)) return null;
    final dir = p.windows.dirname(executable ?? Platform.resolvedExecutable);
    return p.windows.join(dir, folder, exe);
  }
}
