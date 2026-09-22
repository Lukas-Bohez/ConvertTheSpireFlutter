/// Userscript model, metadata parsing and URL matching.
///
/// Greasemonkey/Tampermonkey-compatible: a script is plain JavaScript with a
/// `// ==UserScript== … // ==/UserScript==` header describing where it runs.
/// Most Tampermonkey scripts run unmodified.
///
/// Free of Flutter and I/O so the matching rules — the part that decides
/// whether someone's script fires on their bank's website — can be tested
/// directly.
library;

/// When a script runs relative to page load.
enum UserScriptRunAt {
  /// Before the page's own scripts. Used by scripts that patch APIs.
  documentStart,

  /// After the DOM is parsed. The default, and what most scripts expect.
  documentEnd,

  /// After everything (images included). Treated as document-end, because the
  /// webview has no separate idle injection point.
  documentIdle,
}

class UserScript {
  UserScript({
    required this.id,
    required this.name,
    required this.source,
    this.namespace = '',
    this.version = '',
    this.description = '',
    this.author = '',
    this.matches = const [],
    this.includes = const [],
    this.excludes = const [],
    this.grants = const [],
    this.requires = const [],
    this.runAt = UserScriptRunAt.documentEnd,
    this.enabled = true,
    this.noFrames = false,
    this.downloadUrl,
    this.requiredSources = const {},
  });

  final String id;
  final String name;
  final String namespace;
  final String version;
  final String description;
  final String author;

  /// Chrome-style `@match` patterns.
  final List<String> matches;

  /// Greasemonkey-style `@include` globs (or `/regex/`).
  final List<String> includes;

  /// `@exclude` rules; these win over any match or include.
  final List<String> excludes;

  final List<String> grants;

  /// `@require` URLs — libraries the script expects to be loaded first.
  final List<String> requires;

  final UserScriptRunAt runAt;
  final bool enabled;

  /// `@noframes`: run only in the top-level page, not inside iframes.
  final bool noFrames;

  /// Downloaded `@require` bodies, keyed by URL. Cached at install time so a
  /// page load never waits on the network.
  final Map<String, String> requiredSources;

  /// Where it was installed from, for updates.
  final String? downloadUrl;

  /// The raw JavaScript, header included.
  final String source;

  UserScript copyWith({
    bool? enabled,
    String? source,
    String? version,
    Map<String, String>? requiredSources,
  }) =>
      UserScript(
        id: id,
        name: name,
        namespace: namespace,
        version: version ?? this.version,
        description: description,
        author: author,
        matches: matches,
        includes: includes,
        excludes: excludes,
        grants: grants,
        requires: requires,
        runAt: runAt,
        enabled: enabled ?? this.enabled,
        noFrames: noFrames,
        downloadUrl: downloadUrl,
        requiredSources: requiredSources ?? this.requiredSources,
        source: source ?? this.source,
      );

  /// True when this script should run on [url].
  ///
  /// Excludes are checked first and always win — that is what stops a script
  /// leaking onto a page the author deliberately kept it off.
  bool matchesUrl(String url) {
    if (excludes.any((rule) => _ruleMatches(rule, url))) return false;
    if (matches.any((pattern) => matchPatternMatches(pattern, url))) return true;
    if (includes.any((rule) => _ruleMatches(rule, url))) return true;
    return false;
  }

  static bool _ruleMatches(String rule, String url) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return false;
    // A rule wrapped in slashes is a regular expression.
    if (trimmed.length > 1 && trimmed.startsWith('/') && trimmed.endsWith('/')) {
      try {
        return RegExp(trimmed.substring(1, trimmed.length - 1)).hasMatch(url);
      } catch (_) {
        return false;
      }
    }
    return globMatches(trimmed, url);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'namespace': namespace,
        'version': version,
        'description': description,
        'author': author,
        'matches': matches,
        'includes': includes,
        'excludes': excludes,
        'grants': grants,
        'requires': requires,
        'runAt': runAt.name,
        'enabled': enabled,
        'noFrames': noFrames,
        'downloadUrl': downloadUrl,
        'requiredSources': requiredSources,
        'source': source,
      };

  static UserScript? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final source = json['source'];
    if (id is! String || source is! String) return null;
    List<String> list(String key) {
      final value = json[key];
      if (value is! List) return const [];
      return value.whereType<String>().toList();
    }

    return UserScript(
      id: id,
      name: json['name'] is String ? json['name'] as String : 'Untitled script',
      namespace: json['namespace'] is String ? json['namespace'] as String : '',
      version: json['version'] is String ? json['version'] as String : '',
      description:
          json['description'] is String ? json['description'] as String : '',
      author: json['author'] is String ? json['author'] as String : '',
      matches: list('matches'),
      includes: list('includes'),
      excludes: list('excludes'),
      grants: list('grants'),
      requires: list('requires'),
      noFrames: json['noFrames'] is bool ? json['noFrames'] as bool : false,
      requiredSources: json['requiredSources'] is Map
          ? Map<String, String>.from(
              (json['requiredSources'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          : const {},
      runAt: UserScriptRunAt.values.firstWhere(
        (v) => v.name == json['runAt'],
        orElse: () => UserScriptRunAt.documentEnd,
      ),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      downloadUrl:
          json['downloadUrl'] is String ? json['downloadUrl'] as String : null,
      source: source,
    );
  }
}

/// Converts a glob (where `*` matches any run of characters) into a regex and
/// tests it. Anchored at both ends so `*.example.com/*` cannot match a URL
/// that merely contains it.
bool globMatches(String glob, String url) {
  final buffer = StringBuffer('^');
  for (final rune in glob.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '*') {
      buffer.write('.*');
    } else {
      buffer.write(RegExp.escape(ch));
    }
  }
  buffer.write(r'$');
  try {
    return RegExp(buffer.toString()).hasMatch(url);
  } catch (_) {
    return false;
  }
}

/// Implements Chrome's match-pattern syntax: `<scheme>://<host><path>`.
///
/// Scheme may be `*` (http or https only, per the spec), or a literal scheme.
/// Host may be `*`, `*.domain` (the domain *and* its subdomains), or a literal
/// host. Path is a glob. `<all_urls>` matches anything.
bool matchPatternMatches(String pattern, String url) {
  final rule = pattern.trim();
  if (rule.isEmpty) return false;
  if (rule == '<all_urls>') return true;

  final schemeSplit = rule.indexOf('://');
  if (schemeSplit < 0) return false;
  final scheme = rule.substring(0, schemeSplit);
  final remainder = rule.substring(schemeSplit + 3);
  if (remainder.isEmpty) return false;

  final pathStart = remainder.indexOf('/');
  // A pattern must specify a path; Chrome rejects "https://example.com".
  if (pathStart < 0) return false;
  final hostPattern = remainder.substring(0, pathStart);
  final pathPattern = remainder.substring(pathStart);

  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return false;
  }
  if (uri.host.isEmpty) return false;

  // Scheme
  if (scheme == '*') {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  } else if (scheme != uri.scheme) {
    return false;
  }

  // Host
  final host = uri.host.toLowerCase();
  if (hostPattern != '*') {
    if (hostPattern.startsWith('*.')) {
      final domain = hostPattern.substring(2).toLowerCase();
      // "*.example.com" covers example.com and any subdomain of it, but must
      // not match "notexample.com".
      if (host != domain && !host.endsWith('.$domain')) return false;
    } else if (host != hostPattern.toLowerCase()) {
      return false;
    }
  }

  // Path (query string included, as Tampermonkey does)
  final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  return globMatches(pathPattern, path.isEmpty ? '/' : path);
}

/// Parses the `// ==UserScript== … // ==/UserScript==` header.
///
/// Returns null when there is no header at all — that is how a paste of
/// something that is not a userscript is rejected rather than installed as a
/// script that never runs.
UserScript? parseUserScript(String source, {String? id, String? downloadUrl}) {
  final headerMatch = RegExp(
    r'//\s*==UserScript==\s*\n(.*?)//\s*==/UserScript==',
    dotAll: true,
  ).firstMatch(source);
  if (headerMatch == null) return null;

  final header = headerMatch.group(1) ?? '';
  final values = <String, List<String>>{};
  for (final rawLine in header.split('\n')) {
    final line = rawLine.trim();
    if (!line.startsWith('//')) continue;
    final body = line.substring(2).trim();
    if (!body.startsWith('@')) continue;
    final space = body.indexOf(RegExp(r'\s'));
    if (space < 0) {
      // A valueless directive such as "@noframes".
      values.putIfAbsent(body.substring(1).toLowerCase(), () => []).add('');
      continue;
    }
    final key = body.substring(1, space).toLowerCase();
    final value = body.substring(space).trim();
    if (value.isEmpty) continue;
    values.putIfAbsent(key, () => []).add(value);
  }

  String first(String key) {
    final list = values[key];
    return (list == null || list.isEmpty) ? '' : list.first;
  }

  final runAtRaw = first('run-at');
  final runAt = switch (runAtRaw) {
    'document-start' => UserScriptRunAt.documentStart,
    'document-idle' => UserScriptRunAt.documentIdle,
    _ => UserScriptRunAt.documentEnd,
  };

  final name = first('name');
  final namespace = first('namespace');
  return UserScript(
    id: id ??
        ((namespace.isEmpty ? name : '$namespace/$name').isEmpty
            ? 'script-${source.hashCode.toUnsigned(32)}'
            : '$namespace/$name'),
    name: name.isEmpty ? 'Untitled script' : name,
    namespace: namespace,
    version: first('version'),
    description: first('description'),
    author: first('author'),
    matches: values['match'] ?? const [],
    includes: values['include'] ?? const [],
    excludes: [...?values['exclude'], ...?values['excludematch']],
    grants: values['grant'] ?? const [],
    requires: values['require'] ?? const [],
    noFrames: values.containsKey('noframes'),
    runAt: runAt,
    downloadUrl: downloadUrl ?? (first('downloadurl').isEmpty
        ? null
        : first('downloadurl')),
    source: source,
  );
}
