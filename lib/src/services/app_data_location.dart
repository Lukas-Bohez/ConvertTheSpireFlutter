import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the app keeps its own databases and files.
///
/// On desktop they used to go in the user's Documents folder, next to their
/// own files, where Windows 11 often syncs them to OneDrive: a database that
/// changes every few seconds, locked by the sync now and then. They now live
/// in the app's data folder (%APPDATA% on Windows), and the ones already in
/// Documents are moved there the first time they are asked for.
///
/// On phones Documents is already private to the app and nothing moves.
class AppDataLocation {
  AppDataLocation._();

  static final Map<String, Future<String>> _paths = {};

  /// The path of [name], a file or folder of the app's own, moved from
  /// Documents first if it was there. A database's -wal, -shm and -journal
  /// files move with it.
  static Future<String> pathOf(String name) =>
      _paths[name] ??= _resolve(name).catchError((Object e) {
        _paths.remove(name);
        throw e;
      });

  static Future<String> _resolve(String name) async {
    final documents = await getApplicationDocumentsDirectory();
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      return p.join(documents.path, name);
    }
    final Directory data;
    try {
      data = await getApplicationSupportDirectory();
      await data.create(recursive: true);
    } catch (e) {
      debugPrint('AppDataLocation: no app data folder, using Documents: $e');
      return p.join(documents.path, name);
    }
    try {
      await moveIfThere(documents, data, name);
    } catch (e) {
      // Nothing is lost: the old copy stays where it was, and is used.
      debugPrint('AppDataLocation: could not move $name: $e');
      if (await _exists(p.join(documents.path, name)) &&
          !await _exists(p.join(data.path, name))) {
        return p.join(documents.path, name);
      }
    }
    return p.join(data.path, name);
  }

  /// Moves [name] (and a database's side files) from [from] to [to] when it
  /// is in [from] and not yet in [to]. The main file or folder goes last, so
  /// a move cut short is finished on the next start.
  @visibleForTesting
  static Future<void> moveIfThere(
      Directory from, Directory to, String name) async {
    if (p.equals(from.path, to.path)) return;
    final target = p.join(to.path, name);
    if (await _exists(target)) return;
    final source = p.join(from.path, name);
    if (!await _exists(source)) return;
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final side = File('$source$suffix');
      if (await side.exists()) await _moveFile(side, '$target$suffix');
    }
    if (await FileSystemEntity.isDirectory(source)) {
      await _moveDirectory(Directory(source), target);
    } else {
      await _moveFile(File(source), target);
    }
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path) != FileSystemEntityType.notFound;

  static Future<void> _moveFile(File file, String target) async {
    try {
      await file.rename(target);
    } on FileSystemException {
      // Another drive: copy, then remove the original.
      await file.copy(target);
      await file.delete();
    }
  }

  static Future<void> _moveDirectory(Directory dir, String target) async {
    try {
      await dir.rename(target);
      return;
    } on FileSystemException {
      // Another drive: copy file by file.
    }
    final staging = Directory('$target.moving');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: dir.path);
      if (entity is Directory) {
        await Directory(p.join(staging.path, relative)).create(recursive: true);
      } else if (entity is File) {
        final copy = File(p.join(staging.path, relative));
        await copy.parent.create(recursive: true);
        await entity.copy(copy.path);
      }
    }
    await staging.rename(target);
    await dir.delete(recursive: true);
  }
}
