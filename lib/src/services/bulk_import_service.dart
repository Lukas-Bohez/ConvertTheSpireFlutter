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
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      rows.add(_splitCsvLine(line));
    }
    return rows;
  }

  // Safe, linear-time CSV line splitter that handles quoted fields and
  // doubled-quote escapes. Avoids catastrophic backtracking from regexes.
  List<String> _splitCsvLine(String line) {
    final fields = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++; // skip escaped quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    fields.add(sb.toString().trim());
    // Unwrap surrounding quotes if present
    for (var j = 0; j < fields.length; j++) {
      var v = fields[j];
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1).replaceAll('""', '"');
      }
      fields[j] = v;
    }
    return fields;
  }
}
