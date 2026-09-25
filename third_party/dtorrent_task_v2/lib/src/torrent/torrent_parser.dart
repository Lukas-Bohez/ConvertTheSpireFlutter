import 'dart:io';
import 'dart:typed_data';
import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'torrent_model.dart';
import 'torrent_file_model.dart';
import 'file_tree.dart';
import 'torrent_version.dart';
import 'package:logging/logging.dart';

var _log = Logger('TorrentParser');

/// Parser for .torrent files with full support for BEP 3 (v1) and BEP 52 (v2)
class TorrentParser {
  /// Parse a torrent file from disk
  static Future<TorrentModel> parse(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('Torrent file does not exist: $filePath');
    }

    final bytes = await file.readAsBytes();
    return parseBytes(bytes);
  }

  /// Parse torrent from bytes
  static TorrentModel parseBytes(Uint8List bytes) {
    final decoded = decode(bytes);
    if (decoded is! Map) {
      throw FormatException('Invalid torrent file: root must be a dictionary');
    }

    // Convert Map<dynamic, dynamic> to Map<String, dynamic>
    final data = Map<String, dynamic>.from(decoded);
    return _parseTorrent(data, bytes);
  }

  /// Parse torrent from decoded bencoded dictionary
  ///
  /// This is useful when you have already decoded the torrent data
  /// (e.g., from metadata downloader)
  static TorrentModel parseFromMap(Map<String, dynamic> torrentMap) {
    // Re-encode to bytes for hash calculation
    final encoded = encode(torrentMap);
    return _parseTorrent(torrentMap, encoded);
  }

  /// Parse torrent from decoded bencoded data
  static TorrentModel _parseTorrent(
      Map<String, dynamic> data, Uint8List? originalBytes) {
    final infoRaw = data['info'];
    if (infoRaw is! Map) {
      throw FormatException(
          'Invalid torrent file: missing or invalid info dictionary');
    }
    final info = Map<String, dynamic>.from(infoRaw);

    // Detect version
    final version = _detectVersion(info, data);
    _log.info('Detected torrent version: $version');

    // Parse name - can be String or Uint8List from bencode
    final nameRaw = info['name'];
    String? name;
    if (nameRaw is String) {
      name = nameRaw;
    } else if (nameRaw is Uint8List) {
      name = String.fromCharCodes(nameRaw);
    } else if (nameRaw is List<int>) {
      name = String.fromCharCodes(nameRaw);
    }
    if (name == null || name.isEmpty) {
      throw FormatException(
          'Invalid torrent file: missing name in info dictionary');
    }

    // Parse piece length
    final pieceLength = info['piece length'] as int?;
    if (pieceLength == null || pieceLength <= 0) {
      throw FormatException(
          'Invalid torrent file: missing or invalid piece length');
    }

    // Parse announces
    final announces = _parseAnnounces(data);

    // Parse nodes (DHT)
    final nodes = _parseNodes(data);

    // Parse files and pieces based on version
    List<TorrentFileModel> files = [];
    List<Uint8List>? pieces;
    int? length;
    Map<String, FileTreeEntry>? fileTree;
    Map<String, Uint8List>? pieceLayers;
    Uint8List? rootHash;
    Uint8List? infoDictBytes;
    int? metaVersion;

    if (version == TorrentVersion.v1 || version == TorrentVersion.hybrid) {
      // Parse v1 structure
      if (info.containsKey('length')) {
        // Single file
        length = info['length'] as int?;
        if (length == null) {
          throw FormatException(
              'Invalid torrent file: length must be an integer');
        }
        files = [TorrentFileModel(path: name, length: length, offset: 0)];
      } else if (info.containsKey('files')) {
        // Multiple files
        final filesList = info['files'] as List?;
        if (filesList == null) {
          throw FormatException('Invalid torrent file: files must be a list');
        }
        files = _parseV1Files(filesList, name);
      } else {
        throw FormatException('Invalid torrent file: missing length or files');
      }

      // Parse pieces (v1)
      if (info.containsKey('pieces')) {
        final piecesData = info['pieces'] as Uint8List?;
        if (piecesData != null) {
          pieces = _parsePieces(piecesData);
        }
      }
    }

    if (version == TorrentVersion.v2 || version == TorrentVersion.hybrid) {
      // Parse v2 structure
      metaVersion = info['meta version'] as int?;

      // Parse file tree
      if (info.containsKey('file tree')) {
        final treeData = info['file tree'];
        fileTree = FileTreeHelper.parseFileTree(treeData);
      }

      // Parse piece layers (in root dict, not info dict)
      if (data.containsKey('piece layers')) {
        final layersData = data['piece layers'];
        if (layersData is Map) {
          pieceLayers = _parsePieceLayers(layersData);
        }
      }

      // Parse root hash
      if (info.containsKey('root hash')) {
        final rootHashData = info['root hash'] as Uint8List?;
        if (rootHashData != null && rootHashData.length == 32) {
          rootHash = rootHashData;
        }
      }

      // If we have file tree but no v1 files, extract files from tree
      if (fileTree != null && (version == TorrentVersion.v2 || files.isEmpty)) {
        final treeFiles = FileTreeHelper.extractFiles(fileTree, '');
        if (files.isEmpty) {
          // Convert FileTreeFile to TorrentFileModel
          var offset = 0;
          files = treeFiles.map((tf) {
            final file = TorrentFileModel(
              path: tf.path,
              length: tf.length,
              offset: offset,
            );
            offset += tf.length;
            return file;
          }).toList();
        }
      }
    }

    // Calculate info hash
    Uint8List infoHashBuffer;
    if (originalBytes != null) {
      // Extract info dict bytes for hash calculation
      infoDictBytes = _extractInfoDictBytes(originalBytes);
      if (infoDictBytes != null) {
        if (version == TorrentVersion.v2 || version == TorrentVersion.hybrid) {
          // v2 uses SHA-256
          final hash = sha256.convert(infoDictBytes);
          infoHashBuffer = Uint8List.fromList(hash.bytes);
        } else {
          // v1 uses SHA-1
          final hash = sha1.convert(infoDictBytes);
          infoHashBuffer = Uint8List.fromList(hash.bytes);
        }
      } else {
        // Fallback: use v1 hash if available
        if (pieces != null && pieces.isNotEmpty) {
          final hash = sha1.convert(infoDictBytes ?? Uint8List(0));
          infoHashBuffer = Uint8List.fromList(hash.bytes);
        } else {
          throw FormatException('Unable to calculate info hash');
        }
      }
    } else {
      // If we don't have original bytes, we can't calculate hash
      // This shouldn't happen in normal usage
      throw FormatException(
          'Cannot calculate info hash without original bytes');
    }

    return TorrentModel(
      name: name,
      files: files,
      infoHashBuffer: infoHashBuffer,
      pieceLength: pieceLength,
      pieces: pieces,
      announces: announces,
      nodes: nodes,
      length: length,
      version: version,
      metaVersion: metaVersion,
      fileTree: fileTree,
      pieceLayers: pieceLayers,
      rootHash: rootHash,
      infoDictBytes: infoDictBytes,
      rawData: data,
    );
  }

  /// Detect torrent version from info dict and root dict
  static TorrentVersion _detectVersion(
      Map<String, dynamic> info, Map<String, dynamic> root) {
    final metaVersion = info['meta version'] as int?;
    final hasFileTree = info.containsKey('file tree');
    final hasPieces = info.containsKey('pieces');
    final hasPieceLayers = root.containsKey('piece layers');

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
  }

  /// Parse announce URLs
  static List<Uri> _parseAnnounces(Map<String, dynamic> data) {
    final announces = <Uri>[];

    // Try announce-list first (BEP 0012)
    if (data.containsKey('announce-list')) {
      final announceList = data['announce-list'] as List?;
      if (announceList != null) {
        for (var tier in announceList) {
          if (tier is List) {
            for (var url in tier) {
              String? urlString;
              if (url is String) {
                urlString = url;
              } else if (url is Uint8List) {
                urlString = String.fromCharCodes(url);
              } else if (url is List<int>) {
                urlString = String.fromCharCodes(url);
              }
              if (urlString != null) {
                try {
                  announces.add(Uri.parse(urlString));
                } catch (e) {
                  _log.warning('Invalid announce URL: $urlString', e);
                }
              }
            }
          }
        }
      }
    }

    // Fallback to single announce
    if (announces.isEmpty && data.containsKey('announce')) {
      final announceRaw = data['announce'];
      String? announce;
      if (announceRaw is String) {
        announce = announceRaw;
      } else if (announceRaw is Uint8List) {
        announce = String.fromCharCodes(announceRaw);
      } else if (announceRaw is List<int>) {
        announce = String.fromCharCodes(announceRaw);
      }
      if (announce != null) {
        try {
          announces.add(Uri.parse(announce));
        } catch (e) {
          _log.warning('Invalid announce URL: $announce', e);
        }
      }
    }

    return announces;
  }

  /// Parse DHT nodes
  static List<Uri> _parseNodes(Map<String, dynamic> data) {
    final nodes = <Uri>[];

    if (data.containsKey('nodes')) {
      final nodesData = data['nodes'];
      if (nodesData is List) {
        for (var node in nodesData) {
          if (node is List && node.length == 2) {
            final hostRaw = node[0];
            String? host;
            if (hostRaw is String) {
              host = hostRaw;
            } else if (hostRaw is Uint8List) {
              host = String.fromCharCodes(hostRaw);
            } else if (hostRaw is List<int>) {
              host = String.fromCharCodes(hostRaw);
            }
            final port = node[1] as int?;
            if (host != null && port != null) {
              try {
                nodes.add(Uri.parse('udp://$host:$port'));
              } catch (e) {
                _log.warning('Invalid node: $host:$port', e);
              }
            }
          }
        }
      }
    }

    return nodes;
  }

  /// Parse v1 files list
  static List<TorrentFileModel> _parseV1Files(List filesList, String basePath) {
    final files = <TorrentFileModel>[];
    var offset = 0;

    for (var fileData in filesList) {
      if (fileData is! Map) continue;

      final length = fileData['length'] as int?;
      if (length == null) continue;

      final pathList = fileData['path'] as List?;
      String path;
      if (pathList != null && pathList.isNotEmpty) {
        path = pathList.map((p) {
          if (p is String) {
            return p;
          } else if (p is Uint8List) {
            return String.fromCharCodes(p);
          } else if (p is List<int>) {
            return String.fromCharCodes(p);
          } else {
            return p.toString();
          }
        }).join('/');
        if (basePath.isNotEmpty) {
          path = '$basePath/$path';
        }
      } else {
        path = basePath;
      }

      files.add(TorrentFileModel(
        path: path,
        length: length,
        offset: offset,
      ));

      offset += length;
    }

    return files;
  }

  /// Parse piece hashes from pieces string
  static List<Uint8List> _parsePieces(Uint8List piecesData) {
    const pieceHashLength = 20; // SHA-1 hash length
    if (piecesData.length % pieceHashLength != 0) {
      throw FormatException(
          'Invalid pieces data: length must be multiple of $pieceHashLength');
    }

    final pieces = <Uint8List>[];
    for (var i = 0; i < piecesData.length; i += pieceHashLength) {
      pieces.add(piecesData.sublist(i, i + pieceHashLength));
    }

    return pieces;
  }

  /// Parse piece layers from bencoded data
  static Map<String, Uint8List> _parsePieceLayers(
      Map<dynamic, dynamic> layersData) {
    final pieceLayers = <String, Uint8List>{};

    for (var entry in layersData.entries) {
      final key = entry.key;
      final value = entry.value;

      // Key should be hex string of piece root hash
      String keyString;
      if (key is Uint8List) {
        keyString = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      } else if (key is String) {
        keyString = key;
      } else {
        continue;
      }

      // Value should be Uint8List of piece layer data
      if (value is Uint8List) {
        pieceLayers[keyString] = value;
      }
    }

    return pieceLayers;
  }

  /// Extract info dictionary bytes from bencoded torrent data
  /// This is needed for calculating info hash
  static Uint8List? _extractInfoDictBytes(Uint8List torrentBytes) {
    try {
      // Find the start of "info" key
      final infoKeyBytes = Uint8List.fromList('info'.codeUnits);
      var infoStart = -1;

      for (var i = 0; i < torrentBytes.length - infoKeyBytes.length; i++) {
        var match = true;
        for (var j = 0; j < infoKeyBytes.length; j++) {
          if (torrentBytes[i + j] != infoKeyBytes[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          infoStart = i + infoKeyBytes.length;
          break;
        }
      }

      if (infoStart == -1) {
        return null;
      }

      // Skip the key length and key itself, find the start of the value
      // In bencode, dictionary entries are: d<key><value>e
      // We need to find where the value starts after "info"
      // The value is a dictionary, so it starts with 'd'

      // Find the 'd' that starts the info dict
      var dictStart = infoStart;
      while (
          dictStart < torrentBytes.length && torrentBytes[dictStart] != 0x64) {
        dictStart++;
      }

      if (dictStart >= torrentBytes.length) {
        return null;
      }

      // Find the matching 'e' that closes the info dict
      var depth = 0;
      var dictEnd = dictStart;
      for (var i = dictStart; i < torrentBytes.length; i++) {
        if (torrentBytes[i] == 0x64) {
          // 'd' - start of dict
          depth++;
        } else if (torrentBytes[i] == 0x65) {
          // 'e' - end of dict
          depth--;
          if (depth == 0) {
            dictEnd = i + 1;
            break;
          }
        }
      }

      if (dictEnd <= dictStart) {
        return null;
      }

      return torrentBytes.sublist(dictStart, dictEnd);
    } catch (e) {
      _log.warning('Failed to extract info dict bytes', e);
      return null;
    }
  }
}
