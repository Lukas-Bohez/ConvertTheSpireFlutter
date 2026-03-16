import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A simple support page with donation links and privacy information.
///
/// This replaces the previous mining-based support system.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // ignore: avoid_print
      print('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Support Convert the Spire',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'If you enjoy using Convert the Spire, the best way to support '
                  'continued development is via donations. Your support keeps this '
                  'tool open-source, privacy-minded, and ad-free.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.coffee, color: Colors.brown),
            title: const Text('Buy Me a Coffee'),
            subtitle: const Text('Help keep this project free & open-source'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://buymeacoffee.com/orokaconner'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.favorite, color: Colors.pink),
            title: const Text('GitHub Sponsors'),
            subtitle:
                const Text('Support ongoing development and feature work'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openUrl('https://github.com/sponsors/Lukas-Bohez'),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Privacy First',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This app does not collect analytics or track what you download. '
                  'All processing happens locally on your device.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
