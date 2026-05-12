import 'dart:io';
import 'package:path/path.dart' as p;
import 'platform_dirs.dart';

class MediaOrganizer {
  /// Move files from [sourceDirs] into [target].
  ///
  /// - If [target] starts with `content://` it will attempt to copy files
  ///   into the SAF tree using `PlatformDirs.copyToTree` (Android).
  /// - Deduplication: files with identical base filenames are compared by
  ///   file size and the largest is kept; smaller duplicates are deleted.
  /// Returns a map with counts: {"moved": int, "skipped": int, "deleted": int}
  static Future<Map<String, int>> moveAndDeduplicate(List<String> sourceDirs, String target) async {
    final moved = <String>[];
    final deleted = <String>[];
    final seen = <String, File>{};

    // Collect candidate files from sources
    final candidates = <File>[];
    for (final dirPath in sourceDirs) {
      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) continue;
        dir.listSync(recursive: true).whereType<File>().forEach((f) {
          final ext = p.extension(f.path).toLowerCase();
          if (ext.isEmpty) return;
          candidates.add(f);
        });
      } catch (_) {}
    }

    // Group by basename
    for (final f in candidates) {
      final key = p.basename(f.path).toLowerCase();
      final prev = seen[key];
      if (prev == null) {
        seen[key] = f;
      } else {
        // Keep largest
        if (f.lengthSync() > prev.lengthSync()) {
          deleted.add(prev.path);
          seen[key] = f;
        } else {
          deleted.add(f.path);
        }
      }
    }

    var movedCount = 0;
    var deletedCount = 0;
    // Ensure target when filesystem path
    final targetIsSAF = target.startsWith('content://');
    Directory? targetDir;
    if (!targetIsSAF) {
      targetDir = Directory(target);
      if (!targetDir.existsSync()) targetDir.createSync(recursive: true);
    }

    for (final entry in seen.values) {
      final destName = p.basename(entry.path);
      try {
        if (targetIsSAF) {
          final mime = _mimeTypeForExtension(p.extension(entry.path).toLowerCase());
          final copied = await PlatformDirs.copyToTree(target, entry.path, destName, mime);
          if (copied != null) {
            moved.add(copied);
            movedCount++;
          }
        } else {
          final dest = File(p.join(targetDir!.path, destName));
          if (dest.existsSync()) {
            // If existing, keep larger file
            if (entry.lengthSync() > dest.lengthSync()) {
              entry.copySync(dest.path);
            }
          } else {
            entry.copySync(dest.path);
          }
          movedCount++;
        }
      } catch (_) {}
    }

    // Delete duplicates
    for (final path in deleted) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
          deletedCount++;
        }
      } catch (_) {}
    }

    return {"moved": movedCount, "deleted": deletedCount, "skipped": candidates.length - movedCount - deletedCount};
  }

  static String _mimeTypeForExtension(String ext) {
    if (ext == '.mp3') return 'audio/mpeg';
    if (ext == '.m4a') return 'audio/mp4';
    if (ext == '.wav') return 'audio/wav';
    if (ext == '.flac') return 'audio/flac';
    if (ext == '.mp4' || ext == '.m4v') return 'video/mp4';
    if (ext == '.mkv') return 'video/x-matroska';
    return 'application/octet-stream';
  }
}
