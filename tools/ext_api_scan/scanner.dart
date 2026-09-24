import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/extension_package.dart';
import 'package:path/path.dart' as p;

/// What one extension uses, from its manifest and its JavaScript.
///
/// The compatibility study (issue #10) compares engines by which APIs the
/// extensions people actually use depend on. This is the data for that.
class ExtensionScan {
  ExtensionScan({
    required this.source,
    required this.manifest,
    required this.namespaces,
    required this.jsFiles,
  });

  /// The folder or package name it was read from.
  final String source;
  final ExtensionManifest manifest;

  /// API namespace -> number of references, e.g. `tabs` -> 12. Calls through
  /// `chrome.` and `browser.` are merged: they are the same API.
  final Map<String, int> namespaces;
  final int jsFiles;

  String get backgroundType {
    if (manifest.backgroundServiceWorker != null) return 'service_worker';
    if (manifest.backgroundPage != null) return 'page';
    if (manifest.backgroundScripts.isNotEmpty) return 'scripts';
    return 'none';
  }

  bool get usesDeclarativeNetRequest =>
      manifest.raw['declarative_net_request'] != null ||
      manifest.permissions.any((p) => p.startsWith('declarativeNetRequest'));

  /// The preflight's verdict for a Chromium engine; empty when attempted.
  String get chromiumPreflight => chromiumIncompatibility(manifest) ?? '';
}

/// Matches `chrome.tabs.query`, `browser.storage.local`, `chrome.runtime`...
/// Only the first segment after the root is the namespace.
final RegExp _apiCall = RegExp(r'\b(?:chrome|browser)\.([a-zA-Z]+)\b');

/// Every WebExtension namespace in Chrome's and Firefox's API references
/// (plus Thunderbird's, which cross-browser extensions sometimes carry).
///
/// Only these are counted. Without the list, text like `chrome.google.com`
/// inside a URL, or a minified variable that happens to be named `chrome`,
/// shows up as an "API".
const Set<String> knownNamespaces = {
  'accessibilityFeatures',
  'action',
  'alarms',
  'bookmarks',
  'browserAction',
  'browserSettings',
  'browsingData',
  'captivePortal',
  'certificateProvider',
  'clipboard',
  'commands',
  'contentScripts',
  'contentSettings',
  'contextMenus',
  'contextualIdentities',
  'cookies',
  'debugger',
  'declarativeContent',
  'declarativeNetRequest',
  'desktopCapture',
  'devtools',
  'dns',
  'documentScan',
  'dom',
  'downloads',
  'enterprise',
  'events',
  'extension',
  'extensionTypes',
  'fileBrowserHandler',
  'fileSystemProvider',
  'find',
  'fontSettings',
  'gcm',
  'history',
  'i18n',
  'identity',
  'idle',
  'input',
  'instanceID',
  'loginState',
  'management',
  'menus',
  'messageDisplayScripts',
  'notifications',
  'offscreen',
  'omnibox',
  'pageAction',
  'pageCapture',
  'permissions',
  'pkcs11',
  'platformKeys',
  'power',
  'printerProvider',
  'printing',
  'printingMetrics',
  'privacy',
  'processes',
  'proxy',
  'readingList',
  'runtime',
  'scripting',
  'search',
  'sessions',
  'sidePanel',
  'sidebarAction',
  'storage',
  'system',
  'tabCapture',
  'tabGroups',
  'tabs',
  'theme',
  'topSites',
  'tts',
  'ttsEngine',
  'types',
  'userScripts',
  'vpnProvider',
  'wallpaper',
  'webAuthenticationProxy',
  'webNavigation',
  'webRequest',
  'windows',
};

/// Counts API namespaces referenced in [source].
Map<String, int> countNamespaces(String source) {
  final counts = <String, int>{};
  for (final match in _apiCall.allMatches(source)) {
    final namespace = match.group(1)!;
    if (!knownNamespaces.contains(namespace)) continue;
    counts[namespace] = (counts[namespace] ?? 0) + 1;
  }
  return counts;
}

void _merge(Map<String, int> into, Map<String, int> from) {
  from.forEach((k, v) => into[k] = (into[k] ?? 0) + v);
}

/// Scans an unpacked extension folder.
Future<ExtensionScan> scanFolder(Directory folder) async {
  final manifest = await manifestFromFolder(folder);
  final namespaces = <String, int>{};
  var jsFiles = 0;
  await for (final entity in folder.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.js')) continue;
    jsFiles++;
    _merge(namespaces,
        countNamespaces(await entity.readAsString(encoding: latin1)));
  }
  return ExtensionScan(
    source: p.basename(folder.path),
    manifest: manifest,
    namespaces: namespaces,
    jsFiles: jsFiles,
  );
}

/// Scans a .crx, .zip or .xpi without extracting it to disk.
ExtensionScan scanPackage(String name, Uint8List bytes) {
  final archive = decodeExtensionPackage(bytes);
  final manifest = manifestFromArchive(archive);
  final namespaces = <String, int>{};
  var jsFiles = 0;
  for (final file in archive.files) {
    if (!file.isFile || !file.name.endsWith('.js')) continue;
    jsFiles++;
    _merge(namespaces, countNamespaces(latin1.decode(file.content)));
  }
  return ExtensionScan(
    source: name,
    manifest: manifest,
    namespaces: namespaces,
    jsFiles: jsFiles,
  );
}

/// Scans every extension in [input]: unpacked folders and package files.
/// Anything that is not an extension is reported, not fatal.
Future<(List<ExtensionScan>, List<String>)> scanAll(Directory input) async {
  final scans = <ExtensionScan>[];
  final problems = <String>[];
  final entries = input.listSync()..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in entries) {
    final name = p.basename(entity.path);
    try {
      if (entity is Directory) {
        if (!File(p.join(entity.path, 'manifest.json')).existsSync()) continue;
        scans.add(await scanFolder(entity));
      } else if (entity is File &&
          const {'.crx', '.zip', '.xpi'}.contains(p.extension(name))) {
        scans.add(scanPackage(name, await entity.readAsBytes()));
      }
    } on ExtensionPackageException catch (e) {
      problems.add('$name: ${e.message}');
    } on ArchiveException catch (e) {
      problems.add('$name: $e');
    }
  }
  return (scans, problems);
}

String _csvField(Object? value) {
  final text = '${value ?? ''}';
  if (text.contains(RegExp(r'[",\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// One row per extension; list columns are `;`-separated.
String toCsv(List<ExtensionScan> scans) {
  const header = [
    'source',
    'name',
    'version',
    'manifest_version',
    'background',
    'permissions',
    'host_permissions',
    'content_scripts',
    'action',
    'popup',
    'options',
    'declarative_net_request',
    'gecko_id',
    'gecko_android',
    'commands_key',
    'js_files',
    'api_namespaces',
    'chromium_preflight',
  ];
  final rows = <String>[header.join(',')];
  for (final s in scans) {
    final m = s.manifest;
    final namespaces = s.namespaces.keys.toList()..sort();
    rows.add([
      s.source,
      m.name,
      m.version,
      m.manifestVersion,
      s.backgroundType,
      m.permissions.join(';'),
      m.hostPermissions.join(';'),
      m.contentScriptCount,
      m.hasAction,
      m.popupPath ?? '',
      m.optionsPath ?? '',
      s.usesDeclarativeNetRequest,
      m.geckoId ?? '',
      m.declaresGeckoAndroid,
      m.usesCommandsKey,
      s.jsFiles,
      namespaces.join(';'),
      s.chromiumPreflight,
    ].map(_csvField).join(','));
  }
  return '${rows.join('\n')}\n';
}

/// Extensions down the side, API namespaces across the top.
String toMarkdownMatrix(List<ExtensionScan> scans) {
  final namespaces =
      <String>{for (final s in scans) ...s.namespaces.keys}.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('# Extension API usage')
    ..writeln()
    ..writeln('Generated by `tools/ext_api_scan`. A cell is the number of '
        'references to that namespace in the extension’s JavaScript, '
        'through `chrome.` or `browser.`. Empty means none.')
    ..writeln()
    ..writeln('A static count, so it undercounts extensions that reach the '
        'API through a wrapper (`const api = self.browser || self.chrome`). '
        'An empty cell means "not called directly", not "not used".')
    ..writeln()
    ..writeln('| Extension | MV | Background | ${namespaces.join(' | ')} |')
    ..writeln(
        '|---|---|---|${List.filled(namespaces.length, '---:').join('|')}|');
  for (final s in scans) {
    final cells = namespaces.map((n) => s.namespaces[n]?.toString() ?? '');
    final name = s.manifest.nameIsLocalised ? s.source : s.manifest.name;
    buffer.writeln('| ${name.replaceAll('|', '/')} '
        '| ${s.manifest.manifestVersion} | ${s.backgroundType} '
        '| ${cells.join(' | ')} |');
  }
  return buffer.toString();
}
