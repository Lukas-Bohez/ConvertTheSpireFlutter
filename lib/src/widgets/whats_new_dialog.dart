import 'package:flutter/material.dart';

import '../services/whats_new_service.dart';

/// Shows a release's changelog entry after the app updates itself.
class WhatsNewDialog extends StatelessWidget {
  final WhatsNewEntry entry;

  const WhatsNewDialog({super.key, required this.entry});

  /// Shows the notes for [version] if they have not been seen yet.
  ///
  /// Safe to call on every launch: it is a no-op on a first install and on any
  /// launch of a version whose notes were already shown.
  static Future<void> maybeShow(BuildContext context, String version) async {
    final entry = await WhatsNewService.instance.pendingEntry(version);
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
  List<Widget> _content(BuildContext context) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    for (final raw in entry.body.split('\n')) {
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
    return AlertDialog(
      title: Text(
          entry.title.isEmpty ? 'What’s new in ${entry.version}' : entry.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Version ${entry.version}',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 12),
              ..._content(context),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}
