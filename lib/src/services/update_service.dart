import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final String latestVersion;
  final String currentVersion;
  final String releaseUrl;
  final String windowsAssetUrl;
  final String androidAssetUrl;
  final String linuxAssetUrl;
  final bool updateAvailable;
  final String releaseNotes;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseUrl,
    required this.windowsAssetUrl,
    required this.androidAssetUrl,
    required this.linuxAssetUrl,
    required this.updateAvailable,
    required this.releaseNotes,
  });
}

class UpdateService {
  static const _repoOwner = 'Lukas-Bohez';
  static const _repoName = 'ConvertTheSpireFlutter';
  static const _apiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  static const _prefLastSeenVersion = 'update_last_seen_version';
  static const _prefCheckOnLaunch = 'update_check_on_launch';

  /// Returns null on network failure — never throws to caller.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(Uri.parse(_apiUrl), headers: {
        'Accept': 'application/vnd.github.v3+json'
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String? ?? '').replaceAll('v', '');
      final body = (json['body'] as String? ?? '');
      final htmlUrl = json['html_url'] as String? ?? '';

      String windowsUrl = '';
      String androidUrl = '';
      String linuxUrl = '';
      final assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = asset['browser_download_url'] as String? ?? '';
        if (name.contains('rebor') && name.endsWith('.zip') && windowsUrl.isEmpty) windowsUrl = url;
        if (name.endsWith('.apk') && androidUrl.isEmpty) androidUrl = url;
        // Prefer AppImage on Linux if present; fall back to linux.zip
        if (name.endsWith('.appimage')) {
          linuxUrl = url; // prefer AppImage
        } else if (name.endsWith('.zip') && linuxUrl.isEmpty) {
          linuxUrl = url;
        }
      }

      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      return UpdateInfo(
        latestVersion: tagName,
        currentVersion: current,
        releaseUrl: htmlUrl,
        windowsAssetUrl: windowsUrl,
        androidAssetUrl: androidUrl,
        linuxAssetUrl: linuxUrl,
        updateAvailable: _isNewer(tagName, current),
        releaseNotes: body.length > 500 ? '${body.substring(0, 500)}…' : body,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String latest, String current) {
    final l = latest.split('.').map(int.tryParse).toList();
    final c = current.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? (l[i] ?? 0) : 0;
      final cv = i < c.length ? (c[i] ?? 0) : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static Future<bool> isCheckOnLaunchEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefCheckOnLaunch) ?? true;
  }

  static Future<void> setCheckOnLaunch(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefCheckOnLaunch, value);
  }

  static Future<bool> shouldShowBanner(String latestVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString(_prefLastSeenVersion) ?? '';
    return seen != latestVersion;
  }

  static Future<void> dismissBanner(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastSeenVersion, version);
  }
}
