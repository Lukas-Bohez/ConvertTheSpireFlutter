import 'dart:async';

import 'extension_package.dart';

/// Where an installed extension came from.
enum ExtensionOrigin { file, amo }

/// An extension as the app knows it: the engine's view (id, enabled) joined
/// with what the app recorded when it installed it (version, pages, source).
class InstalledExtension {
  const InstalledExtension({
    required this.id,
    required this.name,
    required this.enabled,
    required this.version,
    required this.origin,
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
  final bool enabled;
  final String version;
  final ExtensionOrigin origin;
  final String? description;

  /// Page shown by the toolbar button, relative to the extension root.
  final String? popupPath;
  final bool hasAction;
  final String? optionsPath;

  /// Set for extensions installed from addons.mozilla.org, for updates.
  final String? amoGuid;
  final String? amoSlug;

  /// Absolute path to the best icon in the extension folder, if any.
  final String? iconPath;

  InstalledExtension copyWith({bool? enabled}) => InstalledExtension(
        id: id,
        name: name,
        enabled: enabled ?? this.enabled,
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

/// What to install.
sealed class ExtensionSource {
  const ExtensionSource();
}

/// A .crx, .zip or .xpi file, or an unpacked folder, the user picked.
class FileExtensionSource extends ExtensionSource {
  const FileExtensionSource(this.path);
  final String path;
}

/// A version file from addons.mozilla.org.
class AmoExtensionSource extends ExtensionSource {
  const AmoExtensionSource({
    required this.guid,
    required this.slug,
    required this.fileUrl,
    required this.version,
    this.sha256,
  });

  final String guid;
  final String slug;
  final String fileUrl;
  final String version;

  /// From AMO's `file.hash`. The download is refused if it does not match.
  final String? sha256;
}

/// Something that changed, for the UI to refresh on.
class ExtensionEvent {
  const ExtensionEvent(this.id, this.kind);
  final String id;
  final ExtensionEventKind kind;
}

enum ExtensionEventKind { installed, removed, enabled, disabled, updated }

/// Runs extensions on whatever engine this platform has.
///
/// The Extensions screen and the browser toolbar talk only to this, so the
/// engine behind it - WebView2 on Windows today, GeckoView on Android later -
/// can change without touching them (issue #10).
abstract class WebExtensionHost {
  /// False when this platform has no engine that can host extensions.
  bool get isSupported;

  /// Shown to the user when [isSupported] is false.
  String? get unsupportedReason;

  /// Whether this engine runs Chromium packages (true) or Firefox ones.
  /// Decides which catalog results can be installed.
  bool get runsChromiumPackages;

  Stream<ExtensionEvent> get events;

  /// Only the extensions the user installed through the app. Engine
  /// built-ins (WebView2 ships a PDF viewer as an extension) are never
  /// listed, so they cannot be switched off or removed by accident.
  Future<List<InstalledExtension>> list();

  /// Installs [source] and returns it. Throws [ExtensionPackageException]
  /// with a user-facing message on any failure.
  Future<InstalledExtension> install(ExtensionSource source);

  Future<void> setEnabled(String id, bool enabled);

  Future<void> remove(String id);

  /// Full URL of an extension page, for the popup and options hosts.
  String? pageUrl(InstalledExtension extension, String relativePath);
}

/// The host for platforms without an extension engine.
class UnsupportedExtensionHost implements WebExtensionHost {
  const UnsupportedExtensionHost(this.unsupportedReason);

  @override
  final String unsupportedReason;

  @override
  bool get isSupported => false;

  @override
  bool get runsChromiumPackages => false;

  @override
  Stream<ExtensionEvent> get events => const Stream.empty();

  @override
  Future<List<InstalledExtension>> list() async => const [];

  @override
  Future<InstalledExtension> install(ExtensionSource source) =>
      Future.error(ExtensionPackageException(unsupportedReason));

  @override
  Future<void> setEnabled(String id, bool enabled) async {}

  @override
  Future<void> remove(String id) async {}

  @override
  String? pageUrl(InstalledExtension extension, String relativePath) => null;
}
