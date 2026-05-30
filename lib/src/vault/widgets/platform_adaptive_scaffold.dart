import 'package:convert_the_spire_reborn/src/config/build_flags.dart';
import 'package:convert_the_spire_reborn/src/screens/browser_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/platform/desktop_window.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/about_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/guide_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/torrents_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
          final sidebarWidth =
              MediaQuery.of(context).size.width > 1400 ? 256.0 : 220.0;
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
            const _NavItem(
              icon: Icons.download_outlined,
              activeIcon: Icons.download,
              label: 'Torrents',
              route: '/torrents',
            ),
            const _NavItem(
              icon: Icons.menu_book_outlined,
              activeIcon: Icons.menu_book,
              label: 'Guide',
              route: '/guide',
            ),
            const _NavItem(
              icon: Icons.campaign_outlined,
              activeIcon: Icons.campaign,
              label: 'Channels',
              route: '/browser',
            ),
            const _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              route: '/about',
            ),
          ]
        : [
            const _NavItem(
              icon: Icons.auto_awesome,
              activeIcon: Icons.auto_awesome,
              label: 'Vault AI',
              route: '/copilot',
            ),
            const _NavItem(
              icon: Icons.chat_bubble_outline,
              activeIcon: Icons.chat_bubble,
              label: 'Local AI',
              route: '/ai_chat',
            ),
            const _NavItem(
              icon: Icons.download_outlined,
              activeIcon: Icons.download,
              label: 'Torrents',
              route: '/torrents',
            ),
            const _NavItem(
              icon: Icons.menu_book_outlined,
              activeIcon: Icons.menu_book,
              label: 'Guide',
              route: '/guide',
            ),
            const _NavItem(
              icon: Icons.campaign_outlined,
              activeIcon: Icons.campaign,
              label: 'Channels',
              route: '/browser',
            ),
            const _NavItem(
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              label: 'Settings',
              route: '/about',
            ),
          ];

    if (isDesktop) {
      return _buildDesktop(context, navItems, location);
    }

    final mobileScreens = [
      const TorrentsScreen(),
      const GuideScreen(),
      const BrowserScreen(),
      const AboutScreen(),
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
                Text(
                  getAppTitle(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                getAppSubtitle(),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          ...items.map((item) {
            final isActive = currentPath == item.route;
            return _SidebarNavTile(
              item: item,
              isActive: isActive,
              onTap: () => context.go(item.route),
            );
          }),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.fullscreen),
            title:
                const Text('Toggle Fullscreen', style: TextStyle(fontSize: 12)),
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

class _SidebarNavTile extends StatefulWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<_SidebarNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final highlighted = widget.isActive || _hovered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.isActive
                ? cs.primaryContainer
                : (_hovered ? cs.surfaceContainerHigh : Colors.transparent),
            border: Border.all(
              color: widget.isActive
                  ? cs.primary.withValues(alpha: 0.22)
                  : (_hovered
                      ? cs.outlineVariant.withValues(alpha: 0.28)
                      : Colors.transparent),
            ),
          ),
          child: ListTile(
            dense: true,
            minTileHeight: 46,
            leading: Icon(
              widget.isActive ? widget.item.activeIcon : widget.item.icon,
              color: highlighted ? cs.primary : cs.onSurfaceVariant,
            ),
            title: Text(
              widget.item.label,
              style: TextStyle(
                fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w600,
                color: highlighted ? cs.primary : cs.onSurface,
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}
