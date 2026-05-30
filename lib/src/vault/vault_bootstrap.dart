import 'package:convert_the_spire_reborn/src/vault/db/sqlcipher_bootstrap.dart';
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
      await initSqlCipherOnAndroid();
      await SettingsService.instance.load();
      await IdentityService.instance.initialize();
      await TorrentService.instance.resumeActiveTorrents();
    } catch (e, st) {
      debugPrint('Vault bootstrap failed: $e');
      debugPrint(st.toString());
    }
  }
}
