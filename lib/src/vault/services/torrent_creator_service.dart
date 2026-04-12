import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class TorrentCreationResult {
  final String torrentPath;
  final int pieceLength;
  final int pieceCount;
  final int totalSize;

  const TorrentCreationResult({
    required this.torrentPath,
    required this.pieceLength,
    required this.pieceCount,
    required this.totalSize,
  });
}

class TorrentCreatorService {
  TorrentCreatorService._();
  static final TorrentCreatorService instance = TorrentCreatorService._();

  static const List<String> defaultTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.tracker.cl:1337/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://open.stealth.si:80/announce',
  ];

  int autoPieceSize(int totalSize) {
    const mb = 1024 * 1024;
    const gb = 1024 * mb;
    if (totalSize < 64 * mb) return 256 * 1024;
    if (totalSize < 512 * mb) return 512 * 1024;
    if (totalSize < 2 * gb) return 1024 * 1024;
    if (totalSize < 8 * gb) return 2 * 1024 * 1024;
    return 4 * 1024 * 1024;
  }

  Future<List<Map<String, Object>>> collectEntries({
    required List<String> filePaths,
    required List<String> directoryPaths,
  }) async {
    final entries = <Map<String, Object>>[];

    for (final filePath in filePaths) {
      final file = File(filePath);
      if (!await file.exists()) continue;
      final stat = await file.stat();
      entries.add({
        'path': file.path,
        'relativePath': p.basename(file.path),
        'length': stat.size,
      });
    }

    for (final directoryPath in directoryPaths) {
      final root = Directory(directoryPath);
      if (!await root.exists()) continue;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        entries.add({
          'path': entity.path,
          'relativePath': p.relative(entity.path, from: root.path),
          'length': stat.size,
        });
      }
    }

    entries.sort((a, b) {
      final ap = a['relativePath']! as String;
      final bp = b['relativePath']! as String;
      return ap.compareTo(bp);
    });

    return entries;
  }

  Future<TorrentCreationResult> createTorrent({
    required List<Map<String, Object>> entries,
    required String torrentName,
    required List<String> trackers,
    required bool isPrivate,
    required String outputDirectory,
    String comment = '',
    int? selectedPieceSize,
    void Function(double progress, String message)? onProgress,
    bool addToDownloads = false,
  }) async {
    if (entries.isEmpty) {
      throw StateError('No files selected.');
    }

    final totalSize = entries.fold<int>(
      0,
      (sum, e) => sum + (e['length']! as int),
    );
    final pieceLength = selectedPieceSize ?? autoPieceSize(totalSize);

    final outDir = Directory(outputDirectory);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    final writableProbe = File(p.join(outDir.path, '.write_probe.tmp'));
    try {
      await writableProbe.writeAsString('probe', flush: true);
    } finally {
      if (await writableProbe.exists()) {
        await writableProbe.delete();
      }
    }

    final receivePort = ReceivePort();
    final completer = Completer<Map<String, Object>>();

    receivePort.listen((message) {
      if (message is Map) {
        final type = message['type'];
        if (type == 'progress') {
          final progress = (message['progress'] as num?)?.toDouble() ?? 0.0;
          final detail = (message['message'] as String?) ?? 'Hashing...';
          onProgress?.call(progress, detail);
        }
        if (type == 'result') {
          completer.complete(Map<String, Object>.from(message));
          receivePort.close();
        }
        if (type == 'error') {
          completer.completeError(StateError((message['error'] as String?) ?? 'Unknown error'));
          receivePort.close();
        }
      }
    });

    await Isolate.spawn(_createTorrentIsolateEntry, {
      'sendPort': receivePort.sendPort,
      'entries': entries,
      'name': torrentName,
      'trackers': trackers,
      'pieceLength': pieceLength,
      'isPrivate': isPrivate,
      'comment': comment,
    });

    final result = await completer.future;
    final bytes = (result['bytes'] as TransferableTypedData).materialize().asUint8List();
    final pieceCount = result['pieceCount'] as int;

    final outputPath = p.join(outputDirectory, '${torrentName.trim()}.torrent');
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(bytes, flush: true);

    onProgress?.call(1.0, 'Torrent created');

    return TorrentCreationResult(
      torrentPath: outputPath,
      pieceLength: pieceLength,
      pieceCount: pieceCount,
      totalSize: totalSize,
    );
  }
}

Future<void> _createTorrentIsolateEntry(Map<String, Object> args) async {
  final sendPort = args['sendPort']! as SendPort;
  try {
    final entries = (args['entries']! as List).cast<Map>();
    final torrentName = args['name']! as String;
    final trackers = (args['trackers']! as List).cast<String>();
    final pieceLength = args['pieceLength']! as int;
    final isPrivate = args['isPrivate']! as bool;
    final comment = args['comment']! as String;

    final totalBytes = entries.fold<int>(0, (sum, e) => sum + (e['length'] as int));
    var processed = 0;

    final pieceHashes = BytesBuilder();
    final buffer = BytesBuilder();
    var bufferLen = 0;

    for (final entry in entries) {
      final file = File(entry['path'] as String);
      if (!await file.exists()) {
        sendPort.send({
          'type': 'error',
          'error': 'Source file missing: ${entry['path']}',
        });
        return;
      }

      await for (final chunk in file.openRead()) {
        buffer.add(chunk);
        bufferLen += chunk.length;
        processed += chunk.length;

        while (bufferLen >= pieceLength) {
          final all = buffer.toBytes();
          final pieceData = all.sublist(0, pieceLength);
          final digest = sha1.convert(pieceData);
          pieceHashes.add(digest.bytes);

          final remaining = all.sublist(pieceLength);
          buffer.clear();
          buffer.add(remaining);
          bufferLen = remaining.length;
        }

        final progress = totalBytes > 0 ? processed / totalBytes : 0.0;
        sendPort.send({
          'type': 'progress',
          'progress': progress,
          'message': 'Hashing ${(progress * 100).toStringAsFixed(1)}%',
        });
      }
    }

    if (bufferLen > 0) {
      final digest = sha1.convert(buffer.toBytes());
      pieceHashes.add(digest.bytes);
    }

    final files = entries
        .map((entry) => {
              'length': entry['length'] as int,
              'path': (entry['relativePath'] as String).split(RegExp(r'[\\/]')),
            })
        .toList();

    final info = <String, Object>{
      'name': torrentName,
      'piece length': pieceLength,
      'pieces': Uint8List.fromList(pieceHashes.toBytes()),
    };

    if (files.length == 1) {
      info['length'] = files.first['length']!;
    } else {
      info['files'] = files;
    }

    if (isPrivate) {
      info['private'] = 1;
    }

    final cleanedTrackers = trackers
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final metadict = <String, Object>{
      'info': info,
      'created by': 'Vault The Spire 1.0',
      'creation date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    if (cleanedTrackers.isNotEmpty) {
      metadict['announce'] = cleanedTrackers.first;
      metadict['announce-list'] = cleanedTrackers.map((t) => [t]).toList();
    }
    if (comment.trim().isNotEmpty) {
      metadict['comment'] = comment.trim();
    }

    final bytes = encode(metadict);
    final pieceCount = pieceHashes.toBytes().length ~/ 20;

    sendPort.send({
      'type': 'result',
      'bytes': TransferableTypedData.fromList([bytes]),
      'pieceCount': pieceCount,
    });
  } catch (e) {
    sendPort.send({'type': 'error', 'error': e.toString()});
  }
}
