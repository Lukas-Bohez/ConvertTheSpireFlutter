import '../models/app_settings.dart';
import '../vault/services/settings_service.dart' as vault;

class VaultSettingsBridge {
  VaultSettingsBridge._();

  static String effectiveTorrentDownloadDir(AppSettings settings) {
    final torrentDir = settings.downloadDirTorrents?.trim() ?? '';
    if (torrentDir.isNotEmpty) return torrentDir;
    return settings.downloadDir.trim();
  }

  static Future<void> pushHostSettingsToVault(AppSettings settings) async {
    final targetDir = effectiveTorrentDownloadDir(settings);
    if (targetDir.isEmpty) return;

    if (vault.SettingsService.instance.downloadDestination.trim() != targetDir) {
      await vault.SettingsService.instance.setDownloadDestination(targetDir);
    }
  }

  static Future<AppSettings> pullVaultSettingsIntoHost(AppSettings settings) async {
    await vault.SettingsService.instance.load();

    final vaultDir = vault.SettingsService.instance.downloadDestination.trim();
    if (vaultDir.isEmpty) return settings;

    final currentEffective = effectiveTorrentDownloadDir(settings);
    if (currentEffective == vaultDir) return settings;

    return settings.copyWith(downloadDirTorrents: vaultDir);
  }
}
