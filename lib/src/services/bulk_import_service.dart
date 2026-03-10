import 'dart:io';

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
      final idx = line.indexOf(sep);
      if (idx > 0) {
        final before = line.substring(0, idx).trim();
        final after = line.substring(idx + sep.length).trim();
        if (before.isNotEmpty && after.isNotEmpty) {
          return '$before $after';
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
    final rows = _parseCsv(text);
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

  // Minimal CSV parser: splits on commas not inside quotes. Returns rows as
  // lists of strings. This avoids depending on `CsvToListConverter` API
  // differences across package versions.
  List<List<dynamic>> _parseCsv(String text) {
    final lines = text.split('\n');
    final rows = <List<dynamic>>[];
    final reg = RegExp(r',(?=(?:[^\"]*\"[^\"]*\")*[^\"]*\$)');
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(reg).map((s) {
        var v = s.trim();
        if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
          v = v.substring(1, v.length - 1).replaceAll('""', '"');
        }
        return v;
      }).toList();
      rows.add(parts);
    }
    return rows;
  }
}
