import 'package:flutter/material.dart';

import '../models/unified_download_task.dart';

/// TrackSpire Downloads — the one and only place a downloaded file gets
/// deleted from disk. UnifiedDownloadService.deleteFile() is only ever
/// called after this returns true; nothing in the downloads pipeline
/// deletes a completed file silently or automatically.
///
/// This mirrors the confirm-before-delete rule already established for
/// playlist pruning in masterprompt_bitplayer_trackspire_ollama.md
/// (Module 2, PruneConfirmationDialog) — same reasoning, same shape of
/// warning. If that dialog gets built in the same Cline session, it's
/// worth merging the two into one shared ConfirmDeletionDialog widget
/// under lib/src/widgets/: they show the same information (what's being
/// removed, a plain-language "this can't be undone") for the same reason,
/// and keeping them as one widget means the safety rule only has to be
/// gotten right once.
Future<bool?> showDeleteDownloadDialog(
  BuildContext context,
  UnifiedDownloadTask task,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this file?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (task.savePath != null) ...[
            const SizedBox(height: 4),
            Text(task.savePath!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          const Text(
            "This will permanently delete the file from your device. "
            "This can't be undone.",
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
