import 'dart:io';

import 'package:convert_the_spire_reborn/src/screens/browser_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/about_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/ai_chat_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/guide_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrents_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrentspire_ai_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class VaultHubScreen extends StatefulWidget {
  const VaultHubScreen({super.key});

  @override
  State<VaultHubScreen> createState() => _VaultHubScreenState();
}

class _VaultHubScreenState extends State<VaultHubScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _index = 0;

  void _openSettingsTab() {
    final entries = _buildEntries();
    final settingsIndex =
        entries.indexWhere((entry) => entry.tab.label == 'Settings');
    if (settingsIndex < 0) return;
    setState(() => _index = settingsIndex);
  }

  List<_VaultEntry> _buildEntries() {
    final hideAi = !kIsWeb && Platform.isAndroid;
    return [
      _VaultEntry(
        tab: const _VaultTab(label: 'Torrents', icon: Icons.download_outlined),
        page: TorrentsScreen(
          key: const ValueKey('vault-hub-torrents'),
          onOpenSettingsTab: _openSettingsTab,
        ),
      ),
      if (!hideAi)
        const _VaultEntry(
          tab: _VaultTab(label: 'Copilot', icon: Icons.auto_awesome),
          page: TorrentSpireAiScreen(key: ValueKey('vault-hub-copilot')),
        ),
      if (!hideAi)
        const _VaultEntry(
          tab: _VaultTab(label: 'AI Chat', icon: Icons.chat_bubble_outline),
          page: AiChatScreen(key: ValueKey('vault-hub-ai-chat')),
        ),
      const _VaultEntry(
        tab: _VaultTab(label: 'Browser', icon: Icons.language),
        page: BrowserScreen(key: ValueKey('vault-hub-browser')),
      ),
      const _VaultEntry(
        tab: _VaultTab(label: 'Guide', icon: Icons.menu_book_outlined),
        page: GuideScreen(key: ValueKey('vault-hub-guide')),
      ),
      const _VaultEntry(
        tab: _VaultTab(label: 'Settings', icon: Icons.settings_outlined),
        page: AboutScreen(key: ValueKey('vault-hub-about')),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final entries = _buildEntries();
    final tabs = entries.map((e) => e.tab).toList();
    final pages = entries.map((e) => e.page).toList();
    if (_index >= pages.length) {
      _index = 0;
    }
    final isCompact = MediaQuery.of(context).size.width < 980;

    if (isCompact) {
      return Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: tabs
              .map(
                (t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.icon),
                  label: t.label,
                ),
              )
              .toList(),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            labelType: NavigationRailLabelType.all,
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: tabs
                .map(
                  (t) => NavigationRailDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.icon),
                    label: Text(t.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
    );
  }
}

class _VaultEntry {
  final _VaultTab tab;
  final Widget page;

  const _VaultEntry({required this.tab, required this.page});
}

class _VaultTab {
  final String label;
  final IconData icon;

  const _VaultTab({required this.label, required this.icon});
}
