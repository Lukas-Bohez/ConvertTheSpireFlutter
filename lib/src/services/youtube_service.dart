import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';

class YouTubeService {
  final YoutubeExplode _yt;

  YouTubeService({required YoutubeExplode yt}) : _yt = yt;

  Future<List<PreviewItem>> preview(
    String url, {
    required bool expandPlaylist,
    required int limit,
    int startIndex = 0,
  }) async {
    if (expandPlaylist) {
      try {
        // Try parsing as playlist using the URL pattern
        // This handles both playlist URLs and video URLs with playlist parameters
        final parsedId = PlaylistId.parsePlaylistId(url);
        
        if (parsedId != null && parsedId.isNotEmpty) {
          if (_isAutoMixPlaylist(parsedId)) {
            // YouTube Mix playlists cannot be expanded
          } else {
            final playlistId = PlaylistId(parsedId);
            final playlistVideos = _yt.playlists.getVideos(playlistId);
            final items = <PreviewItem>[];
            int index = 0;

            await for (final video in playlistVideos) {
              if (index >= startIndex) {
                items.add(_toPreviewItem(video));
                if (items.length >= limit) {
                  break;
                }
              }
              index++;
            }

            if (items.isNotEmpty) {
              return items;
            }
          }
        }
      } catch (e) {
        // If playlist parsing fails, fall through to single video
      }
    }

    // Fallback to single video
    final video = await _yt.videos.get(url);
    return <PreviewItem>[_toPreviewItem(video)];
  }

  PreviewItem _toPreviewItem(Video video) {
    final thumb = video.thumbnails.highResUrl;
    return PreviewItem(
      id: video.id.value,
      title: video.title,
      url: video.url,
      uploader: video.author,
      duration: video.duration,
      thumbnailUrl: thumb,
    );
  }

  void close() {
    _yt.close();
  }

  bool _isAutoMixPlaylist(String playlistId) {
    return playlistId.startsWith('RD');
  }
}
