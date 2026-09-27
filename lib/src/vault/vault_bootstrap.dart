import 'package:convert_the_spire_reborn/src/vault/services/identity_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:flutter/foundation.dart';

class VaultBootstrap {
  VaultBootstrap._();

  static Future<void>? _initFuture;

  static Future<void> ensureInitialized() {
    return _initFuture ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      // NOTE: DB encryption is intentionally NOT enabled yet. The 13.0.6 build
      // keyed the database unconditionally, but SQLCipher is not loaded in the
      // shipped binaries — `PRAGMA cipher_version` returned empty, the DB open
      // threw, and the torrents list spun forever. VaultKeyService stays for
      // when SQLCipher ships with a proper plaintext→encrypted migration.
      await SettingsService.instance.load();
      // The identity lives in the system keyring (Credential Manager on
      // Windows, the Secret Service on Linux), which can refuse; torrents
      // do not need it, and a refusal used to leave them all stopped after
      // a restart.
      try {
        await IdentityService.instance.initialize();
      } catch (e) {
        debugPrint('Vault identity unavailable: $e');
      }
      await TorrentService.instance.resumeActiveTorrents();
    } catch (e, st) {
      debugPrint('Vault bootstrap failed: $e');
      debugPrint(st.toString());
    }
  }
}
