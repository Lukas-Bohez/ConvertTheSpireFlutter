import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:permission_handler/permission_handler.dart';

/// Platform-aware directory resolver.
///
/// On Android, uses a native MethodChannel to bypass path_provider's Pigeon
/// channels which are broken in release mode when ffmpeg_kit_flutter_new (or
/// other plugins with old AGP versions) is present.
///
/// On other platforms, delegates to path_provider.
class PlatformDirs {
  static const MethodChannel _channel = MethodChannel('convert_the_spire/saf');

  /// App-internal files directory (equivalent to getApplicationDocumentsDirectory on Android).
  static Future<Directory?> getFilesDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getFilesDir');
        if (path != null && path.isNotEmpty) {
          return Directory(path);
        }
      } catch (_) {}
      return null;
    }
    try {
      return await pp.getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  /// App-internal cache directory (equivalent to getTemporaryDirectory).
  static Future<Directory> getCacheDir() async {
    if (kIsWeb) return Directory.systemTemp;
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getCacheDir');
        if (path != null && path.isNotEmpty) {
          return Directory(path);
        }
      } catch (_) {}
      return Directory.systemTemp;
    }
    try {
      return await pp.getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// App-specific external storage (no permissions needed on Android).
  /// Equivalent to getExternalStorageDirectory.
  static Future<Directory?> getExternalDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      try {
        final path = await _channel.invokeMethod<String>('getExternalFilesDir');
        if (path != null && path.isNotEmpty) {
          return Directory(path);
        }
      } catch (_) {}
      return null;
    }
    try {
      return await pp.getExternalStorageDirectory();
    } catch (_) {
      return null;
    }
  }

  /// Enumerates all files beneath a SAF tree URI, returning a map for each
  /// document containing its content URI and its display name.
  ///
  /// This is used when the directory picker returns a content:// URI which
  /// cannot be accessed via `Directory` on Android.
  static Future<List<Map<String, String>>> listTree(String treeUri) async {
    if (kIsWeb) return [];
    try {
      final List<dynamic> resp =
          await _channel.invokeMethod('listTree', {'treeUri': treeUri});
      // The platform channel returns loosely-typed maps (Map<Object?,Object?>),
      // so we need to manually convert each entry to a Map<String,String> rather
      // than relying on `cast` which throws at iteration time.
      final List<Map<String, String>> result = [];
      for (final item in resp) {
        if (item is Map) {
          final Map<String, String> m = {};
          item.forEach((key, value) {
            m[key.toString()] = value?.toString() ?? '';
          });
          result.add(m);
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Show the system folder picker (ACTION_OPEN_DOCUMENT_TREE) and return a
  /// persistable URI or null if the user cancelled.  This matches the
  /// `pickTree` method implemented in MainActivity.kt.
  static Future<String?> pickTree() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('pickTree');
    } catch (_) {
      return null;
    }
  }

  /// Ask native code to convert a SAF tree URI into a filesystem path when
  /// possible (e.g. mounted USB drives). Returns the filesystem path or the
  /// original tree URI string if conversion isn't possible.
  static Future<String?> getPathFromTreeUri(String treeUri) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('getPathFromTreeUri', {'treeUri': treeUri});
    } catch (_) {
      return null;
    }
  }

  /// Copy a document represented by a content:// URI into a temporary file
  /// under the app cache directory.  Returns the local file path or null on
  /// failure.  The native implementation (`copyToTemp`) is provided in
  /// MainActivity.kt and is useful for plugins that require real file paths
  /// (e.g. metadata readers or thumbnail generators).
  static Future<String?> copyToTemp(String uri) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('copyToTemp', {'uri': uri});
    } catch (_) {
      return null;
    }
  }

  /// Copy a `content://` URI directly to a filesystem path on Android.
  static Future<bool> copyContentUriToFile(String sourceUri, String destinationPath) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('copyContentUriToFile', {
            'sourceUri': sourceUri,
            'destinationPath': destinationPath,
          }) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Copy a local file (sourcePath) into a SAF tree target (treeUri).
  /// Returns the destination content URI string on success or null on failure.
  static Future<String?> copyToTree(String treeUri, String sourcePath, String displayName, String mimeType, {String? subdir}) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('copyToTree', {
        'treeUri': treeUri,
        'sourcePath': sourcePath,
        'displayName': displayName,
        'mimeType': mimeType,
        'subdir': subdir ?? ''
      });
    } catch (_) {
      return null;
    }
  }

  /// Copy a `content://` source directly into a SAF tree target (treeUri).
  static Future<String?> copyContentUriToTree(String treeUri, String sourceUri, String displayName, String mimeType, {String? subdir}) async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('copyContentUriToTree', {
        'treeUri': treeUri,
        'sourceUri': sourceUri,
        'displayName': displayName,
        'mimeType': mimeType,
        'subdir': subdir ?? ''
      });
    } catch (_) {
      return null;
    }
  }

  /// Application support directory (for config files).
  /// On Android, uses filesDir. On desktop, uses getApplicationSupportDirectory.
  static Future<Directory?> getAppSupportDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      // On Android, filesDir IS the app support directory
      return getFilesDir();
    }
    try {
      return await pp.getApplicationSupportDirectory();
    } catch (_) {
      return await getFilesDir();
    }
  }

  /// Downloads directory (desktop only).
  static Future<Directory?> getDownloadsDir() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid || Platform.isIOS) return null;
    try {
      return await pp.getDownloadsDirectory();
    } catch (_) {
      return null;
    }
  }

  /// Check if MANAGE_EXTERNAL_STORAGE (All Files Access) is granted on Android.
  /// On other platforms, always returns true (no such permission needed).
  static Future<bool> hasManageExternalStoragePermission() async {
    if (kIsWeb) return true;
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.manageExternalStorage.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
}
