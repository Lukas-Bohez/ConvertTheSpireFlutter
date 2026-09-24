import 'package:flutter/material.dart';

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
        title: const Text('Download what?'),
        contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'This video is playing from a playlist.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.music_video_outlined),
                title: const Text('Just this video'),
                subtitle: title.isEmpty
                    ? null
                    : Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, VideoOrPlaylist.video),
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play),
                title: const Text('The whole playlist'),
                subtitle: const Text(
                    'See which songs you already have, then get the rest'),
                onTap: () => Navigator.pop(ctx, VideoOrPlaylist.playlist),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
