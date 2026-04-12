import 'package:flutter/material.dart';

import 'package:convert_the_spire_reborn/src/vault/screens/about_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/ai_chat_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/browser_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/guide_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrents_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrentspire_ai_screen.dart';

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

  static const _tabs = [
    _VaultTab(label: 'Torrents', icon: Icons.download_outlined),
    _VaultTab(label: 'Copilot', icon: Icons.auto_awesome),
    _VaultTab(label: 'AI Chat', icon: Icons.chat_bubble_outline),
    _VaultTab(label: 'Browser', icon: Icons.language),
    _VaultTab(label: 'Guide', icon: Icons.menu_book_outlined),
    _VaultTab(label: 'Settings', icon: Icons.settings_outlined),
  ];

  static const _pages = [
    TorrentsScreen(key: ValueKey('vault-hub-torrents')),
    TorrentSpireAiScreen(key: ValueKey('vault-hub-copilot')),
    AiChatScreen(key: ValueKey('vault-hub-ai-chat')),
    BrowserScreen(key: ValueKey('vault-hub-browser')),
    GuideScreen(key: ValueKey('vault-hub-guide')),
    AboutScreen(key: ValueKey('vault-hub-about')),
  ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isCompact = MediaQuery.of(context).size.width < 980;

    if (isCompact) {
      return Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: _tabs
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
            destinations: _tabs
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
          Expanded(child: IndexedStack(index: _index, children: _pages)),
        ],
      ),
    );
  }
}

class _VaultTab {
  final String label;
  final IconData icon;

  const _VaultTab({required this.label, required this.icon});
}
