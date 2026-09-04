import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Generates and stores a per-install AES-256 key for vault DB encryption,
/// kept in OS-backed secure storage (Keychain on macOS/iOS, KeyStore on
/// Android, etc.). Separate from the identity key so rotation policies can
/// diverge later if needed.
class VaultKeyService {
  VaultKeyService._();

  static const _kVaultDbKey = 'vault_db_encryption_key';
  static const _secureStorage = FlutterSecureStorage();

  /// Returns the existing key, or generates and persists a new 64-hex-char
  /// (32-byte) key on first call.
  static Future<String> getOrCreateKey() async {
    final existing = await _secureStorage.read(key: _kVaultDbKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final key = _generateKey();
    await _secureStorage.write(key: _kVaultDbKey, value: key);
    return key;
  }

  static String _generateKey() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return "x'$hex'";
  }
}
