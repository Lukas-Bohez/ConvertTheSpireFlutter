import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';

class YouTubeService {
  final YoutubeExplode _yt;

  static const Duration _playlistItemTimeout = Duration(seconds: 10);
  static const Duration _singleVideoTimeout = Duration(seconds: 8);

  YouTubeService({required YoutubeExplode yt}) : _yt = yt;

  Future<List<PreviewItem>> preview(
    String url, {
    required bool expandPlaylist,
    required int limit,
    int startIndex = 0,
  }) async {
    if (expandPlaylist) {
      try {
        final parsedId = PlaylistId.parsePlaylistId(url);

        if (parsedId != null && parsedId.isNotEmpty) {
          if (!_isAutoMixPlaylist(parsedId)) {
            final playlistId = PlaylistId(parsedId);
            final playlistVideos = _yt.playlists.getVideos(playlistId).timeout(_playlistItemTimeout);
            final items = <PreviewItem>[];
            int index = 0;

            await for (final video in playlistVideos) {
              if (index >= startIndex) {
                items.add(_toPreviewItem(video));
                if (items.length >= limit) break;
              }
              index++;
            }

            if (items.isNotEmpty) return items;
          }
        }
      } on TimeoutException catch (_) {
        // Playlist stream stalled — fall through to single video fallback
      } catch (_) {
        // Any other failure — fall back
      }
    }

    // Fallback to single video with a timeout to avoid hangs
    try {
      final video = await _yt.videos.get(url).timeout(_singleVideoTimeout);
      return <PreviewItem>[_toPreviewItem(video)];
    } on TimeoutException catch (_) {
      return <PreviewItem>[];
    } catch (_) {
      return <PreviewItem>[];
    }
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
