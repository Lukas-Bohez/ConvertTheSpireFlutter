import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AndroidSaf {
  static const MethodChannel _channel = MethodChannel('convert_the_spire/saf');

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> isAndroidTV() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAndroidTV') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> pickTree() async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('pickTree');
  }

  /// Build a tree URI for the app's own DocumentsProvider from a filesystem
  /// path selected in the in-app browser fallback.
  Future<String?> pathToTreeUri(String path) async {
    if (!isSupported || path.trim().isEmpty) return null;
    return _channel.invokeMethod<String>('pathToTreeUri', {'path': path});
  }

  Future<String?> copyToTree({
    required String treeUri,
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? subdir,
  }) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('copyToTree', {
      'treeUri': treeUri,
      'sourcePath': sourcePath,
      'displayName': displayName,
      'mimeType': mimeType,
      'subdir': subdir,
    });
  }

  Future<String?> createSafFile({
    required String treeUri,
    required String fileName,
    required String mimeType,
  }) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('createSafFile', {
      'treeUri': treeUri,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }

  Future<void> copyToSafUri({
    required String sourcePath,
    required String destUri,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('copyToSafUri', {
      'sourcePath': sourcePath,
      'destUri': destUri,
    });
  }

  Future<void> copyFromSafUri({
    required String uri,
    required String destPath,
  }) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('copyFromSafUri', {
      'uri': uri,
      'destPath': destPath,
    });
  }

  Future<bool> deleteSafUri({required String uri}) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('deleteSafUri', {'uri': uri}) ?? false;
  }

  /// Tests whether we can write to the given SAF tree URI.
  ///
  /// Returns true if a small temporary file can be created and deleted.
  Future<bool> testWriteAccess(String treeUri) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('testTreeWrite', {
          'treeUri': treeUri,
        }) ?? false;
  }

  Future<bool> openTree(String treeUri) async {
    if (!isSupported) return false;
    final result = await _channel.invokeMethod<bool>('openTree', {
      'treeUri': treeUri,
    });
    return result ?? false;
  }

  Future<String?> copyToDownloads({
    required String sourcePath,
    required String displayName,
    required String mimeType,
    String? subdir,
  }) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('copyToDownloads', {
      'sourcePath': sourcePath,
      'displayName': displayName,
      'mimeType': mimeType,
      'subdir': subdir,
    });
  }

  Future<String?> copyToTemp({required String uri}) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('copyToTemp', {'uri': uri});
  }

  Future<List<Map<String, String>>> getExternalVolumes() async {
    if (!isSupported) return const [];
    final result = await _channel.invokeMethod<List<dynamic>>('getExternalVolumes');
    final volumes = <Map<String, String>>[];
    for (final item in result ?? const []) {
      if (item is Map) {
        final volume = <String, String>{};
        item.forEach((key, value) {
          volume[key.toString()] = value?.toString() ?? '';
        });
        volumes.add(volume);
      }
    }
    return volumes;
  }
}
