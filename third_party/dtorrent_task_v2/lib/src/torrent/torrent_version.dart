import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:logging/logging.dart';
import 'torrent_model.dart';

/// BitTorrent protocol version
enum TorrentVersion {
  /// BitTorrent v1 (BEP 0003) - uses SHA-1, 20-byte info hash
  v1,

  /// BitTorrent v2 (BEP 52) - uses SHA-256, 32-byte info hash
  v2,

  /// Hybrid torrent - supports both v1 and v2
  hybrid,
}

var _log = Logger('TorrentVersionHelper');

/// Helper class for working with torrent versions
class TorrentVersionHelper {
  /// Determine torrent version from TorrentModel object
  ///
  /// TorrentModel already has the version field, so we can return it directly
  static TorrentVersion detectVersion(TorrentModel torrent) {
    return torrent.version;
  }

  /// Detect version from raw bencoded torrent data
  ///
  /// This method can be used when you have access to the raw torrent file bytes
  static TorrentVersion detectVersionFromBytes(Uint8List torrentBytes) {
    try {
      final decoded = decode(torrentBytes);
      if (decoded is! Map) {
        return TorrentVersion.v1;
      }

      final info = decoded['info'];
      if (info is! Map) {
        return TorrentVersion.v1;
      }

      // Check meta version field
      final metaVersion = info['meta version'];
      final hasFileTree = info.containsKey('file tree');
      final hasPieces = info.containsKey('pieces');
      final hasPieceLayers = decoded.containsKey('piece layers');

      // v2 torrent: meta version == 2, has file tree
      if (metaVersion == 2 && hasFileTree) {
        // Check if it's hybrid (has both v1 and v2 structures)
        if (hasPieces && hasPieceLayers) {
          return TorrentVersion.hybrid;
        }
        return TorrentVersion.v2;
      }

      // v1 torrent: has pieces, no meta version or meta version != 2
      if (hasPieces && (metaVersion == null || metaVersion != 2)) {
        return TorrentVersion.v1;
      }

      // Default to v1 for compatibility
      return TorrentVersion.v1;
    } catch (e) {
      _log.warning('Failed to detect version from bytes, defaulting to v1', e);
      return TorrentVersion.v1;
    }
  }

  /// Extract file tree from decoded torrent data
  static Map<String, dynamic>? getFileTree(dynamic decodedTorrent) {
    if (decodedTorrent is! Map) {
      return null;
    }

    final info = decodedTorrent['info'];
    if (info is! Map) {
      return null;
    }

    final fileTree = info['file tree'];
    if (fileTree is Map) {
      return fileTree as Map<String, dynamic>;
    }

    return null;
  }

  /// Extract piece layers from decoded torrent data
  static Map<dynamic, dynamic>? getPieceLayers(dynamic decodedTorrent) {
    if (decodedTorrent is! Map) {
      return null;
    }

    final pieceLayers = decodedTorrent['piece layers'];
    if (pieceLayers is Map) {
      return pieceLayers;
    }

    return null;
  }

  /// Detect version from torrent file path
  static Future<TorrentVersion> detectVersionFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _log.warning('Torrent file does not exist: $filePath');
        return TorrentVersion.v1;
      }

      final bytes = await file.readAsBytes();
      return detectVersionFromBytes(bytes);
    } catch (e) {
      _log.warning('Failed to detect version from file: $filePath', e);
      return TorrentVersion.v1;
    }
  }

  /// Get info hash for a specific version from TorrentModel
  static Uint8List? getInfoHashForVersion(
      TorrentModel torrent, TorrentVersion version) {
    switch (version) {
      case TorrentVersion.v1:
        return torrent.v1InfoHash;
      case TorrentVersion.v2:
        return torrent.v2InfoHash;
      case TorrentVersion.hybrid:
        // Hybrid torrents can use either v1 or v2 info hash
        // Return v1 by default for compatibility
        return torrent.v1InfoHash ?? torrent.v2InfoHash;
    }
  }

  /// Calculate v2 info hash (SHA-256) from bencoded info dictionary
  ///
  /// According to BEP 52, v2 info hash is SHA-256 of the bencoded info dict
  static Uint8List? calculateV2InfoHash(Uint8List infoDictBytes) {
    try {
      final hash = sha256.convert(infoDictBytes);
      return Uint8List.fromList(hash.bytes);
    } catch (e) {
      _log.warning('Failed to calculate v2 info hash', e);
      return null;
    }
  }

  /// Calculate v2 info hash from decoded info dictionary
  ///
  /// Re-encodes the info dict and calculates SHA-256
  static Uint8List? calculateV2InfoHashFromDict(Map<String, dynamic> infoDict) {
    try {
      final encoded = encode(infoDict);
      return calculateV2InfoHash(encoded);
    } catch (e) {
      _log.warning('Failed to calculate v2 info hash from dict', e);
      return null;
    }
  }

  /// Get truncated info hash for tracker (20 bytes)
  ///
  /// According to BEP 52, trackers use 20-byte truncated v2 info hash
  static Uint8List? getTruncatedInfoHash(Uint8List fullHash) {
    if (fullHash.length >= 20) {
      return fullHash.sublist(0, 20);
    }
    return null;
  }

  /// Check if info hash is v2 (32 bytes)
  static bool isV2InfoHash(Uint8List infoHash) {
    return infoHash.length == 32;
  }

  /// Check if info hash is v1 (20 bytes)
  static bool isV1InfoHash(Uint8List infoHash) {
    return infoHash.length == 20;
  }

  /// Get piece hash length for a version
  static int getPieceHashLength(TorrentVersion version) {
    switch (version) {
      case TorrentVersion.v1:
        return 20; // SHA-1
      case TorrentVersion.v2:
        return 32; // SHA-256
      case TorrentVersion.hybrid:
        // Hybrid can use either, default to v1 for compatibility
        return 20;
    }
  }

  /// Get hash algorithm for a version
  static Hash getHashAlgorithm(TorrentVersion version) {
    switch (version) {
      case TorrentVersion.v1:
        return sha1;
      case TorrentVersion.v2:
        return sha256;
      case TorrentVersion.hybrid:
        // Hybrid can use either, default to v1 for compatibility
        return sha1;
    }
  }
}
