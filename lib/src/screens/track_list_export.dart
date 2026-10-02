import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../services/bulk_import_service.dart';
import '../utils/l10n.dart';
import '../utils/snack.dart';
import 'player.dart';

/// Saves the Player's songs as a track list: "Artist - Title" lines that
/// Import track lists, here or on another device, or a playlist transfer
/// site turns back into music. The counterpart of Bulk Import.
Future<void> exportTrackList(BuildContext context) async {
  final l10n = context.l10n;
  final player = context.read<PlayerState>();
  final songs =
      player.library.where((item) => item.type == MediaType.audio).toList();
  final all = _listed(songs);
  if (all.isEmpty) {
    Snack.show(context, l10n.noSongsToExport, level: SnackLevel.warning);
    return;
  }
  final favourites =
      _listed(songs.where((item) => player.isFavourite(item.path)));

  final choice = await showDialog<({bool favouritesOnly, bool csv})>(
    context: context,
    builder: (_) =>
        _ExportDialog(allCount: all.length, favouriteCount: favourites.length),
  );
  if (choice == null || !context.mounted) return;

  final tracks = choice.favouritesOnly ? favourites : all;
  final extension = choice.csv ? 'csv' : 'txt';
  final content = choice.csv
      ? BulkImportService.buildCsvList(tracks)
      : BulkImportService.buildTextList(tracks);
  try {
    final saved = await FilePicker.platform.saveFile(
      dialogTitle: l10n.exportTrackLists,
      fileName: '${l10n.trackLists}.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (saved == null || !context.mounted) return;
    Snack.show(context, l10n.savedTrackList(tracks.length),
        level: SnackLevel.success);
  } catch (e) {
    if (!context.mounted) return;
    Snack.show(context, l10n.couldNotSaveFile(e), level: SnackLevel.error);
  }
}

List<ListedTrack> _listed(Iterable<MediaItem> songs) =>
    BulkImportService.uniqueTracks(
        songs.map((item) => BulkImportService.trackFor(
              artist: item.artist,
              title: item.title,
              // A content:// address has no file name to go by; such songs
              // always carry the title the folder scan gave them.
              fileName: item.path.startsWith('content://')
                  ? ''
                  : p.basenameWithoutExtension(item.path),
            )));

class _ExportDialog extends StatefulWidget {
  final int allCount;
  final int favouriteCount;

  const _ExportDialog({required this.allCount, required this.favouriteCount});

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  bool _favouritesOnly = false;
  bool _csv = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.exportTrackLists),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.exportTrackListsHint),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.exportAllSongs(widget.allCount)),
                  selected: !_favouritesOnly,
                  onSelected: (_) => setState(() => _favouritesOnly = false),
                ),
                if (widget.favouriteCount > 0)
                  ChoiceChip(
                    label:
                        Text(l10n.exportFavouriteSongs(widget.favouriteCount)),
                    selected: _favouritesOnly,
                    onSelected: (_) => setState(() => _favouritesOnly = true),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.exportAsText),
                  selected: !_csv,
                  onSelected: (_) => setState(() => _csv = false),
                ),
                ChoiceChip(
                  label: Text(l10n.exportAsCsv),
                  selected: _csv,
                  onSelected: (_) => setState(() => _csv = true),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: Text(l10n.exportAction),
          onPressed: () => Navigator.of(context)
              .pop((favouritesOnly: _favouritesOnly, csv: _csv)),
        ),
      ],
    );
  }
}
