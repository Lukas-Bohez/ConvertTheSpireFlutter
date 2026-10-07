import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/build_flags.dart';
import '../platform/browser_webview_controller.dart' show ContentBlocking;
import 'adblock_scripts.dart';
import 'filter_list.dart';

/// The in-app browser's ad blocker, on the filter lists uBlock Origin also
/// starts from: EasyList (ads) and EasyPrivacy (trackers).
///
/// It blocks the requests the lists name (see [FilterSet]) and hides the
/// elements they name. The lists are cached and refreshed every 7 days.
class AdBlockService extends ChangeNotifier {
  static const _listUrls = [
    'https://easylist.to/easylist/easylist.txt',
    'https://easylist.to/easylist/easyprivacy.txt',
  ];
  static const _prefKey = 'adblock_enabled';
  static const _lastUpdatedKey = 'adblock_last_updated';

  FilterSet _filters = FilterSet(blockedHosts: {..._hardcodedPopupDomains});
  ContentBlocking? _contentBlocking;
  bool _enabled = true;
  bool _loaded = false;
  bool _disposed = false;
  DateTime? _lastUpdated;

  bool get adBlockEnabled => _enabled;
  bool get isLoaded => _loaded;
  DateTime? get lastUpdated => _lastUpdated;
  FilterSet get filters => _filters;

  /// The always-blocked popup/tracking domains.
  Set<String> get hardcodedPopupDomains => _hardcodedPopupDomains;

  /// Common popup / tracking domains that are always blocked.
  static final _hardcodedPopupDomains = <String>{
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
  };

  /// What a webview needs to block with the current lists, or null while
  /// the blocker is off.
  ContentBlocking? get contentBlocking {
    if (!_enabled) return null;
    return _contentBlocking ??= ContentBlocking(
      id: '${identityHashCode(_filters)}-${DateTime.now().microsecondsSinceEpoch}',
      filters: _filters,
      // YouTube features stay out of the Play build.
      documentStartScript:
          documentStartScript(_filters, skipYouTubeAds: !kPlayStoreBuild),
    );
  }

  /// The script that hides [url]'s own site's ad elements, or null.
  String? siteHideScript(String url) =>
      _enabled ? siteHideScriptFor(_filters, url) : null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? true;
    final lastMs = prefs.getInt(_lastUpdatedKey);
    if (lastMs != null) {
      _lastUpdated = DateTime.fromMillisecondsSinceEpoch(lastMs);
    }
    await _loadOrFetch();
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> toggleAdBlock() => setEnabled(!_enabled);

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, _enabled);
    notifyListeners();
  }

  Future<void> updateBlocklist() async {
    await _fetchAndCache();
    if (!_disposed) notifyListeners();
  }

  /// Test seam: loads a blocklist without touching the network or disk.
  ///
  /// Blocking has no other way in — the real list is fetched from EasyList and
  /// cached — and a silent regression here either breaks every page or lets
  /// every ad through, so the rules are worth pinning down.
  @visibleForTesting
  void seedBlocklistForTesting(Iterable<String> domains, {bool enabled = true}) {
    _setFilters(FilterSet(blockedHosts: {...domains.map((d) => d.toLowerCase())}));
    _enabled = enabled;
  }

  @visibleForTesting
  void seedFiltersForTesting(FilterSet filters) => _setFilters(filters);

  /// Whether [url], loaded by the page at [pageUrl], is blocked.
  bool shouldBlock(String url, {String? pageUrl}) {
    if (!_enabled) return false;
    try {
      return _filters.blocks(url, pageUrl: pageUrl);
    } catch (_) {
      return false;
    }
  }

  void _setFilters(FilterSet filters) {
    filters.blockedHosts.addAll(_hardcodedPopupDomains);
    _filters = filters;
    _contentBlocking = null;
  }

  // -- Private --

  Future<File> get _cacheFile async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/adblock_filters.json');
  }

  Future<void> _loadOrFetch() async {
    final file = await _cacheFile;
    final exists = file.existsSync();
    final needsFetch = !exists ||
        _lastUpdated == null ||
        DateTime.now().difference(_lastUpdated!).inDays >= 7;

    if (exists) {
      try {
        final path = file.path;
        final cached = await Isolate.run(
            () => FilterSet.fromJson(jsonDecode(File(path).readAsStringSync())));
        if (cached != null && !_disposed) _setFilters(cached);
      } catch (e) {
        if (kDebugMode) debugPrint('AdBlock cache unreadable: $e');
      }
    }
    // The domain-only cache of earlier versions.
    final old = File('${file.parent.path}/easylist_domains.txt');
    if (old.existsSync()) unawaited(old.delete().then((_) {}, onError: (_) {}));

    if (needsFetch || _filters.ruleCount <= _hardcodedPopupDomains.length) {
      // Fetched in the background: init doesn't wait for the network.
      unawaited(_fetchAndCache().then((_) {
        if (!_disposed) notifyListeners();
      }));
    }
  }

  Future<void> _fetchAndCache() async {
    try {
      final path = (await _cacheFile).path;
      final filters = await Isolate.run(() => _fetchParseAndCache(path))
          .timeout(const Duration(seconds: 60));
      if (_disposed || filters == null) return;
      _setFilters(filters);

      _lastUpdated = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastUpdatedKey, _lastUpdated!.millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) debugPrint('AdBlock update failed: $e');
    }
  }

  /// Downloads and parses the lists and writes the cache, on an isolate so
  /// the UI keeps going. Null when no list could be downloaded.
  static Future<FilterSet?> _fetchParseAndCache(String cachePath) async {
    final lines = <String>[];
    for (final url in _listUrls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) continue;
        lines.addAll(const LineSplitter().convert(response.body));
      } catch (_) {
        // The other list still helps.
      }
    }
    if (lines.isEmpty) return null;
    final filters = FilterSet.parse(lines);
    await File(cachePath).writeAsString(jsonEncode(filters.toJson()));
    return filters;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
