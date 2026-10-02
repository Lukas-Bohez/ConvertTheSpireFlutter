import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// One song in an exported track list.
typedef ListedTrack = ({String artist, String title});

/// Parses bulk track lists from text or CSV and returns search queries, and
/// writes the songs on this device out as such a list.
class BulkImportService {
  /// The header row [buildCsvList] writes.
  static const csvHeader = ['Artist', 'Title'];

  // --─ Text parsing --------------------------------------------------------

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
    const separators = [' - ', ' - ', ' -- ', ' by '];
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

  // --─ File import --------------------------------------------------------─

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

    final text = _withoutBom(await file.readAsString());
    if (text.trim().isEmpty) return [];
    return parseText(text);
  }

  Future<List<String>> _importCSV(File file) async =>
      parseCsv(await file.readAsString());

  /// The search queries in a CSV track list: artist and title from the first
  /// two columns. A header row such as the one [buildCsvList] writes is
  /// skipped.
  List<String> parseCsv(String text) {
    text = _withoutBom(text);
    if (text.trim().isEmpty) return [];
    final rows = _parseCsv(text);
    if (rows.isNotEmpty && _isHeader(rows.first)) rows.removeAt(0);
    final queries = <String>[];
    for (final row in rows) {
      final query = row.take(2).join(' ').trim();
      if (query.isNotEmpty) queries.add(query);
    }
    return queries;
  }

  static bool _isHeader(List<dynamic> row) {
    const names = {'artist', 'title', 'song', 'track', 'name', 'track name'};
    return row.isNotEmpty &&
        row.take(2).every((cell) => names.contains('$cell'.toLowerCase()));
  }

  static String _withoutBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;

  // --─ Export ---------------------------------------------------------------

  /// The artist and title to list for a song with the tags [artist] and
  /// [title] in a file named [fileName] (without its extension). A file
  /// named "Artist - Title [videoId]", as downloads are, lists as that.
  static ListedTrack trackFor(
      {String? artist, String? title, required String fileName}) {
    var name = title?.trim() ?? '';
    if (name.isEmpty) {
      name =
          fileName.replaceAll(RegExp(r'\s*\[[a-zA-Z0-9_\-]{11}\]'), '').trim();
    }
    var by = artist?.trim() ?? '';
    if (by.isNotEmpty &&
        name.length > by.length + 3 &&
        name.toLowerCase().startsWith('${by.toLowerCase()} - ')) {
      name = name.substring(by.length + 3).trim();
    }
    if (by.isEmpty) {
      final dash = name.indexOf(' - ');
      if (dash > 0) {
        by = name.substring(0, dash).trim();
        name = name.substring(dash + 3).trim();
      }
    }
    return (artist: by, title: name);
  }

  /// [tracks] without blank titles and without the same song twice.
  static List<ListedTrack> uniqueTracks(Iterable<ListedTrack> tracks) {
    final seen = <String>{};
    return [
      for (final track in tracks)
        if (track.title.isNotEmpty &&
            seen.add('${track.artist}\u0000${track.title}'.toLowerCase()))
          track,
    ];
  }

  /// [tracks] as a text list [parseText] reads back: an "Artist - Title"
  /// line each, or the title alone when the artist is unknown.
  static String buildTextList(List<ListedTrack> tracks) => [
        for (final t in tracks)
          t.artist.isEmpty ? t.title : '${t.artist} - ${t.title}',
        '',
      ].join('\n');

  /// [tracks] as a spreadsheet: an "Artist,Title" header, then a row each.
  /// It starts with a byte order mark so Excel reads it as UTF-8.
  static String buildCsvList(List<ListedTrack> tracks) {
    String cell(String value) => RegExp(r'[",\r\n]').hasMatch(value)
        ? '"${value.replaceAll('"', '""')}"'
        : value;
    return '\uFEFF${[
      csvHeader.join(','),
      for (final t in tracks) '${cell(t.artist)},${cell(t.title)}',
      '',
    ].join('\r\n')}';
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
