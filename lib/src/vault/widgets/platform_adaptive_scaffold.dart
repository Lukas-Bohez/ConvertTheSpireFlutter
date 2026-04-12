import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/desktop_window.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/about_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/browser_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/guide_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrents_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';

class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _mobileIndex = 0;
  bool _didInitMobileIndex = false;

  int _mobileIndexForPath(String path) {
    switch (path) {
      case '/guide':
        return 1;
      case '/browser':
        return 2;
      case '/about':
        return 3;
      case '/torrents':
      default:
        return 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitMobileIndex) return;
    final location = GoRouterState.of(context).uri.path;
    _mobileIndex = _mobileIndexForPath(location);
    _didInitMobileIndex = true;
  }

  Widget _buildDesktop(
    BuildContext context,
    List<_NavItem> navItems,
    String location,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService.persistentSidebarListenable,
      builder: (context, persistentSidebar, _) {
        if (persistentSidebar) {
          final sidebarWidth = MediaQuery.of(context).size.width > 1400
              ? 240.0
              : 200.0;
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: _Sidebar(items: navItems, currentPath: location),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: widget.child),
              ],
            ),
          );
        }

        return Scaffold(
          body: widget.child,
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: FloatingActionButton.small(
            tooltip: 'Open navigation',
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in navItems)
                          ListTile(
                            leading: Icon(item.icon),
                            title: Text(item.label),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              context.go(item.route);
                            },
                          ),
                        ListTile(
                          leading: const Icon(Icons.fullscreen),
                          title: const Text('Toggle Fullscreen'),
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await toggleDesktopFullScreen();
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            child: const Icon(Icons.menu),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final location = GoRouterState.of(context).uri.path;
    final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

    final navItems = isMobile
        ? [
            _NavItem(
              icon: Icons.download_outlined,
              activeIcon: Icons.download,
              label: 'Torrents',
              route: '/torrents',
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              activeIcon: Icons.menu_book,
              label: 'Guide',
              route: '/guide',
            ),
            _NavItem(
              icon: Icons.campaign_outlined,
              activeIcon: Icons.campaign,
              label: 'Channels',
              route: '/browser',
            ),
            _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              route: '/about',
            ),
          ]
        : [
            _NavItem(
              icon: Icons.auto_awesome,
              activeIcon: Icons.auto_awesome,
              label: 'Vault AI',
              route: '/copilot',
            ),
            _NavItem(
              icon: Icons.chat_bubble_outline,
              activeIcon: Icons.chat_bubble,
              label: 'Local AI',
              route: '/ai_chat',
            ),
            _NavItem(
              icon: Icons.download_outlined,
              activeIcon: Icons.download,
              label: 'Torrents',
              route: '/torrents',
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              activeIcon: Icons.menu_book,
              label: 'Guide',
              route: '/guide',
            ),
            _NavItem(
              icon: Icons.campaign_outlined,
              activeIcon: Icons.campaign,
              label: 'Channels',
              route: '/browser',
            ),
            _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              route: '/about',
            ),
          ];

    if (isDesktop) {
      return _buildDesktop(context, navItems, location);
    }

    final mobileScreens = const [
      TorrentsScreen(),
      GuideScreen(),
      BrowserScreen(),
      AboutScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _mobileIndex, children: mobileScreens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileIndex,
        onDestinationSelected: (i) => setState(() => _mobileIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Torrents',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Guide',
          ),
          NavigationDestination(
            icon: Icon(Icons.language_outlined),
            selectedIcon: Icon(Icons.language),
            label: 'Browser',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final String currentPath;
  const _Sidebar({required this.items, required this.currentPath});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.surfaceContainerLow,
            cs.surface,
          ],
        ),
        border: Border(
          right: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.lock,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Vault The Spire',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Vault The Spire',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...items.map((item) {
            final isActive = currentPath == item.route;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isActive ? cs.primaryContainer : Colors.transparent,
                  border: Border.all(
                    color: isActive ? cs.primary.withValues(alpha: 0.2) : Colors.transparent,
                  ),
                ),
                child: ListTile(
                  leading: Icon(
                    isActive ? item.activeIcon : item.icon,
                    color: isActive ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? cs.primary : cs.onSurface,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => context.go(item.route),
                ),
              ),
            );
          }),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.fullscreen),
            title: const Text('Toggle Fullscreen', style: TextStyle(fontSize: 12)),
            onTap: () async {
              await toggleDesktopFullScreen();
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Identity active', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
