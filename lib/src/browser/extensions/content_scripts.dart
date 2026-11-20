import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../js/js_bridge.dart';
import '../userscripts/userscript.dart' show globMatches, matchPatternMatches;
import 'extension_package.dart';

/// The bridge handler that carries `chrome.storage` writes from a page to the
/// app, which keeps them for the next page.
const String extensionStorageHandler = 'ctsExtStorage';

/// One `content_scripts` entry of a manifest, with its files already read.
class ContentScriptEntry {
  const ContentScriptEntry({
    required this.matches,
    this.excludeMatches = const [],
    this.includeGlobs = const [],
    this.excludeGlobs = const [],
    this.js = const [],
    this.css = const [],
    this.atDocumentStart = false,
    this.allFrames = false,
  });

  final List<String> matches;
  final List<String> excludeMatches;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;

  /// File contents, in manifest order.
  final List<String> js;
  final List<String> css;

  /// `run_at: document_start`. `document_end` and `document_idle` (the
  /// default) both run once the page has loaded.
  final bool atDocumentStart;
  final bool allFrames;

  /// Chrome's rule: a URL must match a `matches` pattern and, when
  /// `include_globs` is given, one of those globs; any exclusion wins.
  bool appliesTo(String url) {
    if (!matches.any((m) => matchPatternMatches(m, url))) return false;
    if (includeGlobs.isNotEmpty && !includeGlobs.any((g) => globMatches(g, url))) {
      return false;
    }
    if (excludeMatches.any((m) => matchPatternMatches(m, url))) return false;
    if (excludeGlobs.any((g) => globMatches(g, url))) return false;
    return true;
  }
}

/// An installed extension in the form the page needs: its content scripts,
/// its translations and the small files it may load from its own package.
///
/// This is how extensions run where the web view cannot host them (Android,
/// Android TV, iOS, macOS, Linux): the scripts an extension adds to pages run
/// as they would in Chrome or Firefox, with `chrome.*` / `browser.*` storage,
/// i18n and runtime. Background pages, popups and network blocking need an
/// engine's extension runtime and do not run here.
class ContentScriptBundle {
  ContentScriptBundle({
    required this.id,
    required this.name,
    required this.manifest,
    required this.entries,
    this.messages = const {},
    this.resources = const {},
  });

  final String id;
  final String name;
  final Map<String, dynamic> manifest;
  final List<ContentScriptEntry> entries;

  /// `_locales` messages, keys lower-cased as Chrome looks them up.
  final Map<String, Object?> messages;

  /// `web_accessible_resources` small enough to hand over as data: URLs.
  final Map<String, String> resources;

  /// Largest single resource inlined for `runtime.getURL`, and the total.
  static const int maxResourceBytes = 128 * 1024;
  static const int maxResourceTotal = 512 * 1024;

  /// Reads the extension unpacked in [folder].
  ///
  /// Throws [ExtensionPackageException] when a file the manifest names is
  /// missing, so a broken package fails at install, not silently on a page.
  static Future<ContentScriptBundle> load({
    required String id,
    required Directory folder,
    required String uiLanguage,
  }) async {
    final manifest = await manifestFromFolder(folder);
    final raw = manifest.raw;
    final messages = await _loadMessages(folder, manifest.defaultLocale, uiLanguage);

    Future<String> read(String relative) async {
      final clean = relative.replaceFirst(RegExp(r'^/+'), '');
      final path = p.normalize(p.join(folder.path, clean));
      if (!p.isWithin(folder.path, path)) {
        throw ExtensionPackageException(
            'The extension points outside its folder ($relative).');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw ExtensionPackageException(
            'The extension is missing a file it needs ($relative).');
      }
      return utf8.decode(await file.readAsBytes(), allowMalformed: true);
    }

    List<String> strings(Object? value) =>
        value is List ? value.whereType<String>().toList() : const [];

    final entries = <ContentScriptEntry>[];
    final declared = raw['content_scripts'];
    if (declared is List) {
      for (final item in declared.whereType<Map>()) {
        final matches = strings(item['matches']);
        if (matches.isEmpty) continue;
        entries.add(ContentScriptEntry(
          matches: matches,
          excludeMatches: strings(item['exclude_matches']),
          includeGlobs: strings(item['include_globs']),
          excludeGlobs: strings(item['exclude_globs']),
          js: [for (final f in strings(item['js'])) await read(f)],
          css: [
            for (final f in strings(item['css']))
              _localiseCss(await read(f), messages, id)
          ],
          atDocumentStart: item['run_at'] == 'document_start',
          allFrames: item['all_frames'] == true,
        ));
      }
    }

    return ContentScriptBundle(
      id: id,
      name: resolveMessage(manifest.name, messages),
      manifest: raw,
      entries: entries,
      messages: messages,
      resources: await _loadResources(folder, raw),
    );
  }

  /// The scripts to run on [url]: at document start only the
  /// `document_start` entries; once loaded, every entry, so a start script
  /// that went into the previous page during navigation still runs in this
  /// one. Each entry runs once per page however often it is offered.
  List<String> injectionsFor(
    String url, {
    required bool atDocumentStart,
    required Map<String, Object?> storage,
    required String uiLanguage,
    required String os,
  }) {
    final out = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (atDocumentStart && !entry.atDocumentStart) continue;
      if (!entry.appliesTo(url)) continue;
      out.add(_wrap(entry, i,
          storage: storage, uiLanguage: uiLanguage, os: os));
    }
    return out;
  }

  String _wrap(
    ContentScriptEntry entry,
    int index, {
    required Map<String, Object?> storage,
    required String uiLanguage,
    required String os,
  }) {
    final meta = jsonEncode({
      'id': id,
      'name': name,
      'manifest': manifest,
      'messages': messages,
      'resources': resources,
      'storage': storage,
      'uiLang': uiLanguage,
      'os': os,
      'base': '${manifest['browser_specific_settings'] != null ? 'moz' : 'chrome'}-extension://$id/',
    });
    final key = jsonEncode('$id#$index');
    final label = jsonEncode('[extension: $name]');
    final css = jsonEncode(entry.css);
    // Each file ends with a newline and a semicolon so a file without a
    // trailing newline cannot swallow the next one into a comment.
    final js = entry.js.map((s) => '$s\n;').join('\n');
    return withJsBridge('''
(function () {
  var W = window;
  if (!W.__ctsExt) {
    try { Object.defineProperty(W, '__ctsExt', { value: { api: {}, done: {} }, enumerable: false }); }
    catch (e) { return; }
  }
  var R = W.__ctsExt, KEY = $key;
  if (R.done[KEY]) return;
  if (W.top !== W.self && ${entry.allFrames ? 'false' : 'true'}) return;
  R.done[KEY] = true;
  var M = $meta;
  var api = R.api[M.id] || (R.api[M.id] = ($_apiFactoryJs)(M));
  var css = $css;
  function addCss() {
    for (var i = 0; i < css.length; i++) {
      var sid = '__cts_' + M.id + '_' + KEY.split('#')[1] + '_' + i;
      if (document.getElementById(sid)) continue;
      var el = document.createElement('style');
      el.id = sid;
      el.textContent = css[i];
      (document.head || document.documentElement).appendChild(el);
    }
  }
  if (css.length) {
    if (document.documentElement) addCss();
    else document.addEventListener('DOMContentLoaded', addCss);
  }
  (function (chrome, browser) {
    try {
$js
    } catch (e) {
      try { console.error($label, e); } catch (_) {}
    }
  }).call(W, api, api);
})();
''');
  }

  // --------------------------------------------------------------- loading

  static Future<Map<String, Object?>> _loadMessages(
      Directory folder, String? defaultLocale, String uiLanguage) async {
    final out = <String, Object?>{};
    Future<void> merge(String locale) async {
      final file = File(p.join(folder.path, '_locales', locale, 'messages.json'));
      if (!await file.exists()) return;
      try {
        final decoded = jsonDecode(
            utf8.decode(await file.readAsBytes(), allowMalformed: true));
        if (decoded is! Map) return;
        decoded.forEach((key, value) {
          if (key is! String || value is! Map) return;
          final placeholders = value['placeholders'];
          out[key.toLowerCase()] = {
            'message': value['message'] is String ? value['message'] : '',
            if (placeholders is Map)
              'placeholders': {
                for (final e in placeholders.entries)
                  if (e.key is String && e.value is Map)
                    (e.key as String).toLowerCase(): {
                      'content': (e.value as Map)['content'] is String
                          ? (e.value as Map)['content']
                          : ''
                    }
              },
          };
        });
      } catch (_) {
        // A broken translation file leaves the keys it would have set empty.
      }
    }

    // Chrome's order: the default locale, then the language, then the
    // language with its region - the most specific wins.
    final tag = uiLanguage.replaceAll('-', '_');
    final language = tag.split('_').first;
    if (defaultLocale != null) await merge(defaultLocale);
    if (language != defaultLocale) await merge(language);
    if (tag != language && tag != defaultLocale) await merge(tag);
    return out;
  }

  static Future<Map<String, String>> _loadResources(
      Directory folder, Map<String, dynamic> manifest) async {
    final declared = manifest['web_accessible_resources'];
    final patterns = <String>[];
    if (declared is List) {
      for (final item in declared) {
        if (item is String) patterns.add(item);
        if (item is Map && item['resources'] is List) {
          patterns.addAll((item['resources'] as List).whereType<String>());
        }
      }
    }
    if (patterns.isEmpty) return const {};

    final out = <String, String>{};
    var total = 0;
    final files = await folder
        .list(recursive: true, followLinks: false)
        .where((e) => e is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final relative = p.relative(file.path, from: folder.path).replaceAll('\\', '/');
      if (!patterns.any((pattern) =>
          globMatches(pattern.replaceFirst(RegExp(r'^/+'), ''), relative))) {
        continue;
      }
      final mime = _mimeOf(relative);
      if (mime == null) continue;
      final length = await file.length();
      if (length > maxResourceBytes || total + length > maxResourceTotal) continue;
      total += length;
      out[relative] = 'data:$mime;base64,${base64Encode(await file.readAsBytes())}';
    }
    return out;
  }

  static String? _mimeOf(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
      '.ico': 'image/x-icon',
      '.css': 'text/css',
      '.js': 'text/javascript',
      '.json': 'application/json',
      '.html': 'text/html',
      '.txt': 'text/plain',
      '.woff': 'font/woff',
      '.woff2': 'font/woff2',
      '.ttf': 'font/ttf',
      '.mp3': 'audio/mpeg',
      '.ogg': 'audio/ogg',
      '.wav': 'audio/wav',
    }[ext];
  }

  /// `__MSG_name__` placeholders in CSS, as Chrome fills them in.
  static String _localiseCss(
          String css, Map<String, Object?> messages, String id) =>
      css.replaceAllMapped(RegExp(r'__MSG_([A-Za-z0-9_@]+)__'), (m) {
        final key = m.group(1)!.toLowerCase();
        if (key == '@@extension_id') return id;
        if (key == '@@bidi_dir') return 'ltr';
        if (key == '@@bidi_reversed_dir') return 'rtl';
        if (key == '@@bidi_start_edge') return 'left';
        if (key == '@@bidi_end_edge') return 'right';
        final entry = messages[key];
        return entry is Map ? '${entry['message'] ?? ''}' : '';
      });
}

/// A manifest string such as `__MSG_appName__` resolved from [messages];
/// anything else comes back unchanged.
String resolveMessage(String value, Map<String, Object?> messages) {
  final match = RegExp(r'^__MSG_([A-Za-z0-9_@]+)__$').firstMatch(value.trim());
  if (match == null) return value;
  final entry = messages[match.group(1)!.toLowerCase()];
  final text = entry is Map ? '${entry['message'] ?? ''}'.trim() : '';
  return text.isEmpty ? value : text;
}

/// Builds the `chrome` / `browser` object a content script sees.
///
/// What a content script can use in Chrome and Firefox: `runtime` (id,
/// manifest, getURL, messaging), `i18n`, `storage` (local, sync, session,
/// managed, onChanged), `extension` and `permissions`. Storage writes go to
/// the app, which persists them and hands them to the next page. Messages to
/// a background page fail the way they do in Chrome when nothing listens.
const String _apiFactoryJs = r'''
function (M) {
  var W = window;
  function ev() {
    var l = [];
    return {
      addListener: function (f) { if (typeof f === 'function' && l.indexOf(f) < 0) l.push(f); },
      removeListener: function (f) { var i = l.indexOf(f); if (i >= 0) l.splice(i, 1); },
      hasListener: function (f) { return l.indexOf(f) >= 0; },
      hasListeners: function () { return l.length > 0; },
      _fire: function () {
        var a = arguments;
        l.slice().forEach(function (f) { try { f.apply(null, a); } catch (e) { console.error(e); } });
      }
    };
  }
  function lastFn(args) {
    var f = args.length ? args[args.length - 1] : null;
    return typeof f === 'function' ? f : null;
  }
  function reply(f, v) {
    if (f) { try { f(v); } catch (e) { console.error(e); } return undefined; }
    return Promise.resolve(v);
  }
  function clone(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)); }
  function post(msg) {
    msg.id = M.id;
    try { if (W.__bbCall) W.__bbCall('ctsExtStorage', JSON.stringify(msg)); } catch (e) {}
  }
  var changed = ev();
  function area(name, writable) {
    var data = (M.storage && M.storage[name]) || {};
    var own = ev();
    function fire(changes) {
      if (!Object.keys(changes).length) return;
      own._fire(changes);
      changed._fire(changes, name);
    }
    function readOnly(f) {
      var err = new Error('This storage area is read-only.');
      if (f) { api.runtime.lastError = err; try { f(); } finally { api.runtime.lastError = undefined; } return undefined; }
      return Promise.reject(err);
    }
    return {
      get: function (keys) {
        var f = lastFn(arguments);
        if (typeof keys === 'function') keys = null;
        var out = {}, k;
        if (keys === null || keys === undefined) { for (k in data) out[k] = clone(data[k]); }
        else if (typeof keys === 'string') { if (keys in data) out[keys] = clone(data[keys]); }
        else if (Array.isArray(keys)) { keys.forEach(function (key) { if (key in data) out[key] = clone(data[key]); }); }
        else if (typeof keys === 'object') { for (k in keys) out[k] = k in data ? clone(data[k]) : keys[k]; }
        return reply(f, out);
      },
      set: function (items) {
        var f = lastFn(arguments);
        if (!writable) return readOnly(f);
        var changes = {};
        items = clone(items || {}) || {};
        for (var k in items) {
          changes[k] = { oldValue: clone(data[k]), newValue: clone(items[k]) };
          data[k] = items[k];
        }
        post({ area: name, set: items });
        fire(changes);
        return reply(f);
      },
      remove: function (keys) {
        var f = lastFn(arguments);
        if (!writable) return readOnly(f);
        if (typeof keys === 'string') keys = [keys];
        keys = Array.isArray(keys) ? keys : [];
        var changes = {};
        keys.forEach(function (k) { if (k in data) { changes[k] = { oldValue: data[k] }; delete data[k]; } });
        post({ area: name, remove: keys });
        fire(changes);
        return reply(f);
      },
      clear: function () {
        var f = lastFn(arguments);
        if (!writable) return readOnly(f);
        var changes = {};
        for (var k in data) changes[k] = { oldValue: data[k] };
        data = {};
        post({ area: name, clear: true });
        fire(changes);
        return reply(f);
      },
      getBytesInUse: function () { return reply(lastFn(arguments), JSON.stringify(data).length); },
      getKeys: function () { return reply(lastFn(arguments), Object.keys(data)); },
      setAccessLevel: function () { return reply(lastFn(arguments)); },
      onChanged: own,
      QUOTA_BYTES: 10485760
    };
  }
  function subst(text, subs) {
    return text.replace(/\$(\d)/g, function (m, i) { var v = subs[+i - 1]; return v == null ? '' : String(v); });
  }
  function getMessage(name, subs) {
    if (name == null) return '';
    var key = String(name).toLowerCase();
    if (key === '@@extension_id') return M.id;
    if (key === '@@ui_locale') return M.uiLang.replace('-', '_');
    if (key === '@@bidi_dir') return 'ltr';
    if (key === '@@bidi_reversed_dir') return 'rtl';
    if (key === '@@bidi_start_edge') return 'left';
    if (key === '@@bidi_end_edge') return 'right';
    var e = M.messages[key];
    if (!e) return '';
    if (subs === undefined || subs === null) subs = [];
    if (!Array.isArray(subs)) subs = [subs];
    var ph = e.placeholders || {};
    var text = String(e.message || '').replace(/\$([A-Za-z0-9_@]+)\$/g, function (m, n) {
      var p = ph[n.toLowerCase()];
      return p ? subst(String(p.content || ''), subs) : m;
    });
    return subst(text, subs).replace(/\$\$/g, '$');
  }
  function getURL(path) {
    path = String(path || '').replace(/^\/+/, '');
    return M.resources[path] || (M.base + path);
  }
  function noReceiver(args) {
    var f = lastFn(args);
    var err = new Error('Could not establish connection. Receiving end does not exist.');
    if (f) {
      api.runtime.lastError = err;
      try { f(); } catch (e) { console.error(e); } finally { api.runtime.lastError = undefined; }
      return undefined;
    }
    return Promise.reject(err);
  }
  function port(name) {
    var p = { name: name || '', postMessage: function () {}, onMessage: ev(), onDisconnect: ev() };
    p.disconnect = function () {};
    setTimeout(function () { p.onDisconnect._fire(p); }, 0);
    return p;
  }
  var api = {
    runtime: {
      id: M.id,
      lastError: undefined,
      getManifest: function () { return clone(M.manifest); },
      getURL: getURL,
      sendMessage: function () { return noReceiver(arguments); },
      connect: function (a, b) {
        var info = (a && typeof a === 'object' ? a : b) || {};
        return port(info.name);
      },
      getPlatformInfo: function () {
        return reply(lastFn(arguments), { os: M.os, arch: 'x86-64', nacl_arch: 'x86-64' });
      },
      getBrowserInfo: function () {
        return reply(lastFn(arguments), { name: 'BitPlayer', vendor: 'BitPlayer', version: '1.0' });
      },
      openOptionsPage: function () { return reply(lastFn(arguments)); },
      setUninstallURL: function () { return reply(lastFn(arguments)); },
      onMessage: ev(), onMessageExternal: ev(), onConnect: ev(), onConnectExternal: ev(),
      onInstalled: ev(), onStartup: ev(), onSuspend: ev(), onUpdateAvailable: ev()
    },
    i18n: {
      getMessage: getMessage,
      getUILanguage: function () { return M.uiLang; },
      getAcceptLanguages: function () { return reply(lastFn(arguments), [M.uiLang]); },
      detectLanguage: function () { return reply(lastFn(arguments), { isReliable: false, languages: [] }); }
    },
    storage: {
      local: area('local', true),
      sync: area('sync', true),
      session: area('session', true),
      managed: area('managed', false),
      onChanged: changed
    },
    extension: {
      getURL: getURL,
      inIncognitoContext: false,
      getBackgroundPage: function () { return null; },
      isAllowedIncognitoAccess: function () { return reply(lastFn(arguments), false); }
    },
    permissions: {
      contains: function () { return reply(lastFn(arguments), true); },
      request: function () { return reply(lastFn(arguments), true); },
      remove: function () { return reply(lastFn(arguments), false); },
      getAll: function () {
        var m = M.manifest || {};
        return reply(lastFn(arguments), {
          permissions: (m.permissions || []).filter(function (p) { return p.indexOf('://') < 0 && p !== '<all_urls>'; }),
          origins: (m.host_permissions || []).concat((m.permissions || []).filter(function (p) { return p.indexOf('://') >= 0 || p === '<all_urls>'; }))
        });
      },
      onAdded: ev(), onRemoved: ev()
    }
  };
  return api;
}
''';
