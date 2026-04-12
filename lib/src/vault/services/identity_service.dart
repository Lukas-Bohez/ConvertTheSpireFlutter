import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:convert_the_spire_reborn/src/vault/crypto/identity.dart';

class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  static const _kIdentityKey = 'vault_the_spire_identity';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Identity? _identity;

  Identity? get identity => _identity;

  Future<void> initialize() async {
    final raw = await _secureStorage.read(key: _kIdentityKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _identity = Identity.fromJson(data);
        return;
      } catch (_) {
        // fallback to regeneration
      }
    }

    await _generateAndSaveIdentity();
  }

  Future<void> _generateAndSaveIdentity() async {
    final identity = await Identity.generate();
    _identity = identity;
    await _secureStorage.write(
      key: _kIdentityKey,
      value: jsonEncode(identity.toJson()),
    );
  }

  Future<void> setDisplayName(String displayName) async {
    if (_identity == null) return;
    _identity = Identity(
      publicKeyBase64: _identity!.publicKeyBase64,
      privateKeyBase64: _identity!.privateKeyBase64,
      nodeId: _identity!.nodeId,
      displayName: displayName.trim().isEmpty ? 'You' : displayName.trim(),
    );
    await _secureStorage.write(
      key: _kIdentityKey,
      value: jsonEncode(_identity!.toJson()),
    );
  }

  Future<String> exportIdentity() async {
    if (_identity == null) {
      throw StateError('Identity not initialized');
    }
    return jsonEncode(_identity!.toJson());
  }

  Future<void> importIdentity(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final identity = Identity.fromJson(data);
    _identity = identity;
    await _secureStorage.write(
      key: _kIdentityKey,
      value: jsonEncode(identity.toJson()),
    );
  }
}
