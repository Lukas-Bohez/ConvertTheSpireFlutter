import 'package:flutter/material.dart';

import '../services/whats_new_service.dart';
import '../utils/l10n.dart';

/// Shows a release's changelog entry after the app updates itself, followed
/// by any releases the person skipped.
class WhatsNewDialog extends StatelessWidget {
  final WhatsNewEntry entry;

  const WhatsNewDialog({super.key, required this.entry});

  /// Shows the notes for [version] if they have not been seen yet.
  ///
  /// Safe to call on every launch: it is a no-op on a first install and on any
  /// launch of a version whose notes were already shown.
  static Future<void> maybeShow(
    BuildContext context,
    String version, {
    bool freshInstall = true,
  }) async {
    final entry = await WhatsNewService.instance
        .pendingEntry(version, freshInstall: freshInstall);
    if (entry == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => WhatsNewDialog(entry: entry),
    );
    await WhatsNewService.instance.markShown(version);
  }

  /// Turns the changelog's Markdown into plain lines.
  ///
  /// Deliberately not a Markdown renderer: the app does not ship one, and the
  /// entries are bullet lists with bold lead-ins, which read fine as text.
  List<Widget> _content(BuildContext context, String body) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    for (final raw in body.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      if (line.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            line.substring(4).trim(),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ));
        continue;
      }
      final isBullet = line.trimLeft().startsWith('- ');
      final text = isBullet ? line.trimLeft().substring(2) : line;
      widgets.add(Padding(
        padding: EdgeInsets.only(left: isBullet ? 12 : 0, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isBullet) const Text('•  '),
            Expanded(
              child:
                  Text(_stripEmphasis(text), style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ));
    }
    return widgets;
  }

  static String _stripEmphasis(String text) =>
      text.replaceAll('**', '').replaceAll('`', '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
          entry.title.isEmpty ? context.l10n.whatsNew(entry.version) : entry.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          // Room for the desktop scrollbar, which otherwise sits on the text.
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.version(entry.version),
                  style: theme.textTheme.labelMedium),
              const SizedBox(height: 12),
              ..._content(context, entry.body),
              for (final older in entry.earlier) ...[
                const Divider(height: 32),
                Text(
                  older.title.isEmpty
                      ? context.l10n.version(older.version)
                      : older.title,
                  style: theme.textTheme.titleMedium,
                ),
                if (older.title.isNotEmpty)
                  Text(context.l10n.version(older.version),
                      style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                ..._content(context, older.body),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.got),
        ),
      ],
    );
  }
}
