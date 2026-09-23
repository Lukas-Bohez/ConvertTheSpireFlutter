import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Why an extension package could not be used. [message] is shown to the user
/// as-is, so it says what went wrong in their terms, not ours.
class ExtensionPackageException implements Exception {
  const ExtensionPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The parts of an extension's `manifest.json` the app needs to reason about.
///
/// This is deliberately a reading of the manifest, not a validation of it:
/// the engine is the judge of whether an extension loads. What we read here
/// decides the Chromium preflight, the toolbar button and the popup.
class ExtensionManifest {
  const ExtensionManifest({
    required this.name,
    required this.version,
    required this.manifestVersion,
    this.description,
    this.backgroundServiceWorker,
    this.backgroundScripts = const [],
    this.backgroundPage,
    this.permissions = const [],
    this.hostPermissions = const [],
    this.popupPath,
    this.hasAction = false,
    this.optionsPath,
    this.geckoId,
    this.declaresGeckoAndroid = false,
    this.contentScriptCount = 0,
    this.usesCommandsKey = false,
    this.defaultLocale,
    this.raw = const {},
  });

  final String name;
  final String version;
  final int manifestVersion;
  final String? description;

  /// MV3 Chromium background: `background.service_worker`.
  final String? backgroundServiceWorker;

  /// Firefox (and MV2) background: `background.scripts`.
  final List<String> backgroundScripts;

  /// MV2 background page: `background.page`.
  final String? backgroundPage;

  final List<String> permissions;
  final List<String> hostPermissions;

  /// The page shown when the toolbar button is pressed, if it has one.
  final String? popupPath;

  /// Whether the extension declares a toolbar button at all (`action` in MV3,
  /// `browser_action` in MV2). A button without a popup fires onClicked.
  final bool hasAction;

  /// `options_ui.page` or `options_page`.
  final String? optionsPath;

  /// `browser_specific_settings.gecko.id` (or the older `applications`).
  final String? geckoId;

  /// `browser_specific_settings.gecko_android` - what makes AMO list it for
  /// Android.
  final bool declaresGeckoAndroid;

  final int contentScriptCount;

  /// The `commands` key does nothing on Android (no keyboard shortcuts).
  final bool usesCommandsKey;

  final String? defaultLocale;

  /// The decoded manifest, for the compatibility scanner.
  final Map<String, dynamic> raw;

  static ExtensionManifest parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const ExtensionPackageException(
          'The extension’s manifest.json is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ExtensionPackageException(
          'The extension’s manifest.json is not a JSON object.');
    }
    return fromMap(decoded);
  }

  static ExtensionManifest fromMap(Map<String, dynamic> m) {
    List<String> strings(Object? value) =>
        value is List ? value.whereType<String>().toList() : const [];
    Map<String, dynamic>? map(Object? value) =>
        value is Map<String, dynamic> ? value : null;

    final manifestVersion = (m['manifest_version'] as num?)?.toInt() ?? 0;
    if (manifestVersion != 2 && manifestVersion != 3) {
      throw ExtensionPackageException(
          'Unsupported manifest_version ($manifestVersion). '
          'Only Manifest V2 and V3 extensions exist.');
    }

    final background = map(m['background']);
    final action = map(m['action']) ?? map(m['browser_action']);
    final optionsUi = map(m['options_ui']);
    final browserSpecific =
        map(m['browser_specific_settings']) ?? map(m['applications']);
    final gecko = map(browserSpecific?['gecko']);

    // MV2 lists host patterns inside `permissions`; MV3 moved them out.
    final allPermissions = strings(m['permissions']);
    final hostPermissions = [
      ...strings(m['host_permissions']),
      if (manifestVersion == 2) ...allPermissions.where(isHostPattern),
    ];
    final apiPermissions = manifestVersion == 2
        ? allPermissions.where((p) => !isHostPattern(p)).toList()
        : allPermissions;

    final name = m['name'];
    return ExtensionManifest(
      name:
          name is String && name.trim().isNotEmpty ? name.trim() : 'Extension',
      version: m['version'] is String ? m['version'] as String : '',
      manifestVersion: manifestVersion,
      description:
          m['description'] is String ? m['description'] as String : null,
      backgroundServiceWorker: background?['service_worker'] as String?,
      backgroundScripts: strings(background?['scripts']),
      backgroundPage: background?['page'] as String?,
      permissions: apiPermissions,
      hostPermissions: hostPermissions,
      popupPath: action?['default_popup'] as String?,
      hasAction: action != null,
      optionsPath:
          optionsUi?['page'] as String? ?? m['options_page'] as String?,
      geckoId: gecko?['id'] as String?,
      declaresGeckoAndroid: browserSpecific?['gecko_android'] != null,
      contentScriptCount: m['content_scripts'] is List
          ? (m['content_scripts'] as List).length
          : 0,
      usesCommandsKey:
          m['commands'] is Map && (m['commands'] as Map).isNotEmpty,
      defaultLocale: m['default_locale'] as String?,
      raw: m,
    );
  }

  /// Whether [name] is a `__MSG_key__` placeholder resolved from `_locales`.
  bool get nameIsLocalised => name.startsWith('__MSG_') && name.endsWith('__');
}

/// Whether a permission string is a host pattern (`<all_urls>`,
/// `https://example.com/*`) rather than an API permission (`tabs`).
///
/// Manifest V2 mixes both into `permissions`, and addons.mozilla.org passes
/// them through that way for MV2 add-ons, so every reader has to split them.
bool isHostPattern(String permission) =>
    RegExp(r'^(<all_urls>$|(\*|https?|wss?|file|ftp)://)').hasMatch(permission);

/// Why a Chromium engine (WebView2) cannot run this extension, or null when it
/// is worth attempting.
///
/// Only the one certain failure is rejected up front: a Manifest V3 extension
/// whose background is `scripts` with no `service_worker` is a Firefox-only
/// build, and Chromium refuses it. Everything else is attempted and the
/// engine's own verdict is what the user sees (issue #10).
String? chromiumIncompatibility(ExtensionManifest manifest) {
  if (manifest.manifestVersion == 3 &&
      manifest.backgroundScripts.isNotEmpty &&
      manifest.backgroundServiceWorker == null) {
    return 'This extension is Firefox-only. Its background runs as scripts, '
        'which Chromium engines do not support in Manifest V3.';
  }
  return null;
}

/// The kinds of package the installer understands.
enum ExtensionPackageKind { crx3, zip, folder }

const _crxMagic = [0x43, 0x72, 0x32, 0x34]; // "Cr24"
const _zipMagic = [0x50, 0x4B, 0x03, 0x04]; // "PK\x03\x04"

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

/// Identifies a package from its first bytes.
ExtensionPackageKind packageKindOf(Uint8List bytes) {
  if (_startsWith(bytes, _crxMagic)) return ExtensionPackageKind.crx3;
  if (_startsWith(bytes, _zipMagic)) return ExtensionPackageKind.zip;
  throw const ExtensionPackageException(
      'This file is not an extension. Use a .crx, .zip or .xpi file, '
      'or a folder containing manifest.json.');
}

/// Strips the CRX3 header and returns the zip payload inside.
///
/// Layout: magic `Cr24`, uint32 LE version (must be 3), uint32 LE header
/// length, that many header bytes (a protobuf with signatures), then a
/// normal zip. Signatures are not checked here: WebView2 installs unpacked
/// folders, so the engine never sees them either.
Uint8List unwrapCrx3(Uint8List bytes) {
  if (!_startsWith(bytes, _crxMagic)) {
    throw const ExtensionPackageException('Not a CRX file.');
  }
  if (bytes.length < 12) {
    throw const ExtensionPackageException(
        'This .crx file is cut short; download it again.');
  }
  final header = ByteData.sublistView(bytes, 4, 12);
  final version = header.getUint32(0, Endian.little);
  if (version == 2) {
    throw const ExtensionPackageException(
        'This is an old CRX2 package. Chromium stopped accepting CRX2 in 2019; '
        'get a current version of the extension.');
  }
  if (version != 3) {
    throw ExtensionPackageException('Unknown CRX version ($version).');
  }
  final headerLength = header.getUint32(4, Endian.little);
  final payloadStart = 12 + headerLength;
  if (payloadStart >= bytes.length) {
    throw const ExtensionPackageException(
        'This .crx file is cut short; download it again.');
  }
  final payload = Uint8List.sublistView(bytes, payloadStart);
  if (!_startsWith(payload, _zipMagic)) {
    throw const ExtensionPackageException(
        'This .crx file is damaged: no zip data after the header.');
  }
  return payload;
}

/// Decodes a .crx, .zip or .xpi into an archive.
Archive decodeExtensionPackage(Uint8List bytes) {
  final kind = packageKindOf(bytes);
  final zipBytes =
      kind == ExtensionPackageKind.crx3 ? unwrapCrx3(bytes) : bytes;
  try {
    return ZipDecoder().decodeBytes(zipBytes);
  } catch (_) {
    throw const ExtensionPackageException(
        'The extension package is damaged and could not be opened.');
  }
}

/// Finds where `manifest.json` sits inside [archive].
///
/// Most packages have it at the root. Release zips from GitHub sometimes wrap
/// everything in one top-level folder; that folder is accepted too. Anything
/// deeper is ambiguous and rejected.
String manifestRootIn(Archive archive) {
  final manifests = archive.files
      .where((f) => f.isFile)
      .map((f) => f.name.replaceAll('\\', '/'))
      .where(
          (name) => name == 'manifest.json' || name.endsWith('/manifest.json'))
      .toList();
  if (manifests.contains('manifest.json')) return '';
  final oneDeep =
      manifests.where((n) => '/'.allMatches(n).length == 1).toList();
  if (oneDeep.length == 1) {
    return oneDeep.single
        .substring(0, oneDeep.single.length - 'manifest.json'.length);
  }
  throw const ExtensionPackageException(
      'No manifest.json found. This does not look like a browser extension.');
}

/// Reads the manifest out of [archive] without extracting anything.
ExtensionManifest manifestFromArchive(Archive archive) {
  final root = manifestRootIn(archive);
  final file = archive.files.firstWhere((f) =>
      f.isFile && f.name.replaceAll('\\', '/') == '${root}manifest.json');
  return ExtensionManifest.parse(
      utf8.decode(file.content, allowMalformed: true));
}

/// Extracts the extension in [archive] into [target], which must not exist
/// yet. Returns nothing; [target] then holds `manifest.json` at its root.
///
/// Every entry is checked to stay inside [target]: a crafted archive with
/// `../` in its paths must not be able to write anywhere else on disk.
Future<void> extractExtension(Archive archive, Directory target) async {
  final root = manifestRootIn(archive);
  final targetPath = p.normalize(p.absolute(target.path));
  await target.create(recursive: true);

  for (final entry in archive.files) {
    final name = entry.name.replaceAll('\\', '/');
    if (!name.startsWith(root)) continue;
    final relative = name.substring(root.length);
    if (relative.isEmpty) continue;
    // Firefox signature files mean nothing to Chromium; leave them behind.
    if (relative.startsWith('META-INF/')) continue;
    if (entry.isSymbolicLink) continue;

    final destination = p.normalize(p.join(targetPath, relative));
    if (!p.isWithin(targetPath, destination)) {
      throw ExtensionPackageException(
          'The package tries to write outside its folder ($name). '
          'It was not installed.');
    }
    if (entry.isFile) {
      final file = File(destination);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content, flush: false);
    } else {
      await Directory(destination).create(recursive: true);
    }
  }
}

/// Reads the manifest of an unpacked extension folder.
Future<ExtensionManifest> manifestFromFolder(Directory folder) async {
  final file = File(p.join(folder.path, 'manifest.json'));
  if (!await file.exists()) {
    throw const ExtensionPackageException(
        'That folder has no manifest.json, so it is not an unpacked extension.');
  }
  return ExtensionManifest.parse(await file.readAsString());
}
