import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Builds a .torrent file to share, for a torrent whose info dictionary is
/// known.
///
/// A torrent's identity is the SHA-1 of its bencoded info dictionary, byte
/// for byte, so the dictionary is copied as it is and never decoded and
/// encoded again: that can reorder keys or change strings, and the file
/// would then describe a different torrent.
class TorrentFileExport {
  const TorrentFileExport._();

  /// A .torrent file around [info], announcing to [trackers].
  static Uint8List build(Uint8List info, {List<String> trackers = const []}) {
    final unique = <String>{
      for (final t in trackers)
        if (t.trim().isNotEmpty) t.trim(),
    }.toList();
    final out = BytesBuilder(copy: false)..addByte(0x64); // d
    // Keys in sorted order, as bencode requires: announce, announce-list, info.
    if (unique.isNotEmpty) {
      out
        ..add(_string('announce'))
        ..add(_string(unique.first))
        ..add(_string('announce-list'))
        ..addByte(0x6c); // l
      for (final t in unique) {
        out
          ..addByte(0x6c)
          ..add(_string(t))
          ..addByte(0x65);
      }
      out.addByte(0x65);
    }
    out
      ..add(_string('info'))
      ..add(info)
      ..addByte(0x65); // e
    return out.toBytes();
  }

  /// The bencoded info dictionary inside [torrentFile], exactly as it is
  /// stored there, or null when the file is not a torrent.
  static Uint8List? infoOf(Uint8List torrentFile) {
    try {
      if (torrentFile.isEmpty || torrentFile[0] != 0x64) return null;
      var i = 1;
      while (i < torrentFile.length && torrentFile[i] != 0x65) {
        final keyEnd = _skip(torrentFile, i);
        final key = utf8.decode(
          torrentFile.sublist(torrentFile.indexOf(0x3a, i) + 1, keyEnd),
          allowMalformed: true,
        );
        final valueEnd = _skip(torrentFile, keyEnd);
        if (key == 'info') {
          return Uint8List.sublistView(torrentFile, keyEnd, valueEnd);
        }
        i = valueEnd;
      }
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
    return null;
  }

  /// Whether [info] is the info dictionary of the torrent [infoHashHex].
  static bool matches(Uint8List info, String infoHashHex) =>
      sha1.convert(info).toString() == infoHashHex.trim().toLowerCase();

  /// The trackers (`tr`) of a magnet link.
  static List<String> trackersOf(String? magnet) {
    if (magnet == null || magnet.trim().isEmpty) return const [];
    try {
      return Uri.parse(magnet.trim()).queryParametersAll['tr'] ?? const [];
    } on FormatException {
      return const [];
    }
  }

  static List<int> _string(String value) {
    final bytes = utf8.encode(value);
    return [...ascii.encode('${bytes.length}:'), ...bytes];
  }

  /// The index just past the bencoded value that starts at [i].
  static int _skip(Uint8List b, int i) {
    final c = b[i];
    if (c == 0x69) {
      // i<n>e
      final end = b.indexOf(0x65, i);
      if (end < 0) throw const FormatException('unterminated integer');
      return end + 1;
    }
    if (c == 0x6c || c == 0x64) {
      // l...e or d...e
      var j = i + 1;
      while (b[j] != 0x65) {
        j = _skip(b, j);
      }
      return j + 1;
    }
    if (c >= 0x30 && c <= 0x39) {
      final colon = b.indexOf(0x3a, i);
      if (colon < 0) throw const FormatException('bad string length');
      final length = int.parse(ascii.decode(b.sublist(i, colon)));
      final end = colon + 1 + length;
      if (end > b.length) throw const FormatException('truncated string');
      return end;
    }
    throw FormatException('unexpected byte $c');
  }
}
