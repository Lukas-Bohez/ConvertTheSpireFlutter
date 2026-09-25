import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'torrent_file_model.dart';
import 'file_tree.dart';
import 'torrent_version.dart';
import 'torrent_parser.dart';

/// Main torrent model with full support for BEP 3 (v1) and BEP 52 (v2)
///
/// This class replaces the Torrent class from dtorrent_parser and provides
/// full support for BitTorrent v2 (BEP 52) including file tree, piece layers,
/// and meta version fields.
class TorrentModel {
  /// Torrent name
  final String name;

  /// Files in the torrent (v1 format)
  final List<TorrentFileModel> files;

  /// Info hash buffer (20 bytes for v1, 32 bytes for v2)
  final Uint8List infoHashBuffer;

  /// Info hash as hex string
  String get infoHash {
    return infoHashBuffer
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Piece length in bytes
  final int pieceLength;

  /// Piece hashes (v1 format - SHA-1, 20 bytes each)
  final List<Uint8List>? pieces;

  /// Announce URLs (trackers)
  final List<Uri> announces;

  /// DHT nodes
  final List<Uri> nodes;

  /// Total length (for single-file torrents)
  final int? length;

  /// Torrent version (v1, v2, or hybrid)
  final TorrentVersion version;

  /// Meta version field from info dict (2 for v2, null for v1)
  final int? metaVersion;

  /// File tree structure (v2 format, BEP 52)
  final Map<String, FileTreeEntry>? fileTree;

  /// Piece layers (v2 format, BEP 52)
  /// Maps piece root hash to piece layer data
  final Map<String, Uint8List>? pieceLayers;

  /// Root hash for v2 torrents (32-byte SHA-256)
  final Uint8List? rootHash;

  /// Raw bencoded info dictionary (for v2 info hash calculation)
  final Uint8List? infoDictBytes;

  /// Raw bencoded torrent data
  final Map<String, dynamic>? rawData;

  TorrentModel({
    required this.name,
    required this.files,
    required this.infoHashBuffer,
    required this.pieceLength,
    this.pieces,
    required this.announces,
    required this.nodes,
    this.length,
    required this.version,
    this.metaVersion,
    this.fileTree,
    this.pieceLayers,
    this.rootHash,
    this.infoDictBytes,
    this.rawData,
  });

  /// Get total size of all files
  int get totalSize {
    if (length != null) {
      return length!;
    }
    return files.fold<int>(0, (sum, file) => sum + file.length);
  }

  /// Check if this is a single-file torrent
  bool get isSingleFile => files.length == 1;

  /// Length of the last piece (may be smaller than pieceLength)
  int get lastPieceLength {
    if (pieces == null || pieces!.isEmpty) {
      return pieceLength;
    }
    final totalSize = this.totalSize;
    final remainder = totalSize % pieceLength;
    return remainder == 0 ? pieceLength : remainder;
  }

  /// Get v1 info hash (20 bytes, SHA-1)
  Uint8List? get v1InfoHash {
    if (version == TorrentVersion.v1 || version == TorrentVersion.hybrid) {
      // For v1, infoHashBuffer is the v1 hash
      if (infoHashBuffer.length == 20) {
        return infoHashBuffer;
      }
    }
    return null;
  }

  /// Get v2 info hash (32 bytes, SHA-256)
  Uint8List? get v2InfoHash {
    if (version == TorrentVersion.v2 || version == TorrentVersion.hybrid) {
      if (infoHashBuffer.length == 32) {
        return infoHashBuffer;
      }
      // If we have infoDictBytes, calculate v2 hash
      if (infoDictBytes != null) {
        final hash = sha256.convert(infoDictBytes!);
        return Uint8List.fromList(hash.bytes);
      }
    }
    return null;
  }

  /// Get truncated info hash for tracker (20 bytes)
  /// According to BEP 52, trackers use 20-byte truncated v2 info hash
  Uint8List get truncatedInfoHash {
    if (infoHashBuffer.length >= 20) {
      return infoHashBuffer.sublist(0, 20);
    }
    return infoHashBuffer;
  }

  /// Parse a torrent file from disk
  ///
  /// This is a convenience method for backward compatibility with Torrent.parse()
  static Future<TorrentModel> parse(String filePath) {
    return TorrentParser.parse(filePath);
  }

  @override
  String toString() {
    return 'TorrentModel(name: $name, version: $version, files: ${files.length}, '
        'size: $totalSize, pieces: ${pieces?.length ?? 0})';
  }
}
