import 'package:flutter/material.dart';
import '../../utils/snack.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../browser/adblock/adblock_service.dart';
import '../../data/browser_db.dart';
import '../../services/ipfs_service.dart';

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
        appBar: AppBar(title: const Text('Browser Settings')),
        body: ListView(
          children: [
            // -- General --
            _SectionHeader(title: 'General'),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search Engine'),
              subtitle: Text(_searchEngine),
              onTap: _pickSearchEngine,
            ),

            // -- Privacy --
            _SectionHeader(title: 'Privacy'),
            SwitchListTile(
              secondary: const Icon(Icons.block),
              title: const Text('Ad Blocker'),
              subtitle: Text(widget.adBlockService.adBlockEnabled
                  ? 'Enabled'
                  : 'Disabled'),
              value: widget.adBlockService.adBlockEnabled,
              onChanged: (v) {
                widget.adBlockService.setEnabled(v);
                setState(() {});
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.web_asset_off),
              title: const Text('Block Pop-ups'),
              value: _blockPopups,
              onChanged: (v) {
                setState(() => _blockPopups = v);
                _savePref('browser_block_popups', v);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.do_not_disturb_on),
              title: const Text('Do Not Track'),
              value: _doNotTrack,
              onChanged: (v) {
                setState(() => _doNotTrack = v);
                _savePref('browser_dnt', v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Update Blocklist'),
              subtitle: const Text('Re-download EasyList rules'),
              onTap: () async {
                await widget.adBlockService.updateBlocklist();
                if (mounted) {
                  Snack.show(context, 'Blocklist updated',
                      level: SnackLevel.info);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: cs.error),
              title: const Text('Clear Browsing Data'),
              onTap: _showClearDataDialog,
            ),

            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('IPFS Gateway'),
              subtitle: Text(
                _ipfsGateway.isEmpty ? 'Default gateway chain' : _ipfsGateway,
              ),
              onTap: _editIpfsGateway,
            ),

            // -- Display --
            _SectionHeader(title: 'Display'),
            SwitchListTile(
              secondary: const Icon(Icons.desktop_windows),
              title: const Text('Desktop Mode'),
              subtitle: const Text('Request desktop version of websites'),
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
          title: const Text('IPFS Gateway'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Custom gateway URL',
              helperText: 'Leave empty to use the built-in public gateways.',
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                controller.clear();
                Navigator.pop(ctx, true);
              },
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
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
      Snack.show(context, 'IPFS gateway updated', level: SnackLevel.info);
    }
  }

  void _pickSearchEngine() {
    const engines = ['DuckDuckGo', 'Google', 'Bing', 'Brave'];
    showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SimpleDialog(
          title: const Text('Search Engine'),
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
        title: const Text('Clear Browsing Data'),
        // overflow-fix: ensure clear-data prompt remains readable on short screens.
        content: const SingleChildScrollView(
          child: Text(
            'This will clear your browsing history and recent sites. Favourites will not be affected.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await widget.repo.clearHistory();
              Navigator.pop(ctx);
              if (mounted) {
                Snack.show(context, 'Browsing data cleared',
                    level: SnackLevel.info);
              }
            },
            child: const Text('Clear'),
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
