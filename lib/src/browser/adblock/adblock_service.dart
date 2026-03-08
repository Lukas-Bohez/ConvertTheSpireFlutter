import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight ad-block service that uses EasyList domain rules.
///
/// Parses `||domain^` and `||domain/` style rules into a [HashSet] for O(1)
/// lookup. The blocklist is cached locally and refreshed every 7 days.
class AdBlockService extends ChangeNotifier {
  static const _easyListUrl = 'https://easylist.to/easylist/easylist.txt';
  static const _prefKey = 'adblock_enabled';
  static const _lastUpdatedKey = 'adblock_last_updated';

  HashSet<String> _blockedDomains = HashSet<String>();
  bool _enabled = true;
  bool _loaded = false;
  DateTime? _lastUpdated;

  bool get adBlockEnabled => _enabled;
  bool get isLoaded => _loaded;
  DateTime? get lastUpdated => _lastUpdated;

  /// Common popup / tracking domains that are always blocked.
  static final _hardcodedPopupDomains = HashSet<String>.from([
    'popads.net',
    'popcash.net',
    'propellerads.com',
    'clickadu.com',
    'adserverplus.com',
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'pagead2.googlesyndication.com',
    'ad.doubleclick.net',
    'adnxs.com',
    'adsrvr.org',
    'outbrain.com',
    'taboola.com',
    'popunder.net',
    'trafficjunky.com',
    'exoclick.com',
    'juicyads.com',
    'revcontent.com',
  ]);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;
    final lastMs = prefs.getInt(_lastUpdatedKey);
    if (lastMs != null) {
      _lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastMs);
    }
    await _loadOrFetch();
    _loaded = true;
    notifyListeners();
  }

  Future<void> toggleAdBlock() async {
    _enabled = !_enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, _enabled);
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, _enabled);
    notifyListeners();
  }

  Future<void> updateBlocklist() async {
    await _fetchAndCache();
    notifyListeners();
  }

  /// Returns `true` if [url] should be blocked.
  bool shouldBlock(String url) {
    if (!_enabled) return false;
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      // Check exact domain and parent domains
      if (_blockedDomains.contains(host) ||
          _hardcodedPopupDomains.contains(host)) {
        return true;
      }
      // Check parent domains (e.g. ads.example.com → example.com)
      final parts = host.split('.');
      for (var i = 1; i < parts.length - 1; i++) {
        final parent = parts.sublist(i).join('.');
        if (_blockedDomains.contains(parent) ||
            _hardcodedPopupDomains.contains(parent)) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // ── Private ──

  Future<File> get _cacheFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/easylist_domains.txt');
  }

  Future<void> _loadOrFetch() async {
    final file = await _cacheFile;
    final needsFetch = !file.existsSync() ||
        _lastUpdated == null ||
        DateTime.now().difference(_lastUpdated!).inDays >= 7;

    if (file.existsSync()) {
      final lines = await file.readAsLines();
      _blockedDomains = HashSet<String>.from(lines);
    }

    if (needsFetch) {
      // Fetch in background — don't block init
      _fetchAndCache().catchError((e) {
        if (kDebugMode) debugPrint('AdBlock fetch failed: $e');
      });
    }
  }

  Future<void> _fetchAndCache() async {
    try {
      final domains = await Isolate.run(() => _fetchAndParse());
      _blockedDomains = HashSet<String>.from(domains);

      final file = await _cacheFile;
      await file.writeAsString(domains.join('\n'));

      _lastUpdated = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _lastUpdatedKey, _lastUpdated!.millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) debugPrint('AdBlock update failed: $e');
    }
  }

  /// Fetched and parsed in an isolate to avoid blocking the UI.
  static Future<List<String>> _fetchAndParse() async {
    final response = await http.get(Uri.parse(_easyListUrl));
    if (response.statusCode != 200) return [];

    final domains = <String>[];
    for (final line in const LineSplitter().convert(response.body)) {
      // Match: ||domain^ or ||domain/
      if (!line.startsWith('||')) continue;
      final rest = line.substring(2);
      // Find the terminator — ^ or /
      var end = rest.indexOf('^');
      final slashEnd = rest.indexOf('/');
      if (end < 0 || (slashEnd >= 0 && slashEnd < end)) end = slashEnd;
      if (end <= 0) continue;
      final domain = rest.substring(0, end).toLowerCase();
      // Validate: must look like a domain (letters, digits, dots, hyphens)
      if (domain.contains(RegExp(r'[^a-z0-9.\-]'))) continue;
      if (!domain.contains('.')) continue;
      domains.add(domain);
    }
    return domains;
  }
}
