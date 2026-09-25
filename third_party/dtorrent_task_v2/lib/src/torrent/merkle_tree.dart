import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

var _log = Logger('MerkleTree');

/// Helper class for Merkle tree operations (BEP 52)
///
/// Merkle tree is used in v2 torrents for file validation.
/// Each file has a Merkle tree with:
/// - Leaf nodes: 16KiB blocks of the file (SHA-256 hashed)
/// - Internal nodes: SHA-256 of concatenated child hashes
/// - Root: pieces root (32-byte SHA-256 hash)
class MerkleTreeHelper {
  /// Calculate Merkle tree root from file data
  ///
  /// [fileData] - file content
  /// [blockSize] - size of each block (default 16KiB for v2)
  static Uint8List calculateRoot(Uint8List fileData,
      {int blockSize = 16 * 1024}) {
    if (fileData.isEmpty) {
      // Empty file has zero root
      return Uint8List(32);
    }

    // Calculate leaf hashes (one per block)
    final leafHashes = <Uint8List>[];
    for (var i = 0; i < fileData.length; i += blockSize) {
      final end =
          (i + blockSize < fileData.length) ? i + blockSize : fileData.length;
      final block = fileData.sublist(i, end);

      // Pad last block if needed (but don't hash padding)
      final hash = sha256.convert(block);
      leafHashes.add(Uint8List.fromList(hash.bytes));
    }

    // Build tree bottom-up
    return _buildTree(leafHashes);
  }

  /// Build Merkle tree from leaf hashes
  static Uint8List _buildTree(List<Uint8List> hashes) {
    if (hashes.isEmpty) {
      return Uint8List(32);
    }

    if (hashes.length == 1) {
      return hashes[0];
    }

    // Build next level
    final nextLevel = <Uint8List>[];
    for (var i = 0; i < hashes.length; i += 2) {
      if (i + 1 < hashes.length) {
        // Pair of hashes
        final combined = Uint8List(64);
        combined.setRange(0, 32, hashes[i]);
        combined.setRange(32, 64, hashes[i + 1]);
        final hash = sha256.convert(combined);
        nextLevel.add(Uint8List.fromList(hash.bytes));
      } else {
        // Odd number, hash with zero
        final combined = Uint8List(64);
        combined.setRange(0, 32, hashes[i]);
        // Right half is zero (already initialized)
        final hash = sha256.convert(combined);
        nextLevel.add(Uint8List.fromList(hash.bytes));
      }
    }

    return _buildTree(nextLevel);
  }

  /// Validate file data against pieces root
  ///
  /// [fileData] - file content to validate
  /// [piecesRoot] - expected root hash (32 bytes)
  /// [blockSize] - size of each block (default 16KiB)
  static bool validateFile(Uint8List fileData, Uint8List piecesRoot,
      {int blockSize = 16 * 1024}) {
    if (piecesRoot.length != 32) {
      _log.warning('Invalid pieces root length: ${piecesRoot.length}');
      return false;
    }

    final calculatedRoot = calculateRoot(fileData, blockSize: blockSize);
    return _hashesEqual(calculatedRoot, piecesRoot);
  }

  /// Validate piece data against piece hash from piece layers
  ///
  /// [pieceData] - piece content
  /// [expectedHash] - expected hash from piece layers (32 bytes)
  static bool validatePiece(Uint8List pieceData, Uint8List expectedHash) {
    if (expectedHash.length != 32) {
      _log.warning('Invalid piece hash length: ${expectedHash.length}');
      return false;
    }

    final calculatedHash = sha256.convert(pieceData);
    final hashBytes = Uint8List.fromList(calculatedHash.bytes);
    return _hashesEqual(hashBytes, expectedHash);
  }

  /// Calculate layer hashes for a specific layer
  ///
  /// [fileData] - file content
  /// [layer] - layer number (0 = leaf layer, 1 = first parent layer, etc.)
  /// [blockSize] - size of each block
  static List<Uint8List>? calculateLayerHashes(Uint8List fileData, int layer,
      {int blockSize = 16 * 1024}) {
    if (layer < 0) {
      return null;
    }

    // Start with leaf hashes
    var currentHashes = <Uint8List>[];
    for (var i = 0; i < fileData.length; i += blockSize) {
      final end =
          (i + blockSize < fileData.length) ? i + blockSize : fileData.length;
      final block = fileData.sublist(i, end);
      final hash = sha256.convert(block);
      currentHashes.add(Uint8List.fromList(hash.bytes));
    }

    // Build up to requested layer
    for (var l = 0; l < layer; l++) {
      final nextLevel = <Uint8List>[];
      for (var i = 0; i < currentHashes.length; i += 2) {
        if (i + 1 < currentHashes.length) {
          final combined = Uint8List(64);
          combined.setRange(0, 32, currentHashes[i]);
          combined.setRange(32, 64, currentHashes[i + 1]);
          final hash = sha256.convert(combined);
          nextLevel.add(Uint8List.fromList(hash.bytes));
        } else {
          final combined = Uint8List(64);
          combined.setRange(0, 32, currentHashes[i]);
          final hash = sha256.convert(combined);
          nextLevel.add(Uint8List.fromList(hash.bytes));
        }
      }
      currentHashes = nextLevel;
    }

    return currentHashes;
  }

  /// Helper to compare two hashes
  static bool _hashesEqual(Uint8List hash1, Uint8List hash2) {
    if (hash1.length != hash2.length) {
      return false;
    }

    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) {
        return false;
      }
    }

    return true;
  }

  /// Get layer number for piece size
  ///
  /// For v2, piece size determines which layer of Merkle tree to use
  /// - 16KiB piece size: leaf layer (layer 0)
  /// - 32KiB piece size: layer 1
  /// - 64KiB piece size: layer 2
  /// - etc.
  static int getLayerForPieceSize(int pieceSize, {int blockSize = 16 * 1024}) {
    if (pieceSize < blockSize) {
      return 0;
    }

    var layer = 0;
    var currentSize = blockSize;
    while (currentSize < pieceSize) {
      currentSize *= 2;
      layer++;
    }

    return layer;
  }
}
