import 'dart:io';

import 'package:flutter/material.dart';

import '../services/android_saf.dart';
import '../utils/snack.dart';

class FolderAccessService {
  FolderAccessService._();

  static const _errorText =
      'Selected download folder is not writable. Please choose a different folder.';

  /// Checks Android SAF tree URI write access and shows a standard Snack on failure.
  /// Returns true when folder is writable or not an Android SAF folder.
  static Future<bool> ensureSafeFolderIsWritable(
    BuildContext context,
    String? downloadFolder,
  ) async {
    if (!Platform.isAndroid) return true;

    final uri = downloadFolder?.trim();
    if (uri == null || uri.isEmpty) return true;
    if (!uri.startsWith('content://')) return true;

    final hasWrite = await AndroidSaf().testWriteAccess(uri);
    if (!hasWrite) {
      Snack.show(context, _errorText, level: SnackLevel.error);
    }
    return hasWrite;
  }
}
