import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert_the_spire_reborn/src/vault/bittorrent/bencode.dart';

class DhtNodeInfo {
  final String id;
  final String address;
  final int port;

  DhtNodeInfo({required this.id, required this.address, required this.port});

  @override
  String toString() => '$id@$address:$port';
}

class DhtRoutingTable {
  final String localNodeId;
  final List<DhtNodeInfo> buckets = [];

  DhtRoutingTable(this.localNodeId);

  void addNode(DhtNodeInfo node) {
    if (node.id == localNodeId) return;
    if (buckets.any((n) => n.id == node.id)) return;
    if (buckets.length < 8) {
      buckets.add(node);
      return;
    }
    // Simplified least-recently-used replacement strategy
    buckets.removeAt(0);
    buckets.add(node);
  }

  List<DhtNodeInfo> findClosest(String targetId, int count) {
    final target = DhtEngine.hexToBytes(targetId);
    final sorted = List<DhtNodeInfo>.from(buckets);
    sorted.sort((a, b) {
      final da = DhtEngine.xorDistance(DhtEngine.hexToBytes(a.id), target);
      final db = DhtEngine.xorDistance(DhtEngine.hexToBytes(b.id), target);
      return DhtEngine.compareDistance(da, db);
    });
    return sorted.take(count).toList();
  }
}

class DhtEngine {
  final DhtRoutingTable routingTable;
  final Random _random = Random.secure();

  DhtEngine(this.routingTable);

  String generateTransactionId() {
    final bytes = List<int>.generate(2, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).substring(0, 4);
  }

  static String generateNodeId() {
    final bytes = List<int>.generate(20, (_) => Random.secure().nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List xorDistance(Uint8List a, Uint8List b) {
    final len = min(a.length, b.length);
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  static int compareDistance(Uint8List a, Uint8List b) {
    for (var i = 0; i < min(a.length, b.length); i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  static Uint8List hexToBytes(String hex) {
    final sanitized = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final bytes = Uint8List(sanitized.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(sanitized.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  String createPingMessage(String targetId) {
    final message = {
      't': generateTransactionId(),
      'y': 'q',
      'q': 'ping',
      'a': {
        'id': DhtEngine.hexToBytes(routingTable.localNodeId),
        'target': DhtEngine.hexToBytes(targetId),
      },
    };
    return _encode(message);
  }

  String createFindNodeMessage(String targetId) {
    final message = {
      't': generateTransactionId(),
      'y': 'q',
      'q': 'find_node',
      'a': {
        'id': DhtEngine.hexToBytes(routingTable.localNodeId),
        'target': DhtEngine.hexToBytes(targetId),
      },
    };
    return _encode(message);
  }

  String _encode(Map<String, dynamic> message) {
    final bytes = bencode(message);
    return utf8.decode(bytes);
  }

  List<DhtNodeInfo> decodeNodes(Uint8List packed) {
    final nodeInfos = <DhtNodeInfo>[];
    for (var i = 0; i + 26 <= packed.length; i += 26) {
      final idBytes = packed.sublist(i, i + 20);
      final ipBytes = packed.sublist(i + 20, i + 24);
      final portBytes = packed.sublist(i + 24, i + 26);
      final ip = '${ipBytes[0]}.${ipBytes[1]}.${ipBytes[2]}.${ipBytes[3]}';
      final port = (portBytes[0] << 8) | portBytes[1];
      nodeInfos.add(
        DhtNodeInfo(
          id: idBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          address: ip,
          port: port,
        ),
      );
    }
    return nodeInfos;
  }

  // This class uses raw bytes for bencoded node IDs, so no conversion to UTF-8 string is required.
}
