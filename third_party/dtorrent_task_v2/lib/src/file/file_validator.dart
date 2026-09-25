import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:logging/logging.dart';
import '../piece/piece.dart';

var _log = Logger('FileValidator');

/// Result of file validation
class FileValidationResult {
  final bool isValid;
  final List<int> invalidPieces;
  final String? error;
  final int validatedBytes;
  final int totalBytes;

  FileValidationResult({
    required this.isValid,
    this.invalidPieces = const [],
    this.error,
    required this.validatedBytes,
    required this.totalBytes,
  });

  double get progress => totalBytes > 0 ? validatedBytes / totalBytes : 0.0;
}

/// Validates downloaded files against torrent piece hashes
class FileValidator {
  final TorrentModel metainfo;
  final List<Piece> pieces;
  final String savePath;

  FileValidator(this.metainfo, this.pieces, this.savePath);

  /// Validate all files in the torrent
  Future<FileValidationResult> validateAll() async {
    try {
      final invalidPieces = <int>[];
      var validatedBytes = 0;
      var totalBytes = 0;

      for (var i = 0; i < pieces.length; i++) {
        final piece = pieces[i];
        totalBytes += piece.byteLength;

        final isValid = await validatePiece(i);
        if (isValid) {
          validatedBytes += piece.byteLength;
        } else {
          invalidPieces.add(i);
          _log.warning('Piece $i failed validation');
        }
      }

      return FileValidationResult(
        isValid: invalidPieces.isEmpty,
        invalidPieces: invalidPieces,
        validatedBytes: validatedBytes,
        totalBytes: totalBytes,
      );
    } catch (e, stackTrace) {
      _log.severe('File validation error', e, stackTrace);
      return FileValidationResult(
        isValid: false,
        error: e.toString(),
        validatedBytes: 0,
        totalBytes: metainfo.length ?? metainfo.totalSize,
      );
    }
  }

  /// Validate a specific piece
  Future<bool> validatePiece(int pieceIndex) async {
    if (pieceIndex < 0 || pieceIndex >= pieces.length) {
      return false;
    }

    final piece = pieces[pieceIndex];
    if (!piece.isCompletelyWritten) {
      return false;
    }

    try {
      final piece = pieces[pieceIndex];

      // Read piece data from files
      final pieceData = await _readPieceData(pieceIndex);
      if (pieceData.length != piece.byteLength) {
        return false;
      }

      // Calculate hash
      final hash = _calculatePieceHash(pieceData);

      // Compare with expected hash
      // The piece object already has hashString, so we'll use that
      final expectedHashString = piece.hashString;

      // Convert hashString to bytes (it's hex string)
      final expectedHashBytes = _hexStringToBytes(expectedHashString);
      return _compareHashes(hash, expectedHashBytes);
    } catch (e) {
      _log.warning('Error validating piece $pieceIndex', e);
      return false;
    }
  }

  /// Validate specific files
  Future<FileValidationResult> validateFiles(List<String> filePaths) async {
    try {
      final invalidPieces = <int>[];
      var validatedBytes = 0;
      var totalBytes = 0;

      // Find pieces that belong to these files
      final piecesToValidate = <int>{};
      for (var filePath in filePaths) {
        final relativePath = filePath.replaceFirst(savePath, '');
        for (var i = 0; i < metainfo.files.length; i++) {
          final file = metainfo.files[i];
          if (file.path == relativePath || file.path.endsWith(relativePath)) {
            final startPiece = file.offset ~/ metainfo.pieceLength;
            final endPiece =
                (file.offset + file.length) ~/ metainfo.pieceLength;
            for (var j = startPiece; j <= endPiece; j++) {
              piecesToValidate.add(j);
            }
            break;
          }
        }
      }

      for (var pieceIndex in piecesToValidate) {
        if (pieceIndex >= pieces.length) continue;
        final piece = pieces[pieceIndex];
        totalBytes += piece.byteLength;

        final isValid = await validatePiece(pieceIndex);
        if (isValid) {
          validatedBytes += piece.byteLength;
        } else {
          invalidPieces.add(pieceIndex);
        }
      }

      return FileValidationResult(
        isValid: invalidPieces.isEmpty,
        invalidPieces: invalidPieces,
        validatedBytes: validatedBytes,
        totalBytes: totalBytes,
      );
    } catch (e, stackTrace) {
      _log.severe('File validation error', e, stackTrace);
      return FileValidationResult(
        isValid: false,
        error: e.toString(),
        validatedBytes: 0,
        totalBytes: 0,
      );
    }
  }

  /// Read piece data from files
  Future<Uint8List> _readPieceData(int pieceIndex) async {
    final piece = pieces[pieceIndex];
    final pieceStart = pieceIndex * metainfo.pieceLength;
    final pieceEnd = pieceStart + piece.byteLength;
    final data = Uint8List(piece.byteLength);
    var offset = 0;

    // Find which files contain this piece
    for (var file in metainfo.files) {
      final fileStart = file.offset;
      final fileEnd = file.offset + file.length;

      if (pieceStart < fileEnd && pieceEnd > fileStart) {
        final readStart = pieceStart > fileStart ? pieceStart - fileStart : 0;
        final readEnd = pieceEnd < fileEnd ? pieceEnd - fileStart : file.length;
        final readLength = readEnd - readStart;

        final filePath = '$savePath${file.path}';
        final fileObj = File(filePath);
        if (await fileObj.exists()) {
          final access = await fileObj.open(mode: FileMode.read);
          await access.setPosition(readStart);
          final bytes = await access.read(readLength);
          data.setRange(offset, offset + bytes.length, bytes);
          offset += bytes.length;
          await access.close();
        } else {
          throw Exception('File not found: $filePath');
        }
      }
    }

    return data;
  }

  /// Calculate SHA1 hash of piece data
  Uint8List _calculatePieceHash(Uint8List data) {
    final digest = sha1.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// Compare two hashes
  bool _compareHashes(Uint8List hash1, Uint8List hash2) {
    if (hash1.length != hash2.length) return false;
    for (var i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) return false;
    }
    return true;
  }

  /// Convert hex string to bytes
  Uint8List _hexStringToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Quick validation - check if files exist and have correct sizes
  Future<bool> quickValidate() async {
    try {
      for (var file in metainfo.files) {
        final filePath = '$savePath${file.path}';
        final fileObj = File(filePath);

        if (!await fileObj.exists()) {
          _log.warning('File missing: $filePath');
          return false;
        }

        final stat = await fileObj.stat();
        if (stat.size != file.length) {
          _log.warning(
              'File size mismatch: $filePath (expected: ${file.length}, actual: ${stat.size})');
          return false;
        }
      }
      return true;
    } catch (e) {
      _log.warning('Quick validation error', e);
      return false;
    }
  }
}
