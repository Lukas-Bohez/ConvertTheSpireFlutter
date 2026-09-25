import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:logging/logging.dart';

var _log = Logger('TorrentCreator');

/// Configuration for creating a torrent file
class TorrentCreationOptions {
  /// Piece length in bytes (default: 256KB)
  final int pieceLength;

  /// Trackers (announce URLs)
  final List<Uri> trackers;

  /// Comment for the torrent
  final String? comment;

  /// Created by field
  final String? createdBy;

  /// Creation date (Unix timestamp)
  final int? creationDate;

  /// Source field (for private trackers)
  final String? source;

  /// Private flag (for private trackers)
  final bool isPrivate;

  TorrentCreationOptions({
    this.pieceLength = 262144, // 256KB
    List<Uri>? trackers,
    this.comment,
    this.createdBy,
    this.creationDate,
    this.source,
    this.isPrivate = false,
  }) : trackers = trackers ?? [];
}

/// Creator for .torrent files
class TorrentCreator {
  /// Create a torrent file from a directory or single file
  ///
  /// [path] - path to file or directory
  /// [options] - creation options
  ///
  /// Returns the created Torrent model
  static Future<TorrentModel> createTorrent(
    String path,
    TorrentCreationOptions options,
  ) async {
    final file = File(path);
    final directory = Directory(path);

    if (await file.exists()) {
      return await _createSingleFileTorrent(file, options);
    } else if (await directory.exists()) {
      return await _createMultiFileTorrent(directory, options);
    } else {
      throw ArgumentError('Path does not exist: $path');
    }
  }

  /// Create torrent for a single file
  static Future<TorrentModel> _createSingleFileTorrent(
    File file,
    TorrentCreationOptions options,
  ) async {
    _log.info('Creating torrent for single file: ${file.path}');

    final fileName = file.path.split(Platform.pathSeparator).last;
    final fileLength = await file.length();
    final pieces = await _calculatePieces(file, options.pieceLength);

    // Build info dictionary
    final info = <String, dynamic>{
      'name': fileName,
      'piece length': options.pieceLength,
      'pieces': pieces,
      'length': fileLength,
    };

    if (options.isPrivate) {
      info['private'] = 1;
    }

    if (options.source != null) {
      info['source'] = options.source;
    }

    // Build announce list
    final announceList = <List<String>>[];
    for (final tracker in options.trackers) {
      announceList.add([tracker.toString()]);
    }

    // Build torrent dictionary
    final torrent = <String, dynamic>{
      'info': info,
    };

    if (announceList.isNotEmpty) {
      if (announceList.length == 1) {
        torrent['announce'] = announceList[0][0];
      }
      torrent['announce-list'] = announceList;
    }

    if (options.comment != null) {
      torrent['comment'] = options.comment!;
    }

    if (options.createdBy != null) {
      torrent['created by'] = options.createdBy!;
    }

    torrent['creation date'] =
        options.creationDate ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    torrent['encoding'] = 'UTF-8';

    // Save to temporary file and parse it
    final tempFile = File(
        '${Directory.systemTemp.path}/torrent_${DateTime.now().millisecondsSinceEpoch}.torrent');
    final encoded = encode(torrent);
    await tempFile.writeAsBytes(encoded);
    final parsed = await TorrentModel.parse(tempFile.path);
    // Clean up temp file if it still exists
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      // Ignore errors when deleting temp file
    }
    return parsed;
  }

  /// Create torrent for multiple files (directory)
  static Future<TorrentModel> _createMultiFileTorrent(
    Directory directory,
    TorrentCreationOptions options,
  ) async {
    _log.info('Creating torrent for directory: ${directory.path}');

    final files = await _getAllFiles(directory);
    if (files.isEmpty) {
      throw ArgumentError('Directory is empty: ${directory.path}');
    }

    final directoryName = directory.path.split(Platform.pathSeparator).last;
    final fileList = <Map<String, dynamic>>[];

    // Calculate pieces for all files
    final allPieces = <int>[];
    for (final file in files) {
      final relativePath = _getRelativePath(file, directory);
      final fileLength = await file.length();

      fileList.add({
        'length': fileLength,
        'path': relativePath.split(Platform.pathSeparator),
      });

      // Calculate pieces for this file
      final filePieces = await _calculatePieces(file, options.pieceLength);
      allPieces.addAll(filePieces.toList());
    }

    // Build info dictionary
    final info = <String, dynamic>{
      'name': directoryName,
      'piece length': options.pieceLength,
      'pieces': Uint8List.fromList(allPieces),
      'files': fileList,
    };

    if (options.isPrivate) {
      info['private'] = 1;
    }

    if (options.source != null) {
      info['source'] = options.source;
    }

    // Build announce list
    final announceList = <List<String>>[];
    for (final tracker in options.trackers) {
      announceList.add([tracker.toString()]);
    }

    // Build torrent dictionary
    final torrent = <String, dynamic>{
      'info': info,
    };

    if (announceList.isNotEmpty) {
      if (announceList.length == 1) {
        torrent['announce'] = announceList[0][0];
      }
      torrent['announce-list'] = announceList;
    }

    if (options.comment != null) {
      torrent['comment'] = options.comment!;
    }

    if (options.createdBy != null) {
      torrent['created by'] = options.createdBy!;
    }

    torrent['creation date'] =
        options.creationDate ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    torrent['encoding'] = 'UTF-8';

    // Save to temporary file and parse it
    final tempFile = File(
        '${Directory.systemTemp.path}/torrent_${DateTime.now().millisecondsSinceEpoch}.torrent');
    final encoded = encode(torrent);
    await tempFile.writeAsBytes(encoded);
    final parsed = await TorrentModel.parse(tempFile.path);
    // Clean up temp file if it still exists
    try {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      // Ignore errors when deleting temp file
    }
    return parsed;
  }

  /// Calculate SHA1 hashes for all pieces in a file
  static Future<Uint8List> _calculatePieces(
    File file,
    int pieceLength,
  ) async {
    final pieces = <int>[];
    final randomAccess = await file.open();
    final fileLength = await file.length();

    int position = 0;
    while (position < fileLength) {
      final remaining = fileLength - position;
      final currentPieceLength =
          remaining < pieceLength ? remaining : pieceLength;

      await randomAccess.setPosition(position);
      final pieceData = await randomAccess.read(currentPieceLength);
      final hash = sha1.convert(pieceData).bytes;
      pieces.addAll(hash);

      position += currentPieceLength;
    }

    await randomAccess.close();
    return Uint8List.fromList(pieces);
  }

  /// Get all files in a directory recursively
  static Future<List<File>> _getAllFiles(Directory directory) async {
    final files = <File>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        files.add(entity);
      }
    }
    return files;
  }

  /// Get relative path from file to directory
  static String _getRelativePath(File file, Directory directory) {
    final filePath = file.absolute.path;
    final dirPath = directory.absolute.path;
    if (!filePath.startsWith(dirPath)) {
      throw ArgumentError('File is not in directory: $filePath');
    }
    return filePath.substring(dirPath.length + 1);
  }

  /// Save torrent to file
  ///
  /// Note: This method requires access to the original torrent file or bencoded data
  /// For newly created torrents, use the return value from createTorrent and save it directly
  static Future<void> saveTorrent(
      Map<String, dynamic> torrentMap, String outputPath) async {
    final file = File(outputPath);
    final encoded = encode(torrentMap);
    await file.writeAsBytes(encoded);
    _log.info('Torrent saved to: $outputPath');
  }
}
