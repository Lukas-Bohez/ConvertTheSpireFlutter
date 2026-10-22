import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show PlatformException;

import 'android_saf.dart';

/// How deleting a file from the library ended.
enum DeleteOutcome {
  deleted,

  /// It was not there any more: as good as deleted.
  alreadyGone,

  /// The user said no in Android's own "Allow deleting?" dialog.
  cancelled,

  /// The app no longer has access to the folder the user picked.
  permissionLost,

  /// Android did not allow it.
  refused,
  failed;

  bool get removed => this == deleted || this == alreadyGone;
}

/// Deletes a library file the way its path needs (issue #45, fix 12).
///
/// On phones the library mostly comes from a folder the user picked, so its
/// paths are `content://` links, and the player refused every one of those:
/// Delete always said "Could not delete file". Files in shared storage that
/// the app did not create need the user's yes in Android's own dialog.
class MediaDeleteService {
  MediaDeleteService({
    AndroidSaf? saf,
    bool? isAndroid,
    Future<bool> Function(String uri)? deleteSafUri,
    Future<String> Function(List<String> uris)? deleteMediaUris,
    Future<String?> Function(String path)? mediaUriForPath,
  })  : _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
        _deleteSafUri = deleteSafUri ??
            ((uri) => (saf ?? AndroidSaf()).deleteSafUri(uri: uri)),
        _deleteMediaUris = deleteMediaUris ??
            ((uris) => (saf ?? AndroidSaf()).deleteMediaUris(uris)),
        _mediaUriForPath = mediaUriForPath ??
            ((path) => (saf ?? AndroidSaf()).mediaUriForPath(path));

  final bool _isAndroid;
  final Future<bool> Function(String uri) _deleteSafUri;
  final Future<String> Function(List<String> uris) _deleteMediaUris;
  final Future<String?> Function(String path) _mediaUriForPath;

  /// A MediaStore item, as Android's Downloads hands back.
  static bool isMediaStoreUri(String path) =>
      path.startsWith('content://media/');

  Future<DeleteOutcome> delete(String path) async {
    if (path.startsWith('content://')) {
      if (isMediaStoreUri(path)) return _viaMediaStore(path);
      try {
        return await _deleteSafUri(path)
            ? DeleteOutcome.deleted
            : DeleteOutcome.failed;
      } on PlatformException catch (e) {
        final message = '${e.code} ${e.message}'.toLowerCase();
        return message.contains('permission') || message.contains('security')
            ? DeleteOutcome.permissionLost
            : DeleteOutcome.failed;
      }
    }

    final file = File(path);
    if (!await file.exists()) return DeleteOutcome.alreadyGone;
    try {
      await file.delete();
      return DeleteOutcome.deleted;
    } on FileSystemException {
      if (!_isAndroid) return DeleteOutcome.refused;
      // Shared storage (Music, Download) on Android 11+: a file the app did
      // not create is deleted through MediaStore, with the user's yes.
      final uri = await _mediaUriForPath(path);
      if (uri == null) return DeleteOutcome.refused;
      return _viaMediaStore(uri);
    }
  }

  Future<DeleteOutcome> _viaMediaStore(String uri) async {
    try {
      return switch (await _deleteMediaUris([uri])) {
        'deleted' => DeleteOutcome.deleted,
        'cancelled' => DeleteOutcome.cancelled,
        _ => DeleteOutcome.refused,
      };
    } on PlatformException {
      return DeleteOutcome.failed;
    }
  }
}
