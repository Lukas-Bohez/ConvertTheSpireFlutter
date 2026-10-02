import 'package:flutter/material.dart';

import '../utils/l10n.dart';

/// Import and export of track lists, beside the Playlists tabs. Only an icon
/// on a phone, where the two tab names need the width.
class TrackListsMenu extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onExport;

  const TrackListsMenu(
      {super.key, required this.onImport, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final color = Theme.of(context).colorScheme.primary;
    return PopupMenuButton<bool>(
      tooltip: l10n.trackLists,
      icon: wide ? null : const Icon(Icons.import_export),
      onSelected: (export) => export ? onExport() : onImport(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: false,
          child: ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(l10n.importTrackLists),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: true,
          child: ListTile(
            leading: const Icon(Icons.download),
            title: Text(l10n.exportTrackLists),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: wide
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.import_export, color: color),
                  const SizedBox(width: 8),
                  Text(l10n.trackLists,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: color)),
                ],
              ),
            )
          : null,
    );
  }
}
