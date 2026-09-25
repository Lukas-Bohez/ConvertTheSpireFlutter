import 'dart:typed_data';
import 'package:logging/logging.dart';

var _log = Logger('PieceLayers');

/// Helper class for working with piece layers (BEP 52)
///
/// Piece layers is a dictionary where:
/// - Keys are pieces root hashes (32 bytes, stored as binary strings)
/// - Values are concatenated hashes from the appropriate layer of Merkle tree
class PieceLayersHelper {
  /// Parse piece layers from bencoded dictionary
  ///
  /// Piece layers structure:
  /// {
  ///   `pieces_root_1`: `concatenated_hashes_1`,
  ///   `pieces_root_2`: `concatenated_hashes_2`,
  ///   ...
  /// }
  static Map<Uint8List, Uint8List>? parsePieceLayers(dynamic pieceLayersData) {
    if (pieceLayersData is! Map) {
      return null;
    }

    final result = <Uint8List, Uint8List>{};

    for (var entry in pieceLayersData.entries) {
      final key = entry.key;
      final value = entry.value;

      Uint8List? piecesRoot;
      Uint8List? hashes;

      // Key should be a 32-byte pieces root
      if (key is Uint8List) {
        piecesRoot = key;
      } else if (key is List<int>) {
        piecesRoot = Uint8List.fromList(key);
      } else {
        _log.warning('Invalid pieces root type: ${key.runtimeType}');
        continue;
      }

      if (piecesRoot.length != 32) {
        _log.warning(
            'Invalid pieces root length: ${piecesRoot.length}, expected 32');
        continue;
      }

      // Value should be concatenated hashes
      if (value is Uint8List) {
        hashes = value;
      } else if (value is List<int>) {
        hashes = Uint8List.fromList(value);
      } else {
        _log.warning('Invalid hashes type: ${value.runtimeType}');
        continue;
      }

      result[piecesRoot] = hashes;
    }

    return result.isEmpty ? null : result;
  }

  /// Get piece hashes for a specific file's pieces root
  static Uint8List? getPieceHashesForFile(
      Map<Uint8List, Uint8List> pieceLayers, Uint8List piecesRoot) {
    return pieceLayers[piecesRoot];
  }

  /// Extract individual piece hash from concatenated hashes
  ///
  /// [hashes] - concatenated hashes from piece layers
  /// [index] - piece index (0-based)
  /// [hashLength] - length of each hash (32 bytes for SHA-256 in v2)
  static Uint8List? getPieceHash(Uint8List hashes, int index, int hashLength) {
    final offset = index * hashLength;
    if (offset + hashLength > hashes.length) {
      return null;
    }
    return hashes.sublist(offset, offset + hashLength);
  }

  /// Get all piece hashes for a file
  static List<Uint8List> getAllPieceHashes(Uint8List hashes, int hashLength) {
    final result = <Uint8List>[];
    final count = hashes.length ~/ hashLength;

    for (var i = 0; i < count; i++) {
      final hash = getPieceHash(hashes, i, hashLength);
      if (hash != null) {
        result.add(hash);
      }
    }

    return result;
  }

  /// Validate piece layers structure
  static bool validatePieceLayers(Map<Uint8List, Uint8List> pieceLayers) {
    for (var entry in pieceLayers.entries) {
      if (entry.key.length != 32) {
        _log.warning('Invalid pieces root length: ${entry.key.length}');
        return false;
      }

      // Hashes should be multiple of 32 (SHA-256 hash length)
      if (entry.value.length % 32 != 0) {
        _log.warning(
            'Invalid hashes length: ${entry.value.length}, must be multiple of 32');
        return false;
      }
    }

    return true;
  }
}
