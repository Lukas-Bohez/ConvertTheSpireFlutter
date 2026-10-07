import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/support_nudge_service.dart';
import '../utils/l10n.dart';

/// The donation card at the bottom of Home, when [SupportNudgeService] says
/// it is time; nothing otherwise.
class SupportCard extends StatelessWidget {
  const SupportCard({super.key});

  static const buyMeACoffeeUrl = 'https://buymeacoffee.com/orokaconner';
  static const githubSponsorsUrl = 'https://github.com/sponsors/Lukas-Bohez';

  Future<void> _open(String url) async {
    unawaited(SupportNudgeService.instance.donated());
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('SupportCard: could not open $url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nudge = SupportNudgeService.instance;
    return ListenableBuilder(
      listenable: nudge,
      builder: (context, _) {
        if (!nudge.show) return const SizedBox.shrink();
        final l10n = context.l10n;
        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.pink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.supportCardTitle,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n.supportCardNever,
                      onPressed: nudge.never,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(l10n.supportCardBody),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.coffee),
                      label: Text(l10n.buyMeCoffee),
                      onPressed: () => _open(buyMeACoffeeUrl),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.favorite_border),
                      label: Text(l10n.githubSponsors),
                      onPressed: () => _open(githubSponsorsUrl),
                    ),
                    TextButton(
                      onPressed: nudge.notNow,
                      child: Text(l10n.supportCardNotNow),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
