import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../browser/adblock/adblock_service.dart';
import '../../data/browser_db.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchEngine =
          prefs.getString('browser_search_engine') ?? 'DuckDuckGo';
      _desktopMode = prefs.getBool('browser_desktop_mode') ?? false;
      _blockPopups = prefs.getBool('browser_block_popups') ?? true;
      _doNotTrack = prefs.getBool('browser_dnt') ?? true;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Browser Settings')),
      body: ListView(
        children: [
          // ── General ──
          _SectionHeader(title: 'General'),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search Engine'),
            subtitle: Text(_searchEngine),
            onTap: _pickSearchEngine,
          ),

          // ── Privacy ──
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Blocklist updated')),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: cs.error),
            title: const Text('Clear Browsing Data'),
            onTap: _showClearDataDialog,
          ),

          // ── Display ──
          _SectionHeader(title: 'Display'),
          SwitchListTile(
            secondary: const Icon(Icons.desktop_windows),
            title: const Text('Desktop Mode'),
            subtitle:
                const Text('Request desktop version of websites'),
            value: _desktopMode,
            onChanged: (v) {
              setState(() => _desktopMode = v);
              _savePref('browser_desktop_mode', v);
            },
          ),
        ],
      ),
    );
  }

  void _pickSearchEngine() {
    const engines = ['DuckDuckGo', 'Google', 'Bing', 'Brave'];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Search Engine'),
        children: engines
            .map((e) => ListTile(
                  title: Text(e),
                  // RadioGroup API introduced — suppress deprecation info until
                  // a full migration is implemented.
                  // ignore: deprecated_member_use
                  leading: Radio<String>(
                    value: e,
                    groupValue: _searchEngine,
                    onChanged: (v) {
                      setState(() => _searchEngine = v!);
                      _savePref('browser_search_engine', v!);
                      Navigator.pop(ctx);
                    },
                  ),
                  onTap: () {
                    setState(() => _searchEngine = e);
                    _savePref('browser_search_engine', e);
                    Navigator.pop(ctx);
                  },
                ))
            .toList(),
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Browsing Data'),
        content: const Text(
            'This will clear your browsing history and recent sites. Favourites will not be affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await widget.repo.clearHistory();
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Browsing data cleared')),
                );
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
