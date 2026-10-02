import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../services/platform_dirs.dart';

/// Shares the file at [path] as the file itself. Returns false when there is
/// no file to share.
///
/// [path] may be an Android content:// address, which is what a folder
/// picked through the system's folder picker hands out. Such a file is
/// copied out first and named [name] (plus its own extension), so the app it
/// goes to gets "Song.mp3" rather than a nameless temporary file.
Future<bool> shareMediaFile(String path,
    {required String name, String? title}) async {
  if (!path.startsWith('content://')) {
    if (!await File(path).exists()) return false;
    await SharePlus.instance
        .share(ShareParams(files: [XFile(path)], title: title ?? name));
    return true;
  }

  final copied = await PlatformDirs.copyToTemp(path);
  if (copied == null || copied.isEmpty) return false;
  final named = await _renameForSharing(File(copied), name);
  try {
    await SharePlus.instance
        .share(ShareParams(files: [XFile(named.path)], title: title ?? name));
  } finally {
    // share_plus has copied it into its own share folder by now.
    try {
      await named.parent.delete(recursive: true);
    } catch (_) {}
  }
  return true;
}

/// Moves [copy] into a folder of its own as [name] with the right extension.
Future<File> _renameForSharing(File copy, String name) async {
  var extension = p.extension(copy.path).toLowerCase();
  if (extension.isEmpty || extension == '.tmp') {
    extension = await _sniffExtension(copy);
  }
  final folder = await copy.parent.createTemp('share_');
  return copy.rename(p.join(folder.path, '${safeShareName(name)}$extension'));
}

/// The extension its first bytes say [file] has (".mp3", ".mp4"), or none.
Future<String> _sniffExtension(File file) async {
  final header = <int>[];
  await for (final chunk in file.openRead(0, 64)) {
    header.addAll(chunk);
  }
  final mime = lookupMimeType('', headerBytes: header);
  final extension = mime == null ? null : extensionFromMime(mime);
  return extension == null ? '' : '.$extension';
}

/// [name] as a file name every system accepts.
String safeShareName(String name) {
  var safe = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Windows drops trailing dots and spaces; a leading dot hides the file.
  safe = safe.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (safe.length > 120) safe = safe.substring(0, 120).trim();
  return safe.isEmpty ? 'media' : safe;
}
