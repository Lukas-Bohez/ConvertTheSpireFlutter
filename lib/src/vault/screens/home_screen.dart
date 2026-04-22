import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:convert_the_spire_reborn/src/vault/services/identity_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = IdentityService.instance.identity;
    final fingerprint = identity?.publicKeyBase64 ?? 'N/A';
    final cs = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final maxContentWidth = width > 1600 ? 1280.0 : 1120.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault The Spire'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: width > 1200 ? 28 : 16,
              vertical: 20,
            ),
            child: ListView(
              children: [
            const SizedBox(height: 8),
            const Text(
              'Vault The Spire',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            const Text(
              'What goes into the Vault, stays in the Vault.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 1200
                    ? 4
                    : constraints.maxWidth > 800
                    ? 3
                    : 2;
                final childAspectRatio = constraints.maxWidth > 1200
                    ? 1.55
                    : 1.35;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: childAspectRatio,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _QuickActionCard(
                      icon: Icons.chat_bubble_outline,
                      title: 'Local AI Chat',
                      subtitle: 'Chat with your local Ollama model',
                      onTap: () => context.go('/ai_chat'),
                    ),
                    _QuickActionCard(
                      icon: Icons.download_outlined,
                      title: 'Add Torrent',
                      subtitle: 'Share or download files',
                      onTap: () => context.go('/torrents'),
                    ),
                    _QuickActionCard(
                      icon: Icons.campaign_outlined,
                      title: 'Browse Channels',
                      subtitle: 'Join public or private channels',
                      onTap: () => context.go('/browser'),
                    ),
                    _QuickActionCard(
                      icon: Icons.settings_outlined,
                      title: 'Settings',
                      subtitle: 'Manage preferences',
                      onTap: () => context.go('/about'),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: cs.tertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Identity ready',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Fingerprint: ${fingerprint.length > 16 ? fingerprint.substring(0, 16) : fingerprint}',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
