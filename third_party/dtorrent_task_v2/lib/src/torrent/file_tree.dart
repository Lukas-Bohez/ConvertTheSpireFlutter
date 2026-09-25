import 'dart:typed_data';

/// Represents a file in v2 file tree structure (BEP 52)
class FileTreeEntry {
  /// File length in bytes
  final int length;

  /// Pieces root (32-byte SHA-256 hash) for non-empty files
  final Uint8List? piecesRoot;

  /// Child entries (for directories)
  final Map<String, FileTreeEntry>? children;

  /// Whether this is a file (has length) or directory
  bool get isFile => length >= 0 && children == null;

  /// Whether this is a directory
  bool get isDirectory => children != null;

  FileTreeEntry({
    required this.length,
    this.piecesRoot,
    this.children,
  }) {
    if (isFile && piecesRoot != null && piecesRoot!.length != 32) {
      throw ArgumentError('Pieces root must be 32 bytes for v2 files');
    }
  }

  /// Create file entry
  factory FileTreeEntry.file(int length, Uint8List? piecesRoot) {
    return FileTreeEntry(length: length, piecesRoot: piecesRoot);
  }

  /// Create directory entry
  factory FileTreeEntry.directory(Map<String, FileTreeEntry> children) {
    return FileTreeEntry(length: -1, children: children);
  }
}

/// Helper class for parsing and working with v2 file tree structure
class FileTreeHelper {
  /// Parse file tree from bencoded dictionary
  ///
  /// File tree structure:
  /// {
  ///   "dir1": {
  ///     "dir2": {
  ///       "file.txt": {
  ///         "": {
  ///           "length": 1024,
  ///           "pieces root": <32-byte hash>
  ///         }
  ///       }
  ///     }
  ///   }
  /// }
  static Map<String, FileTreeEntry>? parseFileTree(dynamic treeData) {
    if (treeData is! Map) {
      return null;
    }

    final result = <String, FileTreeEntry>{};

    for (var entry in treeData.entries) {
      final key = entry.key as String;
      final value = entry.value;

      if (value is Map) {
        // Check if this is a file entry (has empty string key with length)
        if (value.containsKey('')) {
          final fileData = value[''];
          if (fileData is Map) {
            final length = fileData['length'] as int?;
            final piecesRoot = fileData['pieces root'] as Uint8List?;

            if (length != null) {
              result[key] = FileTreeEntry.file(length, piecesRoot);
            }
          }
        } else {
          // This is a directory, recursively parse children
          final children = parseFileTree(value);
          if (children != null) {
            result[key] = FileTreeEntry.directory(children);
          }
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  /// Extract all files from file tree with their paths
  static List<FileTreeFile> extractFiles(
      Map<String, FileTreeEntry> tree, String basePath) {
    final files = <FileTreeFile>[];

    for (var entry in tree.entries) {
      final path = basePath.isEmpty ? entry.key : '$basePath/${entry.key}';
      final fileEntry = entry.value;

      if (fileEntry.isFile) {
        files.add(FileTreeFile(
          path: path,
          length: fileEntry.length,
          piecesRoot: fileEntry.piecesRoot,
        ));
      } else if (fileEntry.isDirectory && fileEntry.children != null) {
        files.addAll(extractFiles(fileEntry.children!, path));
      }
    }

    return files;
  }

  /// Calculate total size from file tree
  static int calculateTotalSize(Map<String, FileTreeEntry> tree) {
    var total = 0;

    for (var entry in tree.values) {
      if (entry.isFile) {
        total += entry.length;
      } else if (entry.isDirectory && entry.children != null) {
        total += calculateTotalSize(entry.children!);
      }
    }

    return total;
  }
}

/// Represents a file in v2 file tree with its path and properties
class FileTreeFile {
  final String path;
  final int length;
  final Uint8List? piecesRoot;

  FileTreeFile({
    required this.path,
    required this.length,
    this.piecesRoot,
  });
}
