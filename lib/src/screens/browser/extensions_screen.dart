import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../browser/extensions/amo_catalog.dart';
import '../../browser/extensions/extension_package.dart';
import '../../browser/extensions/web_extension_host.dart';
import '../../browser/extensions/webview2_extension_host.dart';
import '../../browser/platform/webview2_environment.dart';
import '../../utils/l10n.dart';
import '../../utils/snack.dart';
import 'extension_page_dialog.dart';

/// Install and manage browser extensions (issue #10).
///
/// Two tabs: what is installed, and a catalog backed by addons.mozilla.org -
/// the one store the app integrates. Extensions can also be installed from a
/// .crx, .zip or .xpi file, or an unpacked folder. Every control is a plain
/// focusable widget, so the whole screen works with a keyboard or a remote.
class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key, required this.host, this.catalog});

  final WebExtensionHost host;

  /// Injectable for tests.
  final AmoCatalog? catalog;

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  late final AmoCatalog _catalog = widget.catalog ?? AmoCatalog();
  StreamSubscription<ExtensionEvent>? _events;

  List<InstalledExtension> _installed = const [];
  final Map<String, AmoAddon> _updates = {};
  final Set<String> _busy = {};
  bool _loading = true;
  bool _installing = false;
  String? _problem;

  WebExtensionHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    _events = _host.events.listen((_) => unawaited(_reload()));
    unawaited(_open());
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _open() async {
    if (!_host.isSupported) {
      setState(() {
        _problem = _host.unsupportedReason;
        _loading = false;
      });
      return;
    }
    if (_host is WebView2ExtensionHost &&
        !await WebView2Environment.extensionsEnabled()) {
      if (!mounted) return;
      setState(() {
        _problem = context.l10n.extensionsUnavailableSessionAnotherCopy;
        _loading = false;
      });
      return;
    }
    await _reload(reconcile: true);
    unawaited(_checkUpdates());
  }

  Future<void> _reload({bool reconcile = false}) async {
    try {
      final host = _host;
      final list = reconcile && host is WebView2ExtensionHost
          ? await host.reconcile()
          : await host.list();
      if (!mounted) return;
      setState(() {
        // A copy: the host may hand back an unmodifiable list.
        _installed = [
          ...list
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e);
    }
  }

  /// Looks each addons.mozilla.org extension up once per visit.
  Future<void> _checkUpdates() async {
    for (final extension in _installed) {
      final guid = extension.amoGuid;
      if (guid == null) continue;
      try {
        final latest = await _catalog.details(guid);
        if (latest.version.isNotEmpty && latest.version != extension.version) {
          if (!mounted) return;
          setState(() => _updates[extension.id] = latest);
        }
      } catch (_) {
        // Offline or delisted: no update badge, nothing to report.
      }
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    Snack.show(context, '$error', level: SnackLevel.error);
  }

  bool _isInstalledFromAmo(String guid) =>
      _installed.any((e) => e.amoGuid == guid);

  // ------------------------------------------------------------- installing

  Future<void> _installFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: context.l10n.chooseExtensionPackage,
      type: FileType.custom,
      allowedExtensions: const ['crx', 'zip', 'xpi'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    await _installLocal(path);
  }

  Future<void> _installFromFolder() async {
    final path = await FilePicker.platform
        .getDirectoryPath(dialogTitle: context.l10n.chooseUnpackedExtensionFolder);
    if (path == null) return;
    await _installLocal(path);
  }

  /// Reads the package's manifest first, so the user sees what it may do
  /// before anything is installed.
  Future<void> _installLocal(String path) async {
    final ExtensionManifest manifest;
    try {
      manifest = await _readManifest(path);
      final problem =
          _host.runsChromiumPackages ? chromiumIncompatibility(manifest) : null;
      if (problem != null) throw ExtensionPackageException(problem);
    } catch (e) {
      _showError(e);
      return;
    }
    if (!mounted) return;
    final allowed = await _confirmInstall(
      name: manifest.nameIsLocalised ? context.l10n.extensionLabel : manifest.name,
      permissions: manifest.permissions,
      hostPermissions: manifest.hostPermissions,
    );
    if (allowed != true) return;
    await _runInstall(FileExtensionSource(path));
  }

  static Future<ExtensionManifest> _readManifest(String path) async {
    if (await FileSystemEntity.isDirectory(path)) {
      return manifestFromFolder(Directory(path));
    }
    final file = File(path);
    if (await file.length() > WebView2ExtensionHost.maxPackageBytes) {
      throw const ExtensionPackageException(
          'That file is too large to be a browser extension.');
    }
    final bytes = await file.readAsBytes();
    return manifestFromArchive(
        decodeExtensionPackage(Uint8List.fromList(bytes)));
  }

  Future<void> _installFromCatalog(AmoAddon addon) async {
    final allowed = await _confirmInstall(
      name: addon.name,
      permissions: addon.permissions,
      hostPermissions: addon.hostPermissions,
      note: _host.runsChromiumPackages
          ? context.l10n.firefoxExtensionsRunHereWhen
          : null,
    );
    if (allowed != true) return;
    await _runInstall(AmoExtensionSource(
      guid: addon.guid,
      slug: addon.slug,
      fileUrl: addon.fileUrl,
      version: addon.version,
      sha256: addon.fileSha256,
    ));
  }

  Future<void> _runInstall(ExtensionSource source) async {
    setState(() => _installing = true);
    try {
      final installed = await _host.install(source);
      if (!mounted) return;
      _updates.remove(installed.id);
      Snack.show(context, context.l10n.installed(installed.name),
          level: SnackLevel.info);
      await _reload();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  /// The permission prompt. Never auto-accepted: Cancel holds the focus, so
  /// a stray OK press on a remote cannot install anything.
  Future<bool?> _confirmInstall({
    required String name,
    required List<String> permissions,
    required List<String> hostPermissions,
    String? note,
  }) {
    final lines =
        describePermissions(permissions, hostPermissions, context.l10n);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.add(name)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lines.isEmpty
                    ? context.l10n.asksNoSpecialPermissions
                    : context.l10n.willAble),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2, right: 8),
                          child: Icon(Icons.check_circle_outline, size: 18),
                        ),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  ),
                if (note != null) ...[
                  const SizedBox(height: 12),
                  Text(note,
                      style: Theme.of(dialogContext).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.addExtension),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- managing

  Future<void> _setEnabled(InstalledExtension extension, bool enabled) async {
    setState(() {
      _busy.add(extension.id);
      _installed = [
        for (final e in _installed)
          e.id == extension.id ? e.copyWith(enabled: enabled) : e,
      ];
    });
    try {
      await _host.setEnabled(extension.id, enabled);
    } catch (e) {
      _showError(e);
      await _reload();
    } finally {
      if (mounted) setState(() => _busy.remove(extension.id));
    }
  }

  Future<void> _remove(InstalledExtension extension) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.remove(extension.name)),
        content: Text(
            context.l10n.itsSettingsDeletedTooCan),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.actionRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy.add(extension.id));
    try {
      await _host.remove(extension.id);
      _updates.remove(extension.id);
      await _reload();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy.remove(extension.id));
    }
  }

  Future<void> _update(InstalledExtension extension) async {
    final latest = _updates[extension.id];
    if (latest == null) return;
    await _runInstall(AmoExtensionSource(
      guid: latest.guid,
      slug: latest.slug,
      fileUrl: latest.fileUrl,
      version: latest.version,
      sha256: latest.fileSha256,
    ));
  }

  void _openPage(InstalledExtension extension, String path,
      {required bool options}) {
    final url = _host.pageUrl(extension, path);
    if (url == null) return;
    unawaited(ExtensionPageDialog.show(
      context,
      url: url,
      title: options ? '${extension.name} options' : extension.name,
      isOptionsPage: options,
    ));
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final supported = _host.isSupported && _problem == null;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.extensions),
          actions: [
            if (supported) ...[
              IconButton(
                tooltip: context.l10n.installFromFileCrxZip,
                icon: const Icon(Icons.upload_file),
                onPressed: _installing ? null : _installFromFile,
              ),
              IconButton(
                tooltip: context.l10n.installUnpackedFolder,
                icon: const Icon(Icons.folder_open),
                onPressed: _installing ? null : _installFromFolder,
              ),
            ],
          ],
          bottom: supported
              ? TabBar(tabs: [
                  Tab(text: context.l10n.installed2),
                  Tab(text: context.l10n.getExtensions),
                ])
              : null,
        ),
        body: Column(
          children: [
            if (_installing) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: !supported
                  ? _Message(
                      icon: Icons.extension_off_outlined,
                      text: _problem ?? context.l10n.extensionsNotAvailableHere)
                  : TabBarView(children: [
                      _buildInstalled(),
                      _CatalogTab(
                        catalog: _catalog,
                        forAndroid: !_host.runsChromiumPackages,
                        isInstalled: _isInstalledFromAmo,
                        onInstall: _installing ? null : _installFromCatalog,
                      ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalled() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_installed.isEmpty) {
      return _Message(
        icon: Icons.extension_outlined,
        text: context.l10n.noExtensionsYetFindOne,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _installed.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final extension = _installed[index];
        return _InstalledTile(
          extension: extension,
          busy: _busy.contains(extension.id),
          update: _updates[extension.id],
          onToggle: (value) => _setEnabled(extension, value),
          onOpenPopup: extension.popupPath == null
              ? null
              : () =>
                  _openPage(extension, extension.popupPath!, options: false),
          onOpenOptions: extension.optionsPath == null
              ? null
              : () =>
                  _openPage(extension, extension.optionsPath!, options: true),
          onUpdate: _updates.containsKey(extension.id)
              ? () => _update(extension)
              : null,
          onRemove: () => _remove(extension),
        );
      },
    );
  }
}

/// Turns manifest permissions into sentences a person can judge.
///
/// Only the permissions worth a second thought get a sentence; the rest are
/// listed by name, so nothing the extension asks for is hidden.
List<String> describePermissions(
    List<String> permissions, List<String> hostPermissions,
    [AppLocalizations? l]) {
  l ??= lookupAppLocalizations(const Locale('en'));
  // MV2 add-ons carry host patterns inside `permissions`; AMO passes them
  // through that way. Sort them into the right bucket first.
  hostPermissions = [...hostPermissions, ...permissions.where(isHostPattern)];
  permissions = permissions.where((p) => !isHostPattern(p)).toList();
  final lines = <String>{};
  final allSites = hostPermissions.any((h) =>
      h == '<all_urls>' ||
      h == '*://*/*' ||
      h == 'http://*/*' ||
      h == 'https://*/*');
  if (allSites) {
    lines.add(l.permEveryWebsite);
  } else if (hostPermissions.isNotEmpty) {
    final hosts = hostPermissions
        .map((h) => Uri.tryParse(h.replaceAll('*.', ''))?.host ?? h)
        .where((h) => h.isNotEmpty)
        .toSet()
        .take(4)
        .join(', ');
    final more = hostPermissions.length > 4 ? l.more3 : '';
    lines.add(l.permSomeWebsites(hosts, more));
  }
  for (final permission in permissions) {
    lines.add(_readablePermission(l, permission) ?? l.permUnknown(permission));
  }
  return lines.toList();
}

String? _readablePermission(AppLocalizations l, String permission) {
  return switch (permission) {
    'tabs' => l.permTabs,
    'history' => l.permHistory,
    'bookmarks' => l.permBookmarks,
    'cookies' => l.permCookies,
    'downloads' => l.permDownloads,
    'clipboardRead' => l.permClipboardRead,
    'clipboardWrite' => l.permClipboardWrite,
    'geolocation' => l.permGeolocation,
    'nativeMessaging' => l.permNativeMessaging,
    'webRequest' => l.permWebRequest,
    'webRequestBlocking' => l.permWebRequestBlocking,
    'declarativeNetRequest' => l.permWebRequestBlocking,
    'declarativeNetRequestWithHostAccess' => l.permWebRequestBlocking,
    'scripting' => l.permScripting,
    'privacy' => l.permPrivacy,
    'management' => l.permManagement,
    'proxy' => l.permProxy,
    'notifications' => l.permNotifications,
    'storage' => l.permStorage,
    'unlimitedStorage' => l.permUnlimitedStorage,
    'contextMenus' => l.permContextMenus,
    'menus' => l.permContextMenus,
    'alarms' => l.permAlarms,
    'activeTab' => l.permActiveTab,
    'theme' => l.permTheme,
    'webNavigation' => l.permWebNavigation,
    'topSites' => l.permTopSites,
    'sessions' => l.permSessions,
    'browsingData' => l.permBrowsingData,
    'search' => l.permSearch,
    'identity' => l.permIdentity,
    'fontSettings' => l.permFontSettings,
    'userScripts' => l.permUserScripts,
    'idle' => l.permIdle,
    'sidePanel' => l.permSidePanel,
    'offscreen' => l.permOffscreen,
    'dns' => l.permDns,
    'pageCapture' => l.permPageCapture,
    'tabGroups' => l.permTabGroups,
    'debugger' => l.permDebugger,
    'desktopCapture' => l.permDesktopCapture,
    'tabCapture' => l.permTabCapture,
    _ => null,
  };
}

class _InstalledTile extends StatelessWidget {
  const _InstalledTile({
    required this.extension,
    required this.busy,
    required this.update,
    required this.onToggle,
    required this.onOpenPopup,
    required this.onOpenOptions,
    required this.onUpdate,
    required this.onRemove,
  });

  final InstalledExtension extension;
  final bool busy;
  final AmoAddon? update;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onOpenPopup;
  final VoidCallback? onOpenOptions;
  final VoidCallback? onUpdate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = extension.origin == ExtensionOrigin.amo
        ? 'addons.mozilla.org'
        : context.l10n.installedFromFile;
    // A toolbar button with no popup fires an event only a browser toolbar
    // can send; WebView2 has no toolbar and no way to press it for us.
    final buttonOnly = extension.hasAction && extension.popupPath == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: extension.enabled,
            onChanged: busy ? null : onToggle,
            secondary: _ExtensionIcon(path: extension.iconPath),
            title: Text(extension.name),
            subtitle: Text([
              if (extension.version.isNotEmpty) extension.version,
              origin,
              if (update != null)
                context.l10n.extensionUpdateAvailable(update!.version),
            ].join(' · ')),
          ),
          if (buttonOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
              child: Text(
                context.l10n.itsToolbarButtonRunsBackground,
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Wrap(
              spacing: 4,
              children: [
                if (onOpenPopup != null)
                  TextButton.icon(
                    onPressed: extension.enabled ? onOpenPopup : null,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(context.l10n.actionOpen),
                  ),
                if (onOpenOptions != null)
                  TextButton.icon(
                    onPressed: extension.enabled ? onOpenOptions : null,
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(context.l10n.options),
                  ),
                if (onUpdate != null)
                  TextButton.icon(
                    onPressed: busy ? null : onUpdate,
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: Text(context.l10n.update),
                  ),
                if (extension.amoSlug != null)
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.https('addons.mozilla.org',
                          '/firefox/addon/${extension.amoSlug}/'),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: Text(context.l10n.details),
                  ),
                TextButton.icon(
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(context.l10n.actionRemove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtensionIcon extends StatelessWidget {
  const _ExtensionIcon({this.path, this.url});

  final String? path;
  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    final fallback = Icon(Icons.extension,
        size: size - 8, color: Theme.of(context).colorScheme.primary);
    Widget image;
    if (path != null) {
      image = Image.file(File(path!),
          width: size, height: size, errorBuilder: (_, __, ___) => fallback);
    } else if (url != null) {
      image = Image.network(url!,
          width: size, height: size, errorBuilder: (_, __, ___) => fallback);
    } else {
      image = fallback;
    }
    return SizedBox(width: size, height: size, child: Center(child: image));
  }
}

/// The addons.mozilla.org catalog.
class _CatalogTab extends StatefulWidget {
  const _CatalogTab({
    required this.catalog,
    required this.forAndroid,
    required this.isInstalled,
    required this.onInstall,
  });

  final AmoCatalog catalog;
  final bool forAndroid;
  final bool Function(String guid) isInstalled;
  final Future<void> Function(AmoAddon addon)? onInstall;

  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _query = TextEditingController();
  final List<AmoAddon> _results = [];
  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    final generation = more ? _generation : ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _results.clear();
        _page = 1;
      }
    });
    try {
      final page = await widget.catalog.search(
        _query.text,
        forAndroid: widget.forAndroid,
        page: _page,
      );
      // A newer search started while this one was in flight.
      if (!mounted || generation != _generation) return;
      setState(() {
        _results.addAll(page.results);
        _hasMore = page.hasMore;
        _page++;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: context.l10n.searchAddonsMozillaOrg,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: context.l10n.tabSearch,
                icon: const Icon(Icons.arrow_forward),
                onPressed: _search,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _error != null && _results.isEmpty
              ? _Message(icon: Icons.cloud_off, text: _error!, onRetry: _search)
              : ListView.builder(
                  itemCount: _results.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _results.length) {
                      if (_loading) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (_results.isEmpty) {
                        return _Message(
                            icon: Icons.search_off,
                            text: context.l10n.nothingFoundTryAnotherSearch);
                      }
                      if (!_hasMore) return const SizedBox(height: 24);
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: OutlinedButton(
                            onPressed: () => _search(more: true),
                            child: Text(context.l10n.loadMore),
                          ),
                        ),
                      );
                    }
                    final addon = _results[index];
                    final installed = widget.isInstalled(addon.guid);
                    final users = addon.dailyUsers;
                    return ListTile(
                      leading: _ExtensionIcon(url: addon.iconUrl),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(addon.name,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (addon.recommended) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: context.l10n.recommendedByMozilla,
                              child: Icon(Icons.verified,
                                  size: 16, color: theme.colorScheme.primary),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        [
                          // Some summaries are several paragraphs; keep the
                          // user count visible under one line of text.
                          if (addon.summary != null)
                            addon.summary!.replaceAll(RegExp(r'\s+'), ' '),
                          if (users != null) '${_compact(users)} users',
                        ].join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: addon.summary != null,
                      trailing: installed
                          ? Chip(label: Text(context.l10n.installed2))
                          : FilledButton.tonal(
                              onPressed: widget.onInstall == null
                                  ? null
                                  : () => widget.onInstall!(addon),
                              child: Text(context.l10n.actionAdd),
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        // A comfortable reading width; on a desktop the help text otherwise
        // ran across the whole window in one line.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                    onPressed: onRetry, child: Text(context.l10n.tryAgain)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
