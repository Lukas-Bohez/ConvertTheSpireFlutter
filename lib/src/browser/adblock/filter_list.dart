/// Ad-blocking rules from filter lists in the Adblock Plus syntax, the one
/// EasyList and EasyPrivacy are written in, reduced to what this browser
/// applies.
///
/// Like uBlock Origin it blocks requests to ad and tracker hosts and to ad
/// paths on hosts that also serve other things, honours the lists'
/// exceptions, and hides the page elements ads sit in. A rule it can't apply
/// as written is left out rather than applied more widely: `||cdn.com/ads/`
/// blocks that path, never all of cdn.com.
///
/// The Windows webview matches requests in C++ with the same rules
/// (`third_party/webview_windows/windows/request_blocker.cc`); a change to
/// [FilterSet.blocks] goes there too.
library;

/// A request rule scoped to a path on its host, to some pages, or both.
class UrlRule {
  const UrlRule(this.pattern, {this.onPages = const [], this.notOnPages = const []});

  /// What follows the host in the URL, in the filter syntax: `*` is any
  /// run of characters, `^` a separator or the end, a final `|` the end.
  /// Empty for the whole host.
  final String pattern;

  /// The rule applies on pages of these sites only (all when empty)...
  final List<String> onPages;

  /// ...and not on pages of these.
  final List<String> notOnPages;

  bool matches(String rest, String pageHost) {
    if (onPages.isNotEmpty &&
        !onPages.any((d) => FilterSet.isOnDomain(pageHost, d))) {
      return false;
    }
    if (notOnPages.any((d) => FilterSet.isOnDomain(pageHost, d))) return false;
    return pattern.isEmpty || FilterSet.patternMatches(pattern, rest);
  }

  List<String> toJson() =>
      [pattern, onPages.join('|'), notOnPages.join('|')];

  static UrlRule fromJson(List<dynamic> json) => UrlRule(
        json[0] as String,
        onPages: _split(json[1] as String),
        notOnPages: _split(json[2] as String),
      );

  static List<String> _split(String s) => s.isEmpty ? const [] : s.split('|');
}

class FilterSet {
  FilterSet({
    Set<String>? blockedHosts,
    Set<String>? allowedHosts,
    Map<String, List<UrlRule>>? rules,
    Map<String, List<UrlRule>>? exceptions,
    List<String>? genericHide,
    Map<String, List<String>>? specificHide,
    Map<String, List<String>>? hideExceptions,
    Set<String>? noHide,
    Set<String>? noGenericHide,
    Set<String>? allowedPages,
  })  : blockedHosts = blockedHosts ?? <String>{},
        allowedHosts = allowedHosts ?? <String>{},
        rules = rules ?? {},
        exceptions = exceptions ?? {},
        genericHide = genericHide ?? [],
        specificHide = specificHide ?? {},
        hideExceptions = hideExceptions ?? {},
        noHide = noHide ?? <String>{},
        noGenericHide = noGenericHide ?? <String>{},
        allowedPages = allowedPages ?? <String>{};

  /// Every request to these hosts and their subdomains is blocked...
  final Set<String> blockedHosts;

  /// ...unless the host is here (an exception rule).
  final Set<String> allowedHosts;

  /// Block rules with a path or limited to some pages, by host.
  final Map<String, List<UrlRule>> rules;

  /// Exception rules with a path or limited to some pages, by host.
  final Map<String, List<UrlRule>> exceptions;

  /// CSS selectors of elements hidden on every page.
  final List<String> genericHide;

  /// CSS selectors of elements hidden on one site's pages, by site.
  final Map<String, List<String>> specificHide;

  /// Selectors not hidden on a site's pages, by site.
  final Map<String, List<String>> hideExceptions;

  /// Sites where nothing is hidden.
  final Set<String> noHide;

  /// Sites where only their own selectors are hidden, not the generic ones.
  final Set<String> noGenericHide;

  /// Sites on whose pages nothing at all is blocked or hidden.
  final Set<String> allowedPages;

  int get ruleCount =>
      blockedHosts.length +
      rules.values.fold<int>(0, (n, l) => n + l.length) +
      genericHide.length +
      specificHide.values.fold<int>(0, (n, l) => n + l.length);

  /// Sites whose pages keep all their requests: YouTube's and Google's
  /// players depend on Google's ad hosts and stop working without them.
  static const exemptPages = ['youtube.com', 'youtube-nocookie.com', 'google.*'];

  // -------------------------------------------------------------- matching

  /// Whether [url], requested by the page at [pageUrl], is blocked. The
  /// page itself (a main-frame navigation) is never asked about.
  bool blocks(String url, {String? pageUrl}) {
    final split = splitUrl(url);
    if (split == null) return false;
    final (host, rest) = split;
    final pageHost = pageUrl == null ? '' : (splitUrl(pageUrl)?.$1 ?? '');
    if (pageHost.isNotEmpty) {
      if (exemptPages.any((d) => isOnDomain(pageHost, d))) return false;
      if (_onAnyOf(pageHost, allowedPages)) return false;
    }
    final candidates = hostAndParents(host);
    for (final h in candidates) {
      if (allowedHosts.contains(h)) return false;
      final list = exceptions[h];
      if (list != null && list.any((r) => r.matches(rest, pageHost))) {
        return false;
      }
    }
    for (final h in candidates) {
      if (blockedHosts.contains(h)) return true;
      final list = rules[h];
      if (list != null && list.any((r) => r.matches(rest, pageHost))) {
        return true;
      }
    }
    return false;
  }

  /// The selectors to hide on [host]'s pages besides the generic ones.
  List<String> selectorsFor(String host) {
    host = host.toLowerCase();
    if (_onAnyOf(host, allowedPages) || _onAnyOf(host, noHide)) return const [];
    final skip = exceptionsFor(host).toSet();
    final out = <String>[];
    for (final entry in specificHide.entries) {
      if (!isOnDomain(host, entry.key)) continue;
      for (final s in entry.value) {
        if (!skip.contains(s)) out.add(s);
      }
    }
    return out;
  }

  /// The selectors not to hide on [host]'s pages.
  List<String> exceptionsFor(String host) => [
        for (final entry in hideExceptions.entries)
          if (isOnDomain(host, entry.key)) ...entry.value,
      ];

  bool _onAnyOf(String host, Set<String> sites) =>
      hostAndParents(host).any(sites.contains);

  /// [host] and each parent domain, the top-level domain left out.
  static List<String> hostAndParents(String host) {
    final out = <String>[host];
    var i = host.indexOf('.');
    while (i >= 0) {
      final parent = host.substring(i + 1);
      if (!parent.contains('.')) break;
      out.add(parent);
      i = host.indexOf('.', i + 1);
    }
    return out;
  }

  /// Whether [host] is [domain] or under it. `example.*` stands for
  /// example under any top-level domain.
  static bool isOnDomain(String host, String domain) {
    if (host.isEmpty) return false;
    if (domain.endsWith('.*')) {
      final base = domain.substring(0, domain.length - 1);
      return host.startsWith(base) || host.contains('.$base');
    }
    return host == domain ||
        (host.length > domain.length &&
            host.endsWith(domain) &&
            host.codeUnitAt(host.length - domain.length - 1) == 0x2e);
  }

  /// The lowercase host of an http(s) or ws(s) [url] and what follows it
  /// (a port skipped), or null for any other URL.
  static (String, String)? splitUrl(String url) {
    final scheme = url.indexOf('://');
    if (scheme <= 0) return null;
    final s = url.substring(0, scheme).toLowerCase();
    if (s != 'http' && s != 'https' && s != 'ws' && s != 'wss') return null;
    var start = scheme + 3;
    var end = start;
    while (end < url.length) {
      final c = url.codeUnitAt(end);
      if (c == 0x2f || c == 0x3f || c == 0x23 || c == 0x3a) break; // / ? # :
      if (c == 0x40) start = end + 1; // user@host
      end++;
    }
    final host = url.substring(start, end).toLowerCase();
    if (host.isEmpty) return null;
    if (end < url.length && url.codeUnitAt(end) == 0x3a) {
      end++;
      while (end < url.length &&
          url.codeUnitAt(end) >= 0x30 &&
          url.codeUnitAt(end) <= 0x39) {
        end++;
      }
    }
    return (host, url.substring(end));
  }

  /// Whether the filter [pattern] matches [text] from its start.
  static bool patternMatches(String pattern, String text) {
    var p = pattern;
    final endAnchor = p.endsWith('|');
    if (endAnchor) p = p.substring(0, p.length - 1);
    final t = text.toLowerCase();
    var pi = 0, ti = 0, star = -1, mark = 0;
    while (true) {
      if (pi == p.length) {
        if (!endAnchor || ti == t.length) return true;
      } else {
        final c = p.codeUnitAt(pi);
        if (c == 0x2a) {
          // '*'
          star = pi++;
          mark = ti;
          continue;
        }
        if (ti < t.length &&
            (c == t.codeUnitAt(ti) ||
                (c == 0x5e && _isSeparator(t.codeUnitAt(ti))))) {
          pi++;
          ti++;
          continue;
        }
        if (ti == t.length && c == 0x5e) {
          // '^' also matches the end.
          pi++;
          continue;
        }
      }
      if (star < 0 || mark >= t.length) return false;
      pi = star + 1;
      ti = ++mark;
    }
  }

  /// Anything but a letter, a digit or one of `_-.%`.
  static bool _isSeparator(int c) =>
      !((c >= 0x61 && c <= 0x7a) ||
          (c >= 0x41 && c <= 0x5a) ||
          (c >= 0x30 && c <= 0x39) ||
          c == 0x5f ||
          c == 0x2d ||
          c == 0x2e ||
          c == 0x25);

  // --------------------------------------------------------------- parsing

  /// The rules of one or more filter lists, line by line.
  static FilterSet parse(Iterable<String> lines) {
    final set = FilterSet();
    for (final line in lines) {
      set._add(line.trim());
    }
    set._finish();
    return set;
  }

  final Set<String> _genericExceptions = {};

  void _add(String line) {
    if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) return;
    final hide = line.indexOf('##');
    final unhide = line.indexOf('#@#');
    if (unhide >= 0) {
      _cosmetic(line.substring(0, unhide), line.substring(unhide + 3),
          exception: true);
    } else if (hide >= 0) {
      _cosmetic(line.substring(0, hide), line.substring(hide + 2),
          exception: false);
    } else if (line.contains('#?#') ||
        line.contains(r'#$#') ||
        line.contains('#%#')) {
      return; // extended syntax this browser can't apply
    } else {
      _network(line);
    }
  }

  void _cosmetic(String domains, String selector, {required bool exception}) {
    if (!isPlainSelector(selector)) return;
    final on = <String>[], notOn = <String>[];
    for (var d in domains.split(',')) {
      d = d.trim().toLowerCase();
      if (d.isEmpty) continue;
      if (d.startsWith('~')) {
        notOn.add(d.substring(1));
      } else {
        on.add(d);
      }
    }
    if (exception) {
      if (on.isEmpty) {
        if (notOn.isEmpty) _genericExceptions.add(selector);
        return;
      }
      for (final d in on) {
        (hideExceptions[d] ??= []).add(selector);
      }
      return;
    }
    if (on.isEmpty) {
      // Everywhere but the sites it names.
      genericHide.add(selector);
      for (final d in notOn) {
        (hideExceptions[d] ??= []).add(selector);
      }
      return;
    }
    for (final d in on) {
      (specificHide[d] ??= []).add(selector);
    }
  }

  void _finish() {
    if (_genericExceptions.isNotEmpty) {
      genericHide.removeWhere(_genericExceptions.contains);
      _genericExceptions.clear();
    }
  }

  static const _ignoredOptions = {
    'third-party', '3p', 'script', 'image', 'stylesheet', 'css', 'object',
    'xmlhttprequest', 'xhr', 'subdocument', 'frame', 'media', 'font',
    'websocket', 'other', 'ping', 'beacon', 'important', 'match-case',
  };

  void _network(String line) {
    final exception = line.startsWith('@@');
    var body = exception ? line.substring(2) : line;
    // Only rules anchored to a host: matching every URL against the
    // unanchored ones would cost each request a scan of thousands.
    if (!body.startsWith('||')) return;
    body = body.substring(2);
    var options = const <String>[];
    final dollar = body.lastIndexOf(r'$');
    if (dollar >= 0) {
      options = body.substring(dollar + 1).toLowerCase().split(',');
      body = body.substring(0, dollar);
    }
    var i = 0;
    while (i < body.length && _isHostChar(body.codeUnitAt(i))) {
      i++;
    }
    final host = body.substring(0, i).toLowerCase();
    var rest = body.substring(i).toLowerCase();
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) {
      return; // a partial host, such as an IP prefix
    }
    if (rest.isNotEmpty && !'/^:?|'.contains(rest[0])) return;
    if (rest == '^' || rest == '|' || rest == '^|') rest = '';

    final on = <String>[], notOn = <String>[];
    var page = false, hideOff = false, genericOff = false;
    for (final option in options) {
      if (_ignoredOptions.contains(option)) continue;
      if (option.startsWith('domain=')) {
        for (final d in option.substring(7).split('|')) {
          if (d.startsWith('~')) {
            notOn.add(d.substring(1));
          } else if (d.isNotEmpty) {
            on.add(d);
          }
        }
        continue;
      }
      if (exception && (option == 'document' || option == 'doc')) {
        page = true;
      } else if (exception && (option == 'elemhide' || option == 'ehide')) {
        hideOff = true;
      } else if (exception &&
          (option == 'generichide' || option == 'ghide')) {
        genericOff = true;
      } else {
        // first-party only, popups, redirects, rewriting... not applied.
        return;
      }
    }

    if (page || hideOff || genericOff) {
      if (rest.isNotEmpty || on.isNotEmpty || notOn.isNotEmpty) return;
      if (page) allowedPages.add(host);
      if (hideOff) noHide.add(host);
      if (genericOff) noGenericHide.add(host);
      return;
    }
    if (rest.isEmpty && on.isEmpty && notOn.isEmpty) {
      (exception ? allowedHosts : blockedHosts).add(host);
      return;
    }
    final rule = UrlRule(rest, onPages: on, notOnPages: notOn);
    ((exception ? exceptions : rules)[host] ??= []).add(rule);
  }

  static bool _isHostChar(int c) =>
      (c >= 0x61 && c <= 0x7a) ||
      (c >= 0x41 && c <= 0x5a) ||
      (c >= 0x30 && c <= 0x39) ||
      c == 0x2e ||
      c == 0x2d ||
      c == 0x5f;

  static final _extended = RegExp(
      r':-abp-|:has-text\(|:upward\(|:xpath\(|:remove|:style\(|:matches-|'
      r':min-text-length\(|:watch-attr\(|:others\(|:if\(|:if-not\(|'
      r':nth-ancestor\(|:contains\(|:shadow');

  /// Whether [selector] is plain CSS a browser applies itself, not one of
  /// the extended selectors only uBlock Origin and AdGuard understand.
  static bool isPlainSelector(String selector) {
    if (selector.isEmpty) return false;
    if (selector.startsWith('+js(') || selector.startsWith('^')) return false;
    if (selector.contains('{') || selector.contains('}')) return false;
    if (_extended.hasMatch(selector)) return false;
    // Unbalanced brackets or quotes would swallow the rules after it in
    // the style sheet.
    final open = <int>[];
    int? quote;
    for (final c in selector.codeUnits) {
      if (quote != null) {
        if (c == quote) quote = null;
      } else if (c == 0x22 || c == 0x27) {
        quote = c;
      } else if (c == 0x28 || c == 0x5b) {
        open.add(c == 0x28 ? 0x29 : 0x5d);
      } else if (c == 0x29 || c == 0x5d) {
        if (open.isEmpty || open.removeLast() != c) return false;
      }
    }
    return quote == null && open.isEmpty;
  }

  // ----------------------------------------------------------- persistence

  Map<String, Object> toJson() => {
        'v': 1,
        'blockedHosts': blockedHosts.toList(),
        'allowedHosts': allowedHosts.toList(),
        'rules': _rulesJson(rules),
        'exceptions': _rulesJson(exceptions),
        'genericHide': genericHide,
        'specificHide': specificHide,
        'hideExceptions': hideExceptions,
        'noHide': noHide.toList(),
        'noGenericHide': noGenericHide.toList(),
        'allowedPages': allowedPages.toList(),
      };

  static Map<String, Object> _rulesJson(Map<String, List<UrlRule>> rules) => {
        for (final e in rules.entries)
          e.key: [for (final r in e.value) r.toJson()],
      };

  /// Null when [json] is not a filter set this version wrote.
  static FilterSet? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    Set<String> strings(String key) =>
        {...(json[key] as List).cast<String>()};
    Map<String, List<String>> selectors(String key) => {
          for (final e in (json[key] as Map).entries)
            e.key as String: (e.value as List).cast<String>(),
        };
    Map<String, List<UrlRule>> rules(String key) => {
          for (final e in (json[key] as Map).entries)
            e.key as String: [
              for (final r in e.value as List) UrlRule.fromJson(r as List),
            ],
        };
    return FilterSet(
      blockedHosts: strings('blockedHosts'),
      allowedHosts: strings('allowedHosts'),
      rules: rules('rules'),
      exceptions: rules('exceptions'),
      genericHide: (json['genericHide'] as List).cast<String>(),
      specificHide: selectors('specificHide'),
      hideExceptions: selectors('hideExceptions'),
      noHide: strings('noHide'),
      noGenericHide: strings('noGenericHide'),
      allowedPages: strings('allowedPages'),
    );
  }
}
