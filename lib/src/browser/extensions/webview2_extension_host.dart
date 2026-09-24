import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

import '../platform/webview2_environment.dart';
import 'extension_package.dart';
import 'web_extension_host.dart';

/// Runs Chromium extensions in the Windows browser through WebView2's own
/// extension host (issue #10).
///
/// WebView2 installs *unpacked* folders and keeps them registered across
/// restarts, so every package is extracted under the app's support directory
/// and the folder is kept. An unpacked extension's id is derived from its
/// folder path, so each extension gets a stable folder name: reinstalling or
/// updating it keeps the same id.
class WebView2ExtensionHost implements WebExtensionHost {
  WebView2ExtensionHost({
    Future<Directory> Function()? rootDirectory,
    http.Client? httpClient,
  })  : _rootDirectory = rootDirectory ?? _defaultRoot,
        _http = httpClient ?? http.Client();

  /// Largest package accepted. Lofi Player, the biggest fixture, is 44 MB.
  static const int maxPackageBytes = 200 * 1024 * 1024;

  /// A management webview is only kept this long after its last use.
  static const Duration _idleDispose = Duration(seconds: 30);

  final Future<Directory> Function() _rootDirectory;
  final http.Client _http;
  final _events = StreamController<ExtensionEvent>.broadcast();

  WebviewController? _controller;
  Future<WebviewController>? _controllerReady;
  Timer? _idleTimer;
  Future<void> _queue = Future.value();
  int _busy = 0;

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'extensions'));
  }

  @override
  bool get isSupported => !kIsWeb && Platform.isWindows;

  @override
  String? get unsupportedReason => isSupported
      ? null
      : 'Browser extensions currently work in the Windows app only.';

  @override
  bool get runsChromiumPackages => true;

  @override
  Stream<ExtensionEvent> get events => _events.stream;

  // ------------------------------------------------------------------ registry

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
    } catch (e) {
      debugPrint('[EXTENSIONS] registry unreadable, starting empty: $e');
      return [];
    }
  }

  Future<void> _writeRegistry(List<_Entry> entries) async {
    final file = await _registryFile();
    await file.parent.create(recursive: true);
    // Write-then-rename, so a crash mid-write cannot leave half a registry.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(entries.map((e) => e.toJson()).toList()),
        flush: true);
    await temp.rename(file.path);
  }

  /// Serialises every mutation: two installs racing on the registry would
  /// otherwise lose one of them.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    _busy++;
    final result = _queue.then((_) => action()).whenComplete(() => _busy--);
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  // --------------------------------------------------------------- the engine

  /// A webview dedicated to managing the profile. The profile, and so the
  /// installed extensions, are shared with the browser's webviews.
  Future<WebviewController> _engine() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDispose, _disposeEngine);
    return _controllerReady ??= () async {
      await WebView2Environment.ensure();
      if (!await WebView2Environment.extensionsEnabled()) {
        throw const ExtensionPackageException(
            'Extensions are unavailable in this session: another copy of the '
            'app had the browser open first. Close every copy and start the '
            'app again.');
      }
      final controller = WebviewController();
      await controller.initialize();
      // Nobody sees this webview. An extension that opens a tab on install
      // (a welcome page, say) would otherwise pop up a bare window outside
      // the app.
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _controller = controller;
      return controller;
    }();
  }

  void _disposeEngine() {
    if (_busy > 0) {
      // A long download is still running; look again later.
      _idleTimer = Timer(_idleDispose, _disposeEngine);
      return;
    }
    final controller = _controller;
    _controller = null;
    _controllerReady = null;
    if (controller != null) unawaited(controller.dispose());
  }

  ExtensionPackageException _engineError(Object error) {
    if (error is ExtensionPackageException) return error;
    if (error is PlatformException) {
      final hr = error.details is int ? error.details as int : null;
      // E_NOINTERFACE: the runtime predates the extension APIs.
      if (hr == 0x80004002 || hr == -2147467262) {
        return const ExtensionPackageException(
            'Your WebView2 runtime is too old for extensions. Update '
            'Microsoft Edge WebView2 Runtime and restart the app.');
      }
      return ExtensionPackageException(
          'WebView2 could not load this extension (${error.message}).');
    }
    return ExtensionPackageException('Something went wrong: $error');
  }

  // -------------------------------------------------------------------- list

  @override
  Future<List<InstalledExtension>> list() async {
    final entries = await _readRegistry();
    return entries.map((e) => e.toInstalled()).toList();
  }

  /// Brings the registry in line with what the engine actually has: drops
  /// entries the engine no longer knows (a wiped profile) and takes the
  /// engine's enabled state. Call when the manager opens.
  Future<List<InstalledExtension>> reconcile() => _exclusive(() async {
        final entries = await _readRegistry();
        if (entries.isEmpty) return const <InstalledExtension>[];
        final List<BrowserExtension> engineList;
        try {
          engineList = await (await _engine()).getBrowserExtensions();
        } catch (e) {
          throw _engineError(e);
        }
        final byId = {for (final e in engineList) e.id: e};
        final kept = <_Entry>[];
        for (final entry in entries) {
          final live = byId[entry.id];
          if (live == null) continue;
          kept.add(entry.copyWith(enabled: live.enabled));
        }
        if (kept.length != entries.length ||
            !listEquals(kept.map((e) => e.enabled).toList(),
                entries.map((e) => e.enabled).toList())) {
          await _writeRegistry(kept);
        }
        return kept.map((e) => e.toInstalled()).toList();
      });

  // ----------------------------------------------------------------- install

  @override
  Future<InstalledExtension> install(ExtensionSource source) =>
      _exclusive(() => _install(source));

  Future<InstalledExtension> _install(ExtensionSource source) async {
    final root = await _rootDirectory();
    await root.create(recursive: true);
    final staging = Directory(p.join(root.path, '.staging-${_randomSuffix()}'));

    try {
      // 1. Unpack into a staging folder.
      final ExtensionManifest manifest;
      switch (source) {
        case FileExtensionSource(:final path):
          if (await FileSystemEntity.isDirectory(path)) {
            manifest = await manifestFromFolder(Directory(path));
            _preflight(manifest);
            await _copyFolder(Directory(path), staging);
          } else {
            final bytes = await _readPackageFile(path);
            final archive = decodeExtensionPackage(bytes);
            manifest = manifestFromArchive(archive);
            _preflight(manifest);
            await extractExtension(archive, staging);
          }
        case AmoExtensionSource():
          final bytes = await _download(source);
          final archive = decodeExtensionPackage(bytes);
          manifest = manifestFromArchive(archive);
          _preflight(manifest);
          await extractExtension(archive, staging);
      }

      // 2. Move it to its stable folder, replacing an older copy.
      final amo = source is AmoExtensionSource ? source : null;
      final key = _folderKey(amoGuid: amo?.guid, manifest: manifest);
      final target = Directory(p.join(root.path, key));
      final entries = await _readRegistry();
      final previous =
          entries.where((e) => p.equals(e.folder, target.path)).firstOrNull;

      final engine = await _engine();
      if (previous != null) {
        // Same folder means same id: take the old copy out of the engine
        // before its files change underneath it.
        try {
          await engine.removeBrowserExtension(previous.id);
        } catch (_) {
          // Already gone from the engine; the files still need replacing.
        }
      }
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);

      // 3. Hand it to WebView2.
      final BrowserExtension added;
      try {
        added = await engine.addBrowserExtension(target.path);
      } catch (e) {
        await _deleteQuietly(target);
        if (previous != null) {
          entries.remove(previous);
          await _writeRegistry(entries);
        }
        throw _engineError(e);
      }

      final entry = _Entry(
        id: added.id,
        name: added.name.isNotEmpty ? added.name : manifest.name,
        version: manifest.version,
        origin: amo == null ? ExtensionOrigin.file : ExtensionOrigin.amo,
        folder: target.path,
        enabled: added.enabled,
        description: manifest.description,
        popupPath: manifest.popupPath,
        hasAction: manifest.hasAction,
        optionsPath: manifest.optionsPath,
        amoGuid: amo?.guid,
        amoSlug: amo?.slug,
        iconPath: _bestIcon(manifest, target.path),
      );
      entries
        ..removeWhere((e) => e.id == entry.id || identical(e, previous))
        ..add(entry);
      await _writeRegistry(entries);
      _events.add(ExtensionEvent(
          entry.id,
          previous == null
              ? ExtensionEventKind.installed
              : ExtensionEventKind.updated));
      return entry.toInstalled();
    } catch (e) {
      await _deleteQuietly(staging);
      if (e is ExtensionPackageException) rethrow;
      throw _engineError(e);
    }
  }

  void _preflight(ExtensionManifest manifest) {
    final problem = chromiumIncompatibility(manifest);
    if (problem != null) throw ExtensionPackageException(problem);
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
    // Only AMO: the catalog is the one store the app integrates.
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

  /// A folder name that stays the same for the same extension, so its
  /// WebView2 id - which is derived from the path - stays the same too.
  static String _folderKey(
      {String? amoGuid, required ExtensionManifest manifest}) {
    final base = amoGuid ?? manifest.geckoId ?? manifest.name;
    final cleaned = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    final safe = cleaned.isEmpty ? 'extension' : cleaned;
    return safe.length > 60 ? safe.substring(0, 60) : safe;
  }

  /// The icon closest to 48px, which reads well at list and menu sizes.
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

  static Future<void> _deleteQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // A locked file in a leftover folder is not worth failing over.
    }
  }

  static String _randomSuffix() =>
      Random().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  // ---------------------------------------------------------- enable/remove

  @override
  Future<void> setEnabled(String id, bool enabled) => _exclusive(() async {
        try {
          await (await _engine()).setBrowserExtensionEnabled(id, enabled);
        } catch (e) {
          throw _engineError(e);
        }
        final entries = await _readRegistry();
        final index = entries.indexWhere((e) => e.id == id);
        if (index >= 0) {
          entries[index] = entries[index].copyWith(enabled: enabled);
          await _writeRegistry(entries);
        }
        _events.add(ExtensionEvent(
            id,
            enabled
                ? ExtensionEventKind.enabled
                : ExtensionEventKind.disabled));
      });

  @override
  Future<void> remove(String id) => _exclusive(() async {
        try {
          await (await _engine()).removeBrowserExtension(id);
        } on PlatformException catch (e) {
          // E_INVALIDARG: the engine no longer has it. Still clean up ours.
          final hr = e.details is int ? e.details as int : null;
          if (hr != 0x80070057 && hr != -2147024809) throw _engineError(e);
        } catch (e) {
          throw _engineError(e);
        }
        final entries = await _readRegistry();
        final entry = entries.where((e) => e.id == id).firstOrNull;
        if (entry != null) {
          entries.remove(entry);
          await _writeRegistry(entries);
          await _deleteQuietly(Directory(entry.folder));
        }
        _events.add(ExtensionEvent(id, ExtensionEventKind.removed));
      });

  @override
  String? pageUrl(InstalledExtension extension, String relativePath) {
    final path = relativePath.replaceFirst(RegExp(r'^/+'), '');
    if (path.isEmpty) return null;
    return 'chrome-extension://${extension.id}/$path';
  }

  /// Frees the management webview straight away.
  void close() {
    _idleTimer?.cancel();
    _disposeEngine();
  }
}

/// A registry record: what the app installed and where.
class _Entry {
  const _Entry({
    required this.id,
    required this.name,
    required this.version,
    required this.origin,
    required this.folder,
    required this.enabled,
    this.description,
    this.popupPath,
    this.hasAction = false,
    this.optionsPath,
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
  final String? popupPath;
  final bool hasAction;
  final String? optionsPath;
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
      popupPath: json['popupPath'] as String?,
      hasAction: json['hasAction'] as bool? ?? false,
      optionsPath: json['optionsPath'] as String?,
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
        if (popupPath != null) 'popupPath': popupPath,
        'hasAction': hasAction,
        if (optionsPath != null) 'optionsPath': optionsPath,
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
        popupPath: popupPath,
        hasAction: hasAction,
        optionsPath: optionsPath,
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
        popupPath: popupPath,
        hasAction: hasAction,
        optionsPath: optionsPath,
        amoGuid: amoGuid,
        amoSlug: amoSlug,
        iconPath: iconPath,
      );
}
