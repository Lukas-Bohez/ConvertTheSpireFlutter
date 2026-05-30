import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:convert_the_spire_reborn/src/vault/bittorrent/bencode.dart';

class TorrentMetadata {
  final String infoHashV1;
  final String? infoHashV2;
  final String name;
  final int pieceLength;
  final List<String> pieceHashes;
  final List<TorrentFileEntry> files;
  final List<String> trackers;
  final List<String> webSeeds;

  TorrentMetadata({
    required this.infoHashV1,
    this.infoHashV2,
    required this.name,
    required this.pieceLength,
    required this.pieceHashes,
    required this.files,
    required this.trackers,
    required this.webSeeds,
  });
}

class TorrentFileEntry {
  final int length;
  final String path;

  TorrentFileEntry({required this.length, required this.path});
}

class TorrentFileParser {
  static TorrentMetadata parse(Uint8List data) {
    final decoded = bdecode(data);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Torrent file is not a bencoded dictionary');
    }

    final infoObj = decoded['info'];
    if (infoObj == null || infoObj is! Map<String, dynamic>) {
      throw FormatException('Invalid torrent metadata: info dict missing');
    }

    final infoBencoded = bencode(infoObj);
    final infoHashV1 = sha1.convert(infoBencoded).toString();
    final infoHashV2 = sha256.convert(infoBencoded).toString();

    final pieceLength = _getInt(infoObj, 'piece length');

    final name = _getString(infoObj, 'name');

    final pieces = infoObj['pieces'];
    final pieceHashes = <String>[];
    if (pieces is Uint8List) {
      if (pieces.length % 20 != 0) {
        throw FormatException('Invalid pieces length for v1 torrent');
      }
      for (var i = 0; i < pieces.length; i += 20) {
        pieceHashes.add(_hex(pieces.sublist(i, i + 20)));
      }
    }

    final files = <TorrentFileEntry>[];
    final filesObj = infoObj['files'];
    if (filesObj is List) {
      for (final file in filesObj) {
        if (file is Map<String, dynamic>) {
          final length = _getInt(file, 'length');
          final pathList = file['path'];
          if (pathList is List) {
            final pathSegments = pathList.map((segment) {
              if (segment is Uint8List) return utf8.decode(segment);
              throw FormatException('Invalid path segment');
            }).join('/');
            files.add(TorrentFileEntry(length: length, path: pathSegments));
          }
        }
      }
    } else {
      files.add(
        TorrentFileEntry(length: _getInt(infoObj, 'length'), path: name),
      );
    }

    final trackers = <String>[];
    final announce = decoded['announce'];
    if (announce is Uint8List) trackers.add(utf8.decode(announce));

    final announceList = decoded['announce-list'];
    if (announceList is List) {
      for (final tier in announceList) {
        if (tier is List) {
          for (final uri in tier) {
            if (uri is Uint8List) {
              final url = utf8.decode(uri);
              if (!trackers.contains(url)) trackers.add(url);
            }
          }
        }
      }
    }

    final webSeeds = <String>[];
    final urlList = decoded['url-list'];
    if (urlList is Uint8List) {
      webSeeds.add(utf8.decode(urlList));
    }

    return TorrentMetadata(
      infoHashV1: infoHashV1,
      infoHashV2: infoHashV2,
      name: name,
      pieceLength: pieceLength,
      pieceHashes: pieceHashes,
      files: files,
      trackers: trackers,
      webSeeds: webSeeds,
    );
  }

  static String _getString(Map<String, dynamic> map, String key) {
    final val = map[key];
    if (val is Uint8List) return utf8.decode(val);
    throw FormatException('Expected string for $key');
  }

  static int _getInt(Map<String, dynamic> map, String key) {
    final val = map[key];
    if (val is int) return val;
    throw FormatException('Expected int for $key');
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
