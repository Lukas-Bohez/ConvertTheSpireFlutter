import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

/// Parses bulk track lists from text or CSV and returns search queries.
class BulkImportService {
  // ─── Text parsing ────────────────────────────────────────────────────────

  /// Parse a multi-line text blob into search queries.
  /// Supports formats:  "Artist - Song", "Artist -- Song", "Song by Artist".
  List<String> parseText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return lines.map(_parseTrackLine).where((q) => q.isNotEmpty).toList();
  }

  String _parseTrackLine(String line) {
    const separators = [' - ', ' – ', ' -- ', ' by '];
    for (final sep in separators) {
      if (line.contains(sep)) {
        final parts = line.split(sep);
        if (parts.length >= 2) {
          return '${parts[0].trim()} ${parts[1].trim()}';
        }
      }
    }
    return line.trim();
  }

  // ─── File import ─────────────────────────────────────────────────────────

  /// Open a file picker for .txt / .csv and return parsed search queries.
  Future<List<String>> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv'],
    );
    if (result == null || result.files.isEmpty) return [];

    final path = result.files.single.path;
    if (path == null) return [];

    final file = File(path);
    final ext = result.files.single.extension?.toLowerCase();

    if (ext == 'csv') {
      return await _importCSV(file);
    }

    final text = await file.readAsString();
    return parseText(text);
  }

  Future<List<String>> _importCSV(File file) async {
    final text = await file.readAsString();
    final rows = const CsvToListConverter().convert(text);
    final queries = <String>[];
    for (final row in rows) {
      if (row.length >= 2) {
        queries.add('${row[0]} ${row[1]}');
      } else if (row.length == 1) {
        queries.add(row[0].toString());
      }
    }
    return queries;
  }
}
