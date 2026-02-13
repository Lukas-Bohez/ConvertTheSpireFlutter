import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<PreviewItem>> preview(
    String url, {
    required bool expandPlaylist,
    required int limit,
  }) async {
    if (expandPlaylist) {
      try {
        // Try parsing as playlist using the URL pattern
        // This handles both playlist URLs and video URLs with playlist parameters
        final parsedId = PlaylistId.parsePlaylistId(url);
        
        if (parsedId != null && parsedId.isNotEmpty) {
          if (_isAutoMixPlaylist(parsedId)) {
            print('Playlist ID $parsedId appears to be a YouTube Mix and cannot be expanded.');
          } else {
            print('Found playlist ID: $parsedId');
            final playlistId = PlaylistId(parsedId);
            final playlistVideos = _yt.playlists.getVideos(playlistId);
            final items = <PreviewItem>[];

            await for (final video in playlistVideos) {
              items.add(_toPreviewItem(video));
              print('Added video ${items.length}: ${video.title}');
              if (items.length >= limit) {
                break;
              }
            }

            print('Playlist expansion complete: ${items.length} items');
            if (items.isNotEmpty) {
              return items;
            }
          }
        } else {
          print('No playlist ID found in URL');
        }
      } catch (e, stackTrace) {
        // If playlist parsing fails, fall through to single video
        print('Playlist expansion failed: $e');
        print('Stack trace: $stackTrace');
      }
    }

    // Fallback to single video
    print('Falling back to single video');
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
