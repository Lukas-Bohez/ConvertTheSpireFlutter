import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'userscript.dart';

/// Stores installed userscripts and builds the JavaScript injected into pages.
///
/// The matching rules live in [userscript.dart] and are tested there; this
/// handles persistence, installing from a URL, and wrapping a script in the
/// small `GM_*` shim that Tampermonkey scripts expect to find.
class UserScriptService extends ChangeNotifier {
  static const String _prefsKey = 'browser_userscripts_v1';
  static const String _enabledKey = 'browser_userscripts_enabled';

  final List<UserScript> _scripts = [];
  bool _enabled = true;
  bool _loaded = false;

  List<UserScript> get scripts => List.unmodifiable(_scripts);

  /// Master switch. Off means nothing is injected, whatever is installed.
  bool get enabled => _enabled;

  int get enabledCount => _scripts.where((s) => s.enabled).length;

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              final script =
                  UserScript.fromJson(Map<String, dynamic>.from(entry));
              if (script != null) _scripts.add(script);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('UserScriptService: load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_scripts.map((s) => s.toJson()).toList()));
      await prefs.setBool(_enabledKey, _enabled);
    } catch (e) {
      debugPrint('UserScriptService: save failed: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _save();
    notifyListeners();
  }

  /// Installs from raw source. Returns the script, or null if [source] has no
  /// userscript header — pasting arbitrary JavaScript should fail loudly
  /// rather than install something that silently never runs.
  Future<UserScript?> installFromSource(String source,
      {String? downloadUrl}) async {
    var parsed = parseUserScript(source, downloadUrl: downloadUrl);
    if (parsed == null) return null;
    // Fetch @require libraries now and cache them, so a page load never waits
    // on the network and the script still works offline afterwards.
    if (parsed.requires.isNotEmpty) {
      parsed = parsed.copyWith(
          requiredSources: await _fetchRequires(parsed.requires));
    }
    final existing = _scripts.indexWhere((s) => s.id == parsed!.id);
    if (existing >= 0) {
      // Keep the user's on/off choice across an update.
      _scripts[existing] =
          parsed.copyWith(enabled: _scripts[existing].enabled);
    } else {
      _scripts.add(parsed);
    }
    await _save();
    notifyListeners();
    return parsed;
  }

  /// Downloads each `@require` URL. A library that fails to download is left
  /// out rather than blocking the install; the script still runs, and the
  /// missing symbol shows up in the page console.
  Future<Map<String, String>> _fetchRequires(List<String> urls) async {
    final out = <String, String>{};
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200) out[url] = response.body;
      } catch (e) {
        debugPrint('UserScriptService: @require $url failed: $e');
      }
    }
    return out;
  }

  /// Downloads and installs a `.user.js` file.
  /// Returns null on success, or a message to show the user.
  Future<String?> installFromUrl(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return 'Download failed (HTTP ${response.statusCode}).';
      }
      final installed =
          await installFromSource(response.body, downloadUrl: url);
      if (installed == null) {
        return 'That file is not a userscript — it has no '
            '// ==UserScript== header.';
      }
      return null;
    } catch (e) {
      return 'Could not download the script: $e';
    }
  }

  Future<void> remove(String id) async {
    _scripts.removeWhere((s) => s.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> toggleScript(String id) async {
    final index = _scripts.indexWhere((s) => s.id == id);
    if (index < 0) return;
    _scripts[index] = _scripts[index].copyWith(
      enabled: !_scripts[index].enabled,
    );
    await _save();
    notifyListeners();
  }

  /// Re-downloads every script that recorded where it came from.
  Future<int> updateAll() async {
    var updated = 0;
    for (final script in List<UserScript>.from(_scripts)) {
      final url = script.downloadUrl;
      if (url == null || url.isEmpty) continue;
      if (await installFromUrl(url) == null) updated++;
    }
    return updated;
  }

  /// Enabled scripts that apply to [url], for a given injection time.
  List<UserScript> scriptsFor(String url, {required UserScriptRunAt runAt}) {
    if (!_enabled) return const [];
    return _scripts.where((script) {
      if (!script.enabled) return false;
      // document-idle has no separate injection point in a webview, so it is
      // folded into document-end, which is where such scripts expect the DOM
      // to already exist.
      final effective = script.runAt == UserScriptRunAt.documentIdle
          ? UserScriptRunAt.documentEnd
          : script.runAt;
      if (effective != runAt) return false;
      return script.matchesUrl(url);
    }).toList();
  }

  /// The JavaScript to inject for [script].
  ///
  /// Wrapped in an IIFE so a script cannot collide with the page's own
  /// variables, and in a try/catch so a broken script logs instead of taking
  /// the page down with it.
  static String wrapForInjection(UserScript script) {
    final info = jsonEncode({
      'script': {
        'name': script.name,
        'namespace': script.namespace,
        'version': script.version,
        'description': script.description,
        'author': script.author,
      },
      'scriptHandler': 'BitPlayer',
      'version': '1.0',
    });
    final storagePrefix = jsonEncode('__gm_${script.id}_');
    final label = jsonEncode('[userscript: ${script.name}]');

    // @noframes: bail out immediately inside an iframe. Checked in JS rather
    // than in Dart because only the page knows whether it is framed.
    final frameGuard = script.noFrames
        ? '  if (window.top !== window.self) { return; }'
        : '';

    return '''
(function () {
$frameGuard
  var GM_info = $info;
  var __p = $storagePrefix;
  var unsafeWindow = window;
  function GM_log() { try { console.log.apply(console, arguments); } catch (e) {} }
  function GM_addStyle(css) {
    try {
      var el = document.createElement('style');
      el.textContent = css;
      (document.head || document.documentElement).appendChild(el);
      return el;
    } catch (e) { return null; }
  }
  function GM_setValue(key, value) {
    try { localStorage.setItem(__p + key, JSON.stringify(value)); } catch (e) {}
  }
  function GM_getValue(key, fallback) {
    try {
      var raw = localStorage.getItem(__p + key);
      return raw === null ? fallback : JSON.parse(raw);
    } catch (e) { return fallback; }
  }
  function GM_deleteValue(key) {
    try { localStorage.removeItem(__p + key); } catch (e) {}
  }
  function GM_listValues() {
    var out = [];
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (k && k.indexOf(__p) === 0) out.push(k.slice(__p.length));
      }
    } catch (e) {}
    return out;
  }
  function GM_openInTab(url) { try { return window.open(url, '_blank'); } catch (e) { return null; } }
  function GM_setClipboard(text) {
    try { navigator.clipboard && navigator.clipboard.writeText(text); } catch (e) {}
  }
  // Subject to the page's CORS rules, unlike a real extension. Scripts that
  // need genuinely cross-origin requests will not work here.
  function GM_xmlhttpRequest(opts) {
    try {
      opts = opts || {};
      return fetch(opts.url, {
        method: opts.method || 'GET',
        headers: opts.headers || {},
        body: opts.data
      }).then(function (r) {
        return r.text().then(function (t) {
          if (opts.onload) opts.onload({ status: r.status, responseText: t, finalUrl: r.url });
        });
      })['catch'](function (e) { if (opts.onerror) opts.onerror(e); });
    } catch (e) { if (opts && opts.onerror) opts.onerror(e); }
  }
  var GM = {
    info: GM_info,
    setValue: function (k, v) { return Promise.resolve(GM_setValue(k, v)); },
    getValue: function (k, d) { return Promise.resolve(GM_getValue(k, d)); },
    deleteValue: function (k) { return Promise.resolve(GM_deleteValue(k)); },
    listValues: function () { return Promise.resolve(GM_listValues()); },
    addStyle: function (c) { return Promise.resolve(GM_addStyle(c)); },
    openInTab: GM_openInTab,
    setClipboard: GM_setClipboard,
    xmlHttpRequest: GM_xmlhttpRequest
  };
  try {
${_requireBlock(script)}$_bodyMarker
${script.source}
  } catch (e) {
    try { console.error($label, e); } catch (_) {}
  }
})();
''';
  }

  /// `@require` libraries, inlined ahead of the script body.
  static String _requireBlock(UserScript script) {
    if (script.requiredSources.isEmpty) return '';
    final buffer = StringBuffer();
    for (final url in script.requires) {
      final body = script.requiredSources[url];
      if (body == null || body.isEmpty) continue;
      buffer.writeln('// @require $url');
      buffer.writeln(body);
    }
    return buffer.toString();
  }

  static const String _bodyMarker = '// --- userscript body ---';

  /// All injectable JavaScript for [url] at [runAt], already wrapped.
  List<String> injectionsFor(String url, {required UserScriptRunAt runAt}) =>
      scriptsFor(url, runAt: runAt).map(wrapForInjection).toList();

  @visibleForTesting
  void seedForTesting(List<UserScript> scripts, {bool enabled = true}) {
    _loaded = true;
    _scripts
      ..clear()
      ..addAll(scripts);
    _enabled = enabled;
  }
}
