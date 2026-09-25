import 'dart:io';

import 'package:path/path.dart' as p;

/// What [TorrentContentDeleter.delete] did.
class TorrentContentDeletion {
  const TorrentContentDeletion({
    this.deleted = const [],
    this.missing = const [],
    this.failed = const [],
    this.skipped = const [],
  });

  /// Files that were deleted.
  final List<String> deleted;

  /// Files of the torrent that were not on disk.
  final List<String> missing;

  /// Files that could not be deleted, usually because they are open.
  final List<String> failed;

  /// Entries of the file list that point outside the download folder, at
  /// the folder itself, or at something that is not a file. Never touched.
  final List<String> skipped;
}

/// Deletes what a torrent downloaded, and nothing else.
///
/// "Remove torrent and delete files" used to delete the torrent's download
/// folder recursively. That folder is shared by every torrent, and is often
/// the user's own Downloads folder, so it wiped everything in it. This only
/// ever deletes:
///  - the files in the torrent's own file list, one by one, and only when
///    they are strictly inside [saveDir];
///  - folders inside [saveDir] that are empty once those files are gone;
///  - the torrent's own resume state file.
/// Never a folder with anything left in it, and never [saveDir] itself.
class TorrentContentDeleter {
  const TorrentContentDeleter._();

  static Future<TorrentContentDeletion> delete({
    required String saveDir,
    required Iterable<String> relativeFiles,
    String? stateFileName,
  }) async {
    final deleted = <String>[];
    final missing = <String>[];
    final failed = <String>[];
    final skipped = <String>[];
    if (saveDir.trim().isEmpty) {
      return TorrentContentDeletion(skipped: relativeFiles.toList());
    }
    final base = p.normalize(p.absolute(saveDir));
    final parents = <String>{};

    for (final relative in relativeFiles) {
      final target = resolveInside(base, relative);
      if (target == null) {
        skipped.add(relative);
        continue;
      }
      final type = await FileSystemEntity.type(target, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        missing.add(target);
      } else if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        try {
          await File(target).delete();
          deleted.add(target);
        } catch (_) {
          failed.add(target);
        }
      } else {
        // A folder where the torrent has a file: not ours to delete.
        skipped.add(relative);
        continue;
      }
      parents.add(p.dirname(target));
    }

    if (stateFileName != null && stateFileName.isNotEmpty) {
      final state = resolveInside(base, stateFileName);
      if (state != null &&
          await FileSystemEntity.type(state, followLinks: false) ==
              FileSystemEntityType.file) {
        try {
          await File(state).delete();
        } catch (_) {
          // The download itself is gone; a stale state file is harmless.
        }
      }
    }

    await _removeEmptyFolders(base, parents);
    return TorrentContentDeletion(
      deleted: deleted,
      missing: missing,
      failed: failed,
      skipped: skipped,
    );
  }

  /// [relative] joined to [base], or null unless the result is strictly
  /// inside [base]. Rejects absolute paths, `..` and paths that come back to
  /// [base] itself, such as `.` or `a/..`.
  static String? resolveInside(String base, String relative) {
    final cleaned = relative.replaceAll('\\', '/').trim();
    if (cleaned.isEmpty || p.posix.isAbsolute(cleaned) || p.isAbsolute(cleaned)) {
      return null;
    }
    final segments = cleaned.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty || segments.any((s) => s == '..' || s == '.')) {
      return null;
    }
    final target = p.normalize(p.join(base, p.joinAll(segments)));
    return p.isWithin(base, target) ? target : null;
  }

  /// Deletes each folder in [folders], and the folders above it up to [base],
  /// while they are empty. Stops at the first one with anything in it.
  static Future<void> _removeEmptyFolders(
    String base,
    Set<String> folders,
  ) async {
    // Deepest first, so a parent is only checked after its children.
    final ordered = folders.toList()
      ..sort((a, b) => p.split(b).length.compareTo(p.split(a).length));
    for (var folder in ordered) {
      while (p.isWithin(base, folder)) {
        final dir = Directory(folder);
        try {
          if (await dir.exists()) {
            if (!await dir.list().isEmpty) break;
            await dir.delete();
          }
        } catch (_) {
          break;
        }
        folder = p.dirname(folder);
      }
    }
  }
}
