import 'package:flutter/material.dart';

import '../utils/l10n.dart';

/// The answer to "this video, or the playlist it is playing from?".
enum VideoOrPlaylist { video, playlist }

/// Asks whether to download the video that is playing or the whole playlist
/// it belongs to. Returns null when the user cancels.
///
/// The first choice has focus, so on a TV remote OK takes the video, which
/// is what pressing download while watching usually means.
Future<VideoOrPlaylist?> askVideoOrPlaylist(
  BuildContext context, {
  String? videoTitle,
}) {
  return showDialog<VideoOrPlaylist>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final title = videoTitle?.trim() ?? '';
      return AlertDialog(
        title: Text(context.l10n.downloadWhat),
        contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  context.l10n.videoPlayingFromPlaylist,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.music_video_outlined),
                title: Text(context.l10n.justVideo),
                subtitle: title.isEmpty
                    ? null
                    : Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, VideoOrPlaylist.video),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: Text(context.l10n.wholePlaylist),
                subtitle: Text(
                    context.l10n.seeWhichSongsAlreadyHave),
                onTap: () => Navigator.pop(ctx, VideoOrPlaylist.playlist),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.actionCancel),
          ),
        ],
      );
    },
  );
}
