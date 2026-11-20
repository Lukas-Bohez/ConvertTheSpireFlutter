import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'content_scripts.dart';
import 'extension_package.dart';
import 'web_extension_host.dart';

/// Runs Chrome and Firefox extensions where the web view has no extension
/// engine: Android, Android TV, iOS, macOS and Linux.
///
/// An extension's content scripts and styles - the part that changes web
/// pages, which is what most extensions are for - run on matching pages with
/// the `chrome.*` / `browser.*` APIs content scripts get (see
/// [ContentScriptBundle]). Background pages, toolbar popups and network
/// blocking need an engine's extension runtime; extensions that work only
/// through those cannot be installed here, and the user is told why.
class ContentScriptExtensionHost implements WebExtensionHost {
  ContentScriptExtensionHost({
    Future<Directory> Function()? rootDirectory,
    http.Client? httpClient,
    String? uiLanguage,
    String? os,
  })  : _rootDirectory = rootDirectory ?? _defaultRoot,
        _http = httpClient ?? http.Client(),
        _uiLanguageOverride = uiLanguage,
        _os = os ?? _platformOs();

  static const int maxPackageBytes = 200 * 1024 * 1024;

  final Future<Directory> Function() _rootDirectory;
  final http.Client _http;
  final String? _uiLanguageOverride;
  final String _os;
  final _events = StreamController<ExtensionEvent>.broadcast();

  Future<void> _queue = Future.value();
  Future<void>? _loading;
  final List<_Entry> _entries = [];
  final Map<String, ContentScriptBundle> _bundles = {};
  final Map<String, Map<String, Map<String, Object?>>> _storage = {};
  final Map<String, Timer> _saveTimers = {};

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'web_extensions'));
  }

  static String _platformOs() {
    if (kIsWeb) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS || Platform.isIOS) return 'mac';
    if (Platform.isWindows) return 'win';
    return 'linux';
  }

  String get _uiLanguage {
    final override = _uiLanguageOverride;
    if (override != null) return override;
    try {
      return PlatformDispatcher.instance.locale.toLanguageTag();
    } catch (_) {
      return 'en';
    }
  }

  @override
  bool get isSupported => !kIsWeb;

  @override
  String? get unsupportedReason =>
      isSupported ? null : 'Browser extensions do not run in the web version.';

  /// Both kinds run here: content scripts are the same in either package.
  @override
  bool get runsChromiumPackages => false;

  @override
  Stream<ExtensionEvent> get events => _events.stream;

  // ------------------------------------------------------------------ loading

  /// Reads the installed extensions into memory. The browser calls this at
  /// start; until it finishes, pages simply get no extension scripts.
  Future<void> warmUp() => _loading ??= _exclusive(_load);

  Future<void> _load() async {
    _entries
      ..clear()
      ..addAll(await _readRegistry());
    _bundles.clear();
    for (final entry in _entries) {
      await _loadStorage(entry.id);
      if (!entry.enabled) continue;
      try {
        _bundles[entry.id] = await ContentScriptBundle.load(
            id: entry.id, folder: Directory(entry.folder), uiLanguage: _uiLanguage);
      } catch (e) {
        debugPrint('extension ${entry.name} could not be loaded: $e');
      }
    }
  }

  /// The wrapped scripts of every enabled extension that runs on [url].
  List<String> injectionsFor(String url, {required bool atDocumentStart}) {
    if (_bundles.isEmpty || url.isEmpty) return const [];
    final scheme = Uri.tryParse(url)?.scheme ?? '';
    // Extensions run on web pages, never on the app's own or local pages.
    if (scheme != 'http' && scheme != 'https' && scheme != 'file') {
      return const [];
    }
    final out = <String>[];
    for (final bundle in _bundles.values) {
      out.addAll(bundle.injectionsFor(
        url,
        atDocumentStart: atDocumentStart,
        storage: _storage[bundle.id] ?? const {},
        uiLanguage: _uiLanguage,
        os: _os,
      ));
    }
    return out;
  }

  /// A `chrome.storage` write from a page (see [extensionStorageHandler]).
  void handleStorageMessage(String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final id = decoded['id'];
    final area = decoded['area'];
    if (id is! String || area is! String) return;
    if (!_entries.any((e) => e.id == id)) return;
    if (area != 'local' && area != 'sync' && area != 'session') return;

    final areas = _storage.putIfAbsent(id, () => {});
    final data = areas.putIfAbsent(area, () => <String, Object?>{});
    if (decoded['clear'] == true) data.clear();
    final remove = decoded['remove'];
    if (remove is List) {
      for (final key in remove.whereType<String>()) {
        data.remove(key);
      }
    }
    final set = decoded['set'];
    if (set is Map) {
      set.forEach((key, value) {
        if (key is String) data[key] = value;
      });
    }
    // Session storage lives as long as the app; the rest is written to disk.
    if (area != 'session') _scheduleSave(id);
  }

  @visibleForTesting
  Map<String, Object?> storageOf(String id) => _storage[id] ?? const {};

  // ------------------------------------------------------------------ storage

  Future<File> _storageFile(String id) async => File(
      p.join((await _rootDirectory()).path, 'storage', '$id.json'));

  Future<void> _loadStorage(String id) async {
    final file = await _storageFile(id);
    final areas = <String, Map<String, Object?>>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          for (final name in const ['local', 'sync']) {
            final value = decoded[name];
            if (value is Map) areas[name] = Map<String, Object?>.from(value);
          }
        }
      }
    } catch (e) {
      debugPrint('extension storage for $id unreadable: $e');
    }
    _storage[id] = areas;
  }

  void _scheduleSave(String id) {
    _saveTimers[id]?.cancel();
    _saveTimers[id] =
        Timer(const Duration(milliseconds: 400), () => unawaited(_saveStorage(id)));
  }

  Future<void> _saveStorage(String id) async {
    _saveTimers.remove(id)?.cancel();
    final areas = _storage[id];
    if (areas == null) return;
    final file = await _storageFile(id);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({
      'local': areas['local'] ?? const {},
      'sync': areas['sync'] ?? const {},
    }));
    await temp.rename(file.path);
  }

  /// Writes any storage still waiting for its timer.
  @visibleForTesting
  Future<void> flushStorage() async {
    for (final id in _saveTimers.keys.toList()) {
      await _saveStorage(id);
    }
  }

  // ----------------------------------------------------------------- registry

  Future<File> _registryFile() async =>
      File(p.join((await _rootDirectory()).path, 'registry.json'));

  Future<List<_Entry>> _readRegistry() async {
    final file = await _registryFile();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_Entry.fromJson)
          .whereType<_Entry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeRegistry() async {
    final file = await _registryFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_entries.map((e) => e.toJson()).toList()));
    await temp.rename(file.path);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<List<InstalledExtension>> list() async {
    await warmUp();
    return _entries.map((e) => e.toInstalled()).toList();
  }

  // ------------------------------------------------------------------ install

  @override
  Future<InstalledExtension> install(ExtensionSource source) async {
    await warmUp();
    return _exclusive(() => _install(source));
  }

  Future<InstalledExtension> _install(ExtensionSource source) async {
    final root = await _rootDirectory();
    await root.create(recursive: true);
    final staging = Directory(p.join(root.path, '.staging-${_randomSuffix()}'));
    try {
      final ExtensionManifest manifest;
      switch (source) {
        case FileExtensionSource(:final path):
          if (await FileSystemEntity.isDirectory(path)) {
            manifest = await manifestFromFolder(Directory(path));
            preflight(manifest);
            await _copyFolder(Directory(path), staging);
          } else {
            final bytes = await _readPackageFile(path);
            final archive = decodeExtensionPackage(bytes);
            manifest = manifestFromArchive(archive);
            preflight(manifest);
            await extractExtension(archive, staging);
          }
        case AmoExtensionSource():
          final bytes = await _download(source);
          final archive = decodeExtensionPackage(bytes);
          manifest = manifestFromArchive(archive);
          preflight(manifest);
          await extractExtension(archive, staging);
      }

      final amo = source is AmoExtensionSource ? source : null;
      final id = extensionIdFor(amo?.guid ?? manifest.geckoId ?? manifest.name);

      // Reading every file now means a broken package fails here, with a
      // message, rather than doing nothing on pages later.
      final bundle = await ContentScriptBundle.load(
          id: id, folder: staging, uiLanguage: _uiLanguage);
      if (bundle.entries.isEmpty) {
        throw const ExtensionPackageException(noPageScripts);
      }

      final target = Directory(p.join(root.path, id));
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);

      final previous = _entries.where((e) => e.id == id).firstOrNull;
      final entry = _Entry(
        id: id,
        name: bundle.name,
        version: manifest.version,
        origin: amo == null ? ExtensionOrigin.file : ExtensionOrigin.amo,
        folder: target.path,
        enabled: previous?.enabled ?? true,
        description: manifest.description == null
            ? null
            : resolveMessage(manifest.description!, bundle.messages),
        amoGuid: amo?.guid ?? previous?.amoGuid,
        amoSlug: amo?.slug ?? previous?.amoSlug,
        iconPath: _bestIcon(manifest, target.path),
      );
      _entries
        ..removeWhere((e) => e.id == id)
        ..add(entry);
      await _writeRegistry();
      _storage.putIfAbsent(id, () => {});
      if (entry.enabled) {
        _bundles[id] = await ContentScriptBundle.load(
            id: id, folder: target, uiLanguage: _uiLanguage);
      }
      _events.add(ExtensionEvent(
          id,
          previous == null
              ? ExtensionEventKind.installed
              : ExtensionEventKind.updated));
      return entry.toInstalled();
    } catch (e) {
      await _deleteQuietly(staging);
      if (e is ExtensionPackageException) rethrow;
      throw ExtensionPackageException('The extension could not be installed: $e');
    }
  }

  static const String noPageScripts =
      'This extension works only through a background page, toolbar popup or '
      'network blocking, which need a desktop browser engine. On this device '
      'extensions run the scripts and styles they add to web pages, and this '
      'one has none. Ad blocking is built into the browser.';

  /// Refuses packages that cannot do anything here, before downloading the
  /// rest of the work.
  static void preflight(ExtensionManifest manifest) {
    if (manifest.contentScriptCount == 0) {
      throw const ExtensionPackageException(noPageScripts);
    }
  }

  /// A Chrome-style id (32 letters a-p) that stays the same for the same
  /// extension, so its storage survives updates.
  static String extensionIdFor(String key) {
    final digest = sha256.convert(utf8.encode(key.trim().toLowerCase())).bytes;
    final out = StringBuffer();
    for (final byte in digest.take(16)) {
      out
        ..writeCharCode(0x61 + (byte >> 4))
        ..writeCharCode(0x61 + (byte & 0x0f));
    }
    return out.toString();
  }

  Future<Uint8List> _readPackageFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ExtensionPackageException('That file no longer exists.');
    }
    if (await file.length() > maxPackageBytes) {
      throw const ExtensionPackageException(
          'That file is too large to be a browser extension.');
    }
    return file.readAsBytes();
  }

  Future<Uint8List> _download(AmoExtensionSource source) async {
    final uri = Uri.tryParse(source.fileUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'addons.mozilla.org') {
      throw const ExtensionPackageException(
          'Extensions are only downloaded from addons.mozilla.org.');
    }
    final http.Response response;
    try {
      response = await _http.get(uri).timeout(const Duration(minutes: 3));
    } catch (_) {
      throw const ExtensionPackageException(
          'The download from addons.mozilla.org failed. Check your connection.');
    }
    if (response.statusCode != 200) {
      throw ExtensionPackageException(
          'addons.mozilla.org refused the download (${response.statusCode}).');
    }
    final bytes = response.bodyBytes;
    if (bytes.length > maxPackageBytes) {
      throw const ExtensionPackageException(
          'That extension is too large to install.');
    }
    final expected = source.sha256;
    if (expected != null && sha256.convert(bytes).toString() != expected) {
      throw const ExtensionPackageException(
          'The download did not match the checksum addons.mozilla.org '
          'published for it, so it was not installed.');
    }
    return bytes;
  }

  static String? _bestIcon(ExtensionManifest manifest, String folder) {
    final icons = manifest.raw['icons'];
    if (icons is! Map) return null;
    final sized = icons.entries
        .map((e) => (int.tryParse('${e.key}'), e.value))
        .where((e) => e.$1 != null && e.$2 is String)
        .toList()
      ..sort((a, b) => (a.$1! - 48).abs().compareTo((b.$1! - 48).abs()));
    if (sized.isEmpty) return null;
    final relative = (sized.first.$2 as String).replaceFirst(RegExp(r'^/'), '');
    final path = p.normalize(p.join(folder, relative));
    if (!p.isWithin(folder, path)) return null;
    return File(path).existsSync() ? path : null;
  }

  static Future<void> _copyFolder(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: from.path);
      if (entity is File) {
        final destination = File(p.join(to.path, relative));
        await destination.parent.create(recursive: true);
        await entity.copy(destination.path);
      } else if (entity is Directory) {
        await Directory(p.join(to.path, relative)).create(recursive: true);
      }
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } catch (_) {}
  }

  static String _randomSuffix() =>
      Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  // ---------------------------------------------------------- enable/remove

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    await warmUp();
    await _exclusive(() async {
      final index = _entries.indexWhere((e) => e.id == id);
      if (index < 0) return;
      _entries[index] = _entries[index].copyWith(enabled: enabled);
      await _writeRegistry();
      if (enabled) {
        try {
          _bundles[id] = await ContentScriptBundle.load(
              id: id,
              folder: Directory(_entries[index].folder),
              uiLanguage: _uiLanguage);
        } on ExtensionPackageException {
          rethrow;
        } catch (e) {
          throw ExtensionPackageException('The extension could not be loaded: $e');
        }
      } else {
        _bundles.remove(id);
      }
    });
    _events.add(ExtensionEvent(
        id, enabled ? ExtensionEventKind.enabled : ExtensionEventKind.disabled));
  }

  @override
  Future<void> remove(String id) async {
    await warmUp();
    await _exclusive(() async {
      final entry = _entries.where((e) => e.id == id).firstOrNull;
      if (entry == null) return;
      _entries.remove(entry);
      _bundles.remove(id);
      _storage.remove(id);
      _saveTimers.remove(id)?.cancel();
      await _writeRegistry();
      await _deleteQuietly(Directory(entry.folder));
      await _deleteQuietly(await _storageFile(id));
    });
    _events.add(ExtensionEvent(id, ExtensionEventKind.removed));
  }

  /// Extension pages (popups, options) need the engine's extension runtime.
  @override
  String? pageUrl(InstalledExtension extension, String relativePath) => null;
}

class _Entry {
  const _Entry({
    required this.id,
    required this.name,
    required this.version,
    required this.origin,
    required this.folder,
    required this.enabled,
    this.description,
    this.amoGuid,
    this.amoSlug,
    this.iconPath,
  });

  final String id;
  final String name;
  final String version;
  final ExtensionOrigin origin;
  final String folder;
  final bool enabled;
  final String? description;
  final String? amoGuid;
  final String? amoSlug;
  final String? iconPath;

  static _Entry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final folder = json['folder'];
    if (id is! String || folder is! String) return null;
    return _Entry(
      id: id,
      name: json['name'] as String? ?? id,
      version: json['version'] as String? ?? '',
      origin:
          json['origin'] == 'amo' ? ExtensionOrigin.amo : ExtensionOrigin.file,
      folder: folder,
      enabled: json['enabled'] as bool? ?? true,
      description: json['description'] as String?,
      amoGuid: json['amoGuid'] as String?,
      amoSlug: json['amoSlug'] as String?,
      iconPath: json['iconPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'origin': origin.name,
        'folder': folder,
        'enabled': enabled,
        if (description != null) 'description': description,
        if (amoGuid != null) 'amoGuid': amoGuid,
        if (amoSlug != null) 'amoSlug': amoSlug,
        if (iconPath != null) 'iconPath': iconPath,
      };

  _Entry copyWith({bool? enabled}) => _Entry(
        id: id,
        name: name,
        version: version,
        origin: origin,
        folder: folder,
        enabled: enabled ?? this.enabled,
        description: description,
        amoGuid: amoGuid,
        amoSlug: amoSlug,
        iconPath: iconPath,
      );

  InstalledExtension toInstalled() => InstalledExtension(
        id: id,
        name: name,
        enabled: enabled,
        version: version,
        origin: origin,
        description: description,
        amoGuid: amoGuid,
        amoSlug: amoSlug,
        iconPath: iconPath,
      );
}
