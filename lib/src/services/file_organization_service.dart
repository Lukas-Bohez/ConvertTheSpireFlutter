import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/track_metadata.dart';

/// Organises downloaded files according to naming templates,
/// and detects duplicates by filename or content hash.
class FileOrganizationService {
  // ─── Naming templates ──────────────────────────────────────────────────

  static const templateArtistAlbum = '{artist}/{album}/{track} - {title}';
  static const templateArtistOnly = '{artist}/{title}';
  static const templateGenreArtist = '{genre}/{artist}/{title}';
  static const templateYearAlbum = '{year} - {album}/{track} - {title}';
  static const templateFlat = 'Singles/{artist} - {title}';

  static const defaultTemplate = templateArtistOnly;

  /// Apply a naming template using [metadata].
  String applyTemplate(String template, TrackMetadata metadata, {String trackNumber = '01'}) {
    return template
        .replaceAll('{artist}', _sanitize(metadata.artist))
        .replaceAll('{title}', _sanitize(metadata.title))
        .replaceAll('{album}', _sanitize(metadata.album))
        .replaceAll('{year}', metadata.year?.toString() ?? 'Unknown')
        .replaceAll('{genre}', metadata.genre ?? 'Unknown')
        .replaceAll('{track}', trackNumber);
  }

  String _sanitize(String text) {
    return text
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Move [sourcePath] to a structured location under [baseDir] using [template].
  Future<String> organizeFile(
    String sourcePath,
    TrackMetadata metadata,
    String template,
    String baseDir,
    String extension,
  ) async {
    final relative = applyTemplate(template, metadata);
    final targetPath = '$baseDir${Platform.pathSeparator}$relative.$extension';
    final targetDir = File(targetPath).parent;
    await targetDir.create(recursive: true);

    final sourceFile = File(sourcePath);
    await sourceFile.rename(targetPath);
    return targetPath;
  }

  // ─── Duplicate detection ───────────────────────────────────────────────

  /// Check for a duplicate by filename in [directory].
  Future<bool> isDuplicateByName(String filePath, String directory) async {
    final fileName = Uri.file(filePath).pathSegments.last.toLowerCase();
    final dir = Directory(directory);
    if (!await dir.exists()) return false;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final existingName = Uri.file(entity.path).pathSegments.last.toLowerCase();
        if (existingName == fileName) return true;
      }
    }
    return false;
  }

  /// Calculate MD5 hash of file contents.
  Future<String> calculateFileHash(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    return md5.convert(bytes).toString();
  }

  /// Check for a content-identical file in [directory].
  Future<bool> isDuplicateByHash(String filePath, String directory) async {
    final targetHash = await calculateFileHash(filePath);
    final dir = Directory(directory);
    if (!await dir.exists()) return false;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path != filePath) {
        final hash = await calculateFileHash(entity.path);
        if (hash == targetHash) return true;
      }
    }
    return false;
  }

  /// Scan [directory] and return groups of content-identical files.
  Future<Map<String, List<String>>> findAllDuplicates(String directory) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return {};

    final hashToFiles = <String, List<String>>{};
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final hash = await calculateFileHash(entity.path);
        hashToFiles.putIfAbsent(hash, () => []).add(entity.path);
      }
    }

    // Keep only groups with duplicates
    hashToFiles.removeWhere((_, files) => files.length < 2);
    return hashToFiles;
  }
}
