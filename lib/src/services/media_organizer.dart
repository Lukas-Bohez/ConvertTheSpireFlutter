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
  static Future<Map<String, int>> moveAndDeduplicate(
      List<String> sourceDirs, String target) async {
      stdout.writeln(
        '[MediaOrganizer] Starting moveAndDeduplicate with ${sourceDirs.length} sources, target=$target');
    final moved = <String>[];
    final deleted = <String>[];
    final seen = <String, _MediaCandidate>{};

    final normalizedTarget = target.startsWith('content://')
        ? target
        : p.normalize(p.absolute(target));
    final filteredSources = <String>[];
    for (final source in sourceDirs) {
      if (source.trim().isEmpty) continue;
      if (target.startsWith('content://')) {
        filteredSources.add(source);
        continue;
      }

      final normalizedSource = p.normalize(p.absolute(source));
      final overlapsTarget = normalizedSource == normalizedTarget ||
          p.isWithin(normalizedSource, normalizedTarget) ||
          p.isWithin(normalizedTarget, normalizedSource);
      if (overlapsTarget) {
        stdout.writeln(
            '[MediaOrganizer] Skipping overlapping source/target path: $source');
        continue;
      }
      if (!filteredSources.contains(source)) {
        filteredSources.add(source);
      }
    }

    if (filteredSources.isEmpty) {
        stdout.writeln(
          '[MediaOrganizer] No valid source directories after filtering overlaps.');
      return {'moved': 0, 'deleted': 0, 'skipped': 0};
    }

    // Collect candidate files from sources.
    // SAF sources are enumerated natively and represented by their original URIs,
    // not by temp files, so dedupe and copy can stay URI-aware.
    final candidates = <_MediaCandidate>[];
    for (final dirPath in filteredSources) {
      try {
        // If the source is a SAF tree URI, enumerate via native channel
        if (dirPath.startsWith('content://')) {
          stdout.writeln('[MediaOrganizer] Enumerating SAF tree: $dirPath');
          final items = await PlatformDirs.listTree(dirPath);
          for (final item in items) {
            final uri = item['uri'] ?? '';
            if (uri.isEmpty) continue;
            final name = item['name'] ?? p.basename(Uri.parse(uri).path);
            final mimeType = item['mimeType'] ??
                _mimeTypeForExtension(p.extension(name).toLowerCase());
            final size = int.tryParse(item['size'] ?? '') ?? 0;
            candidates.add(_MediaCandidate(
              displayName:
                  name.isEmpty ? p.basename(Uri.parse(uri).path) : name,
              sourceUri: uri,
              mimeType: mimeType,
              size: size,
            ));
          }
            stdout.writeln(
              '[MediaOrganizer] Found ${candidates.length} candidates in SAF $dirPath');
          continue;
        }

        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          stdout.writeln('[MediaOrganizer] Source dir does not exist: $dirPath');
          continue;
        }
        stdout.writeln('[MediaOrganizer] Scanning source: $dirPath');
        dir.listSync(recursive: true).whereType<File>().forEach((f) {
          final ext = p.extension(f.path).toLowerCase();
          if (ext.isEmpty) return;
          candidates.add(_MediaCandidate(
            displayName: p.basename(f.path),
            sourcePath: f.path,
            mimeType: _mimeTypeForExtension(ext),
            size: f.lengthSync(),
          ));
        });
        stdout.writeln(
            '[MediaOrganizer] Found ${candidates.length} candidates in $dirPath');
      } catch (e) {
        stdout.writeln('[MediaOrganizer] Error scanning source $dirPath: $e');
      }
    }

    stdout.writeln('[MediaOrganizer] Total candidates collected: ${candidates.length}');

    // Group by basename
    for (final candidate in candidates) {
      final key = p.basename(candidate.displayName).toLowerCase();
      final prev = seen[key];
      if (prev == null) {
        seen[key] = candidate;
      } else {
        // Keep largest
        if (candidate.size > prev.size) {
          deleted.add(prev.debugPath);
          seen[key] = candidate;
        } else {
          deleted.add(candidate.debugPath);
        }
      }
    }

    stdout.writeln(
        '[MediaOrganizer] After dedup: ${seen.length} unique files, ${deleted.length} duplicates to delete');

    var movedCount = 0;
    var deletedCount = 0;
    // Ensure target when filesystem path
    final targetIsSAF = target.startsWith('content://');
    stdout.writeln('[MediaOrganizer] Target is SAF: $targetIsSAF');
    Directory? targetDir;
    if (!targetIsSAF) {
      targetDir = Directory(target);
      if (!targetDir.existsSync()) {
        stdout.writeln('[MediaOrganizer] Creating target directory: $target');
        targetDir.createSync(recursive: true);
      }
    }

    for (final entry in seen.values) {
      final destName = p.basename(entry.displayName);
      try {
        if (targetIsSAF) {
          final mime = entry.mimeType;
            stdout.writeln(
              '[MediaOrganizer] Copying to SAF: ${entry.debugPath} -> $destName (mime=$mime)');
          final copied = entry.sourceUri != null
              ? await PlatformDirs.copyContentUriToTree(
                  target, entry.sourceUri!, destName, mime)
              : await PlatformDirs.copyToTree(
                  target, entry.sourcePath!, destName, mime);
          if (copied != null) {
            moved.add(copied);
            movedCount++;
            stdout.writeln('[MediaOrganizer] Successfully copied: $destName');
          } else {
            stdout.writeln('[MediaOrganizer] Failed to copy: $destName');
          }
        } else {
          final dest = File(p.join(targetDir!.path, destName));
          if (entry.sourcePath != null &&
              p.equals(entry.sourcePath!, dest.path)) {
            stdout.writeln('[MediaOrganizer] Skipping (same path): $destName');
            continue;
          }
          stdout.writeln(
              '[MediaOrganizer] Copying to filesystem: ${entry.debugPath} -> ${dest.path}');
          if (dest.existsSync()) {
            // If existing, keep larger file
            if (entry.size > dest.lengthSync()) {
              if (entry.sourceUri != null) {
                final ok = await PlatformDirs.copyContentUriToFile(
                    entry.sourceUri!, dest.path);
                if (!ok) throw Exception('copyContentUriToFile failed');
              } else {
                File(entry.sourcePath!).copySync(dest.path);
              }
              stdout.writeln('[MediaOrganizer] Overwrote existing: $destName');
            }
          } else {
            if (entry.sourceUri != null) {
              final ok = await PlatformDirs.copyContentUriToFile(
                  entry.sourceUri!, dest.path);
              if (!ok) throw Exception('copyContentUriToFile failed');
            } else {
              File(entry.sourcePath!).copySync(dest.path);
            }
            stdout.writeln('[MediaOrganizer] Copied: $destName');
          }
          movedCount++;
        }
      } catch (e) {
        stdout.writeln('[MediaOrganizer] Error moving ${entry.debugPath}: $e');
      }
    }

    // Delete duplicates
    for (final path in deleted) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
          deletedCount++;
          stdout.writeln('[MediaOrganizer] Deleted duplicate: $path');
        }
      } catch (e) {
        stdout.writeln('[MediaOrganizer] Error deleting $path: $e');
      }
    }

    final skipped = candidates.length - movedCount - deletedCount;
    final result = {
      'moved': movedCount,
      'deleted': deletedCount,
      'skipped': skipped
    };
    stdout.writeln('[MediaOrganizer] Final result: $result');
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

class _MediaCandidate {
  final String displayName;
  final String? sourcePath;
  final String? sourceUri;
  final String mimeType;
  final int size;

  const _MediaCandidate({
    required this.displayName,
    required this.mimeType,
    required this.size,
    this.sourcePath,
    this.sourceUri,
  });

  String get debugPath => sourcePath ?? sourceUri ?? displayName;
}
