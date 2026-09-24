import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../browser/adblock/adblock_service.dart';
import '../../browser/extensions/extension_hosts.dart';
import '../../data/browser_db.dart';
import '../../services/ipfs_service.dart';
import '../../utils/l10n.dart';
import '../../utils/snack.dart';
import 'extensions_screen.dart';

/// Browser settings screen: search engine, ad-block, privacy, display.
class BrowserSettingsScreen extends StatefulWidget {
  final AdBlockService adBlockService;
  final BrowserRepository repo;

  const BrowserSettingsScreen({
    super.key,
    required this.adBlockService,
    required this.repo,
  });

  @override
  State<BrowserSettingsScreen> createState() => _BrowserSettingsScreenState();
}

class _BrowserSettingsScreenState extends State<BrowserSettingsScreen> {
  String _searchEngine = 'DuckDuckGo';
  bool _desktopMode = false;
  bool _blockPopups = true;
  bool _doNotTrack = true;
  String _ipfsGateway = '';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchEngine = prefs.getString('browser_search_engine') ?? 'DuckDuckGo';
      _desktopMode = prefs.getBool('browser_desktop_mode') ?? false;
      _blockPopups = prefs.getBool('browser_block_popups') ?? true;
      _doNotTrack = prefs.getBool('browser_dnt') ?? true;
      _ipfsGateway = prefs.getString('browser_ipfs_gateway') ?? '';
    });
  }

  Future<void> _savePref(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.browserSettings)),
        body: ListView(
          children: [
            // -- General --
            _SectionHeader(title: context.l10n.general),
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(context.l10n.searchEngine),
              subtitle: Text(_searchEngine),
              onTap: _pickSearchEngine,
            ),
            if (ExtensionHosts.available)
              ListTile(
                leading: const Icon(Icons.extension_outlined),
                title: Text(context.l10n.extensions),
                subtitle: Text(
                    context.l10n.chromeExtensionsAddonsMozillaOrg),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ExtensionsScreen(host: ExtensionHosts.current),
                  ),
                ),
              ),

            // -- Privacy --
            _SectionHeader(title: context.l10n.privacy),
            SwitchListTile(
              secondary: const Icon(Icons.block),
              title: Text(context.l10n.adBlocker),
              subtitle: Text(widget.adBlockService.adBlockEnabled
                  ? context.l10n.enabled
                  : context.l10n.disabled),
              value: widget.adBlockService.adBlockEnabled,
              onChanged: (v) {
                widget.adBlockService.setEnabled(v);
                setState(() {});
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.web_asset_off),
              title: Text(context.l10n.blockPopUps),
              value: _blockPopups,
              onChanged: (v) {
                setState(() => _blockPopups = v);
                _savePref('browser_block_popups', v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.do_not_disturb_on),
              title: Text(context.l10n.doNotTrack),
              value: _doNotTrack,
              onChanged: (v) {
                setState(() => _doNotTrack = v);
                _savePref('browser_dnt', v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: Text(context.l10n.updateBlocklist),
              subtitle: Text(context.l10n.reDownloadEasylistRules),
              onTap: () async {
                await widget.adBlockService.updateBlocklist();
                if (mounted) {
                  Snack.show(context, context.l10n.blocklistUpdated,
                      level: SnackLevel.info);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: cs.error),
              title: Text(context.l10n.clearBrowsingData),
              onTap: _showClearDataDialog,
            ),

            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(context.l10n.ipfsGateway),
              subtitle: Text(
                _ipfsGateway.isEmpty ? context.l10n.defaultGatewayChain : _ipfsGateway,
              ),
              onTap: _editIpfsGateway,
            ),

            // -- Display --
            _SectionHeader(title: context.l10n.display),
            SwitchListTile(
              secondary: const Icon(Icons.desktop_windows),
              title: Text(context.l10n.desktopMode),
              subtitle: Text(context.l10n.requestDesktopVersionWebsites),
              value: _desktopMode,
              onChanged: (v) {
                setState(() => _desktopMode = v);
                _savePref('browser_desktop_mode', v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editIpfsGateway() async {
    final controller = TextEditingController(text: _ipfsGateway);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(context.l10n.ipfsGateway),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: context.l10n.customGatewayUrl,
              helperText: context.l10n.leaveEmptyUseBuiltPublic,
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.actionCancel),
            ),
            TextButton(
              onPressed: () {
                controller.clear();
                Navigator.pop(ctx, true);
              },
              child: Text(context.l10n.reset),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.actionSave),
            ),
          ],
        );
      },
    );

    if (saved != true || !mounted) return;

    final gateway = controller.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (gateway.isEmpty) {
      await prefs.remove('browser_ipfs_gateway');
      await IpfsService.setCustomGateway(null);
    } else {
      await prefs.setString('browser_ipfs_gateway', gateway);
      await IpfsService.setCustomGateway(gateway);
    }

    setState(() {
      _ipfsGateway = gateway;
    });

    if (mounted) {
      Snack.show(context, context.l10n.ipfsGatewayUpdated, level: SnackLevel.info);
    }
  }

  void _pickSearchEngine() {
    const engines = ['DuckDuckGo', 'Google', 'Bing', 'Brave'];
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SimpleDialog(
          title: Text(context.l10n.searchEngine),
          children: engines
              .map((e) => ListTile(
                    title: Text(e),
                    trailing: e == _searchEngine
                        ? Icon(Icons.check, color: cs.primary)
                        : null,
                    onTap: () {
                      setState(() => _searchEngine = e);
                      _savePref('browser_search_engine', e);
                      Navigator.pop(ctx);
                    },
                  ))
              .toList(),
        );
      },
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.clearBrowsingData),
        // overflow-fix: ensure clear-data prompt remains readable on short screens.
        content: SingleChildScrollView(
          child: Text(
            context.l10n.willClearBrowsingHistoryRecent,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.actionCancel)),
          FilledButton(
            onPressed: () async {
              await widget.repo.clearBrowsingData();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Snack.show(context, context.l10n.browsingDataCleared,
                    level: SnackLevel.info);
              }
            },
            child: Text(context.l10n.actionClear),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
