import 'dart:io';

import 'package:flutter/services.dart';

class AndroidSaf {
  static const MethodChannel _channel = MethodChannel('convert_the_spire/saf');

  bool get isSupported => Platform.isAndroid;

  Future<String?> pickTree() async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('pickTree');
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
}
