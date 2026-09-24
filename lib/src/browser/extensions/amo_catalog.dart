import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Why a catalog call failed, worded for the user.
class AmoException implements Exception {
  const AmoException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One add-on from addons.mozilla.org, reduced to what the app shows and
/// needs to install it.
class AmoAddon {
  const AmoAddon({
    required this.guid,
    required this.slug,
    required this.name,
    required this.version,
    required this.fileUrl,
    this.summary,
    this.iconUrl,
    this.fileSha256,
    this.fileSize,
    this.permissions = const [],
    this.hostPermissions = const [],
    this.androidCompatible = false,
    this.dailyUsers,
    this.rating,
    this.recommended = false,
    this.pageUrl,
  });

  final String guid;
  final String slug;
  final String name;
  final String version;

  /// The signed .xpi for [version].
  final String fileUrl;
  final String? summary;
  final String? iconUrl;

  /// Lower-case hex, from AMO's `file.hash` ("sha256:...").
  final String? fileSha256;
  final int? fileSize;
  final List<String> permissions;
  final List<String> hostPermissions;

  /// Whether the current version declares Firefox for Android support.
  final bool androidCompatible;
  final int? dailyUsers;
  final double? rating;

  /// Mozilla's "Recommended" badge.
  final bool recommended;

  /// The add-on's page on addons.mozilla.org.
  final String? pageUrl;

  /// Parses one entry of a search result or a details response.
  ///
  /// Every field is read defensively: the v5 API is not frozen (issue #10),
  /// so a missing or reshaped field degrades the entry instead of failing
  /// the whole list. Only an entry with no installable file is dropped.
  static AmoAddon? fromJson(Map<String, dynamic> json,
      {String lang = 'en-US'}) {
    final version = json['current_version'];
    if (version is! Map<String, dynamic>) return null;
    final file = version['file'];
    if (file is! Map<String, dynamic>) return null;
    final fileUrl = file['url'];
    final guid = json['guid'];
    if (fileUrl is! String || fileUrl.isEmpty || guid is! String) return null;

    final compatibility = version['compatibility'];
    final hash = file['hash'];
    final ratings = json['ratings'];
    final promoted = json['promoted'];

    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];

    return AmoAddon(
      guid: guid,
      slug: json['slug'] as String? ?? guid,
      name: localised(json['name'], lang) ?? guid,
      version: version['version'] as String? ?? '',
      fileUrl: fileUrl,
      summary: localised(json['summary'], lang),
      iconUrl: json['icon_url'] as String?,
      fileSha256: hash is String && hash.startsWith('sha256:')
          ? hash.substring('sha256:'.length).toLowerCase()
          : null,
      fileSize: (file['size'] as num?)?.toInt(),
      permissions: strings(file['permissions']),
      hostPermissions: strings(file['host_permissions']),
      androidCompatible:
          compatibility is Map && compatibility.containsKey('android'),
      dailyUsers: (json['average_daily_users'] as num?)?.toInt(),
      rating: ratings is Map ? (ratings['average'] as num?)?.toDouble() : null,
      recommended: promoted is List &&
          promoted.any((p) => p is Map && p['category'] == 'recommended'),
      pageUrl: json['url'] as String?,
    );
  }

  /// Reads a translated field.
  ///
  /// AMO returns these as a map even when a language is requested, and the
  /// requested language can be null in it: an add-on whose default locale is
  /// Dutch comes back as `{"nl": "Lofi Player", "en-US": null, "_default":
  /// "nl"}`. So: the requested language, then the add-on's own default
  /// language, then anything at all.
  static String? localised(Object? field, String lang) {
    if (field is String) return field.trim().isEmpty ? null : field;
    if (field is! Map) return null;
    String? pick(Object? key) {
      final value = key is String ? field[key] : null;
      return value is String && value.trim().isNotEmpty ? value : null;
    }

    return pick(lang) ??
        pick(lang.split('-').first) ??
        pick(field['_default']) ??
        field.entries
            .where((e) => e.key != '_default')
            .map((e) => e.value)
            .whereType<String>()
            .where((v) => v.trim().isNotEmpty)
            .firstOrNull;
  }
}

/// A page of search results.
class AmoSearchPage {
  const AmoSearchPage({
    required this.results,
    required this.total,
    required this.hasMore,
  });

  final List<AmoAddon> results;
  final int total;
  final bool hasMore;
}

/// Client for the addons.mozilla.org v5 API.
///
/// Talks only to AMO. Endpoints and fields used are recorded, with sample
/// responses, in docs/extensions/amo-api.md.
class AmoCatalog {
  AmoCatalog({
    http.Client? client,
    this.lang = 'en-US',
    this.cacheFor = const Duration(minutes: 10),
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static const String _base = 'https://addons.mozilla.org/api/v5';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;
  final String lang;
  final Duration cacheFor;
  final DateTime Function() _clock;
  final Map<String, (DateTime, Object)> _cache = {};

  /// Searches extensions. [forAndroid] limits results to those that declare
  /// Firefox for Android support and returns Android download URLs.
  Future<AmoSearchPage> search(
    String query, {
    bool forAndroid = false,
    int page = 1,
    int pageSize = 20,
  }) async {
    final trimmed = query.trim();
    final params = <String, String>{
      'type': 'extension',
      'app': forAndroid ? 'android' : 'firefox',
      'lang': lang,
      'page': '$page',
      'page_size': '$pageSize',
      // An empty query lists the most used extensions, a sensible front page.
      if (trimmed.isNotEmpty) 'q': trimmed else 'sort': 'users',
    };
    final json = await _getJson('/addons/search/', params);
    final raw = json['results'];
    final results = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map((r) => AmoAddon.fromJson(r, lang: lang))
            .whereType<AmoAddon>()
            .toList()
        : <AmoAddon>[];
    return AmoSearchPage(
      results: results,
      total: (json['count'] as num?)?.toInt() ?? results.length,
      hasMore: json['next'] is String,
    );
  }

  /// One add-on by guid or slug, with its current version.
  Future<AmoAddon> details(String guidOrSlug, {bool forAndroid = false}) async {
    final json = await _getJson(
      '/addons/addon/${Uri.encodeComponent(guidOrSlug)}/',
      {'lang': lang, 'app': forAndroid ? 'android' : 'firefox'},
    );
    final addon = AmoAddon.fromJson(json, lang: lang);
    if (addon == null) {
      throw const AmoException(
          'addons.mozilla.org has no installable version of this extension.');
    }
    return addon;
  }

  Future<Map<String, dynamic>> _getJson(
      String path, Map<String, String> params) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: params);
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null && _clock().difference(cached.$1) < cacheFor) {
      return cached.$2 as Map<String, dynamic>;
    }

    final http.Response response;
    try {
      response = await _client.get(uri,
          headers: const {'Accept': 'application/json'}).timeout(_timeout);
    } on TimeoutException {
      throw const AmoException(
          'addons.mozilla.org did not answer. Check your connection.');
    } catch (_) {
      throw const AmoException(
          'Could not reach addons.mozilla.org. Check your connection.');
    }

    if (response.statusCode == 404) {
      throw const AmoException('That extension is not on addons.mozilla.org.');
    }
    if (response.statusCode == 429) {
      throw const AmoException(
          'addons.mozilla.org is rate limiting requests. Try again in a minute.');
    }
    if (response.statusCode != 200) {
      throw AmoException(
          'addons.mozilla.org returned an error (${response.statusCode}).');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const AmoException(
          'addons.mozilla.org sent a response the app could not read.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AmoException(
          'addons.mozilla.org sent a response the app could not read.');
    }
    _cache[key] = (_clock(), decoded);
    return decoded;
  }

  void close() => _client.close();
}
