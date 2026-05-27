import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:shared_preferences/shared_preferences.dart';

class ProxySettings {
  final bool enabled;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useForTrackers;
  final bool useForPeers;

  const ProxySettings({
    required this.enabled,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.useForTrackers,
    required this.useForPeers,
  });

  bool get isConfigured => enabled && host.trim().isNotEmpty && port > 0;

  String? toYtDlpProxyUrl() {
    if (!isConfigured) return null;
    final auth = username.trim().isEmpty
        ? ''
        : '${Uri.encodeComponent(username.trim())}:${Uri.encodeComponent(password)}@';
    return 'socks5://$auth${host.trim()}:$port';
  }

  dt.ProxyConfig? toTorrentProxyConfig() {
    if (!isConfigured) return null;
    return dt.ProxyConfig.socks5(
      host: host.trim(),
      port: port,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password,
      useForTrackers: useForTrackers,
      useForPeers: useForPeers,
    );
  }
}

class NetworkProxyService {
  static const String _kProxyEnabled = 'network_proxy_enabled';
  static const String _kProxyHost = 'network_proxy_host';
  static const String _kProxyPort = 'network_proxy_port';
  static const String _kProxyUsername = 'network_proxy_username';
  static const String _kProxyPassword = 'network_proxy_password';
  static const String _kProxyForTrackers = 'network_proxy_for_trackers';
  static const String _kProxyForPeers = 'network_proxy_for_peers';

  static Future<ProxySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ProxySettings(
      enabled: prefs.getBool(_kProxyEnabled) ?? false,
      host: prefs.getString(_kProxyHost) ?? '',
      port: prefs.getInt(_kProxyPort) ?? 1080,
      username: prefs.getString(_kProxyUsername) ?? '',
      password: prefs.getString(_kProxyPassword) ?? '',
      useForTrackers: prefs.getBool(_kProxyForTrackers) ?? true,
      useForPeers: prefs.getBool(_kProxyForPeers) ?? true,
    );
  }

  static Future<void> save(ProxySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kProxyEnabled, settings.enabled);
    await prefs.setString(_kProxyHost, settings.host.trim());
    await prefs.setInt(_kProxyPort, settings.port);
    await prefs.setString(_kProxyUsername, settings.username);
    await prefs.setString(_kProxyPassword, settings.password);
    await prefs.setBool(_kProxyForTrackers, settings.useForTrackers);
    await prefs.setBool(_kProxyForPeers, settings.useForPeers);
  }

  static Future<void> clear() async {
    await save(
      const ProxySettings(
        enabled: false,
        host: '',
        port: 1080,
        username: '',
        password: '',
        useForTrackers: true,
        useForPeers: true,
      ),
    );
  }

  static Future<String?> ytDlpProxyUrl() async {
    final settings = await load();
    return settings.toYtDlpProxyUrl();
  }

  static Future<dt.ProxyConfig?> torrentProxyConfig() async {
    final settings = await load();
    return settings.toTorrentProxyConfig();
  }

  static Future<bool> testSocks5Connection() async {
    final settings = await load();
    final proxy = settings.toTorrentProxyConfig();
    if (proxy == null) return false;

    final manager = dt.ProxyManager(proxy);
    if (manager.socks5Client == null) return false;

    final socket = await manager.connectThroughProxy(
      InternetAddress('8.8.8.8'),
      80,
      timeout: const Duration(seconds: 10),
    );
    await socket.close();
    return true;
  }
}
