import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class Identity {
  final String publicKeyBase64;
  final String privateKeyBase64;
  final String nodeId;
  final String displayName;

  Identity({
    required this.publicKeyBase64,
    required this.privateKeyBase64,
    required this.nodeId,
    required this.displayName,
  });

  static Future<Identity> generate() async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();

    final publicKey = keyPairData.publicKey;
    final publicKeyBytes = publicKey.bytes;
    final privateKeyBytes = keyPairData.bytes;

    final publicKeyBase64 = base64UrlEncode(publicKeyBytes);
    final privateKeyBase64 = base64UrlEncode(privateKeyBytes);

    final nodeId = _deriveNodeId(publicKeyBytes);

    return Identity(
      publicKeyBase64: publicKeyBase64,
      privateKeyBase64: privateKeyBase64,
      nodeId: nodeId,
      displayName: 'You',
    );
  }

  static String _deriveNodeId(List<int> publicKeyBytes) {
    // Avoid direct derivation from the public key to minimize deterministic
    // node ID fingerprinting risks. Generate a random DHT node ID per session.
    final random = Random.secure();
    final nodeIdBytes = List<int>.generate(20, (_) => random.nextInt(256));
    return nodeIdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, dynamic> toJson() => {
        'publicKeyBase64': publicKeyBase64,
        'privateKeyBase64': privateKeyBase64,
        'nodeId': nodeId,
        'displayName': displayName,
      };

  factory Identity.fromJson(Map<String, dynamic> json) {
    return Identity(
      publicKeyBase64: json['publicKeyBase64'] as String,
      privateKeyBase64: json['privateKeyBase64'] as String,
      nodeId: json['nodeId'] as String,
      displayName: json['displayName'] as String? ?? 'You',
    );
  }
}
