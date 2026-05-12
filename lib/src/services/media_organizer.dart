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
    print('[MediaOrganizer] Starting moveAndDeduplicate with ${sourceDirs.length} sources, target=$target');
    final moved = <String>[];
    final deleted = <String>[];
    final seen = <String, File>{};

    // Collect candidate files from sources
    final candidates = <File>[];
    for (final dirPath in sourceDirs) {
      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          print('[MediaOrganizer] Source dir does not exist: $dirPath');
          continue;
        }
        print('[MediaOrganizer] Scanning source: $dirPath');
        dir.listSync(recursive: true).whereType<File>().forEach((f) {
          final ext = p.extension(f.path).toLowerCase();
          if (ext.isEmpty) return;
          candidates.add(f);
        });
        print('[MediaOrganizer] Found ${candidates.length} candidates in $dirPath');
      } catch (e) {
        print('[MediaOrganizer] Error scanning source $dirPath: $e');
      }
    }

    print('[MediaOrganizer] Total candidates collected: ${candidates.length}');

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

    print('[MediaOrganizer] After dedup: ${seen.length} unique files, ${deleted.length} duplicates to delete');

    var movedCount = 0;
    var deletedCount = 0;
    // Ensure target when filesystem path
    final targetIsSAF = target.startsWith('content://');
    print('[MediaOrganizer] Target is SAF: $targetIsSAF');
    Directory? targetDir;
    if (!targetIsSAF) {
      targetDir = Directory(target);
      if (!targetDir.existsSync()) {
        print('[MediaOrganizer] Creating target directory: $target');
        targetDir.createSync(recursive: true);
      }
    }

    for (final entry in seen.values) {
      final destName = p.basename(entry.path);
      try {
        if (targetIsSAF) {
          final mime = _mimeTypeForExtension(p.extension(entry.path).toLowerCase());
          print('[MediaOrganizer] Copying to SAF: ${entry.path} -> $destName (mime=$mime)');
          final copied = await PlatformDirs.copyToTree(target, entry.path, destName, mime);
          if (copied != null) {
            moved.add(copied);
            movedCount++;
            print('[MediaOrganizer] Successfully copied: $destName');
          } else {
            print('[MediaOrganizer] Failed to copy: $destName');
          }
        } else {
          final dest = File(p.join(targetDir!.path, destName));
          if (p.equals(entry.path, dest.path)) {
            print('[MediaOrganizer] Skipping (same path): $destName');
            continue;
          }
          print('[MediaOrganizer] Copying to filesystem: ${entry.path} -> ${dest.path}');
          if (dest.existsSync()) {
            // If existing, keep larger file
            if (entry.lengthSync() > dest.lengthSync()) {
              entry.copySync(dest.path);
              print('[MediaOrganizer] Overwrote existing: $destName');
            }
          } else {
            entry.copySync(dest.path);
            print('[MediaOrganizer] Copied: $destName');
          }
          movedCount++;
        }
      } catch (e) {
        print('[MediaOrganizer] Error moving ${entry.path}: $e');
      }
    }

    // Delete duplicates
    for (final path in deleted) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
          deletedCount++;
          print('[MediaOrganizer] Deleted duplicate: $path');
        }
      } catch (e) {
        print('[MediaOrganizer] Error deleting $path: $e');
      }
    }

    final skipped = candidates.length - movedCount - deletedCount;
    final result = {"moved": movedCount, "deleted": deletedCount, "skipped": skipped};
    print('[MediaOrganizer] Final result: $result');
    return result;
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
