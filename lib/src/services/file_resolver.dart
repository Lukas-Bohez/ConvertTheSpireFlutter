import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'platform_dirs.dart';

/// Resolve a potentially platform-specific path into a local file path that
/// native libraries can open. On Android this will copy `content://` URIs
/// into a temporary file and return the copied path.
class FileResolver {
  /// Ensure the given [path] is usable as a local filesystem path.
  ///
  /// - If [path] starts with `content://` on Android, copies it to a temp
  ///   file via `PlatformDirs.copyToTemp` and returns the temp path.
  /// - If [path] is already a `file://` or an absolute path, returns it
  ///   unchanged.
  /// - For HTTP(S) URLs returns the original value (caller must stream).
  static Future<String> ensureLocalPath(String path) async {
    if (kIsWeb) return path;
    if (path.startsWith('content://')) {
      final copied = await PlatformDirs.copyToTemp(path);
      return copied ?? path;
    }
    if (path.startsWith('file://')) return path;
    // If it's an absolute filesystem path on Android or desktop, return as-is
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS || Platform.isAndroid || Platform.isIOS) {
      return path;
    }
    return path;
  }
}
