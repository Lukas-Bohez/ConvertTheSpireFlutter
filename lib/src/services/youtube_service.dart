import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/preview_item.dart';

class YouTubeService {
  final YoutubeExplode _yt;

  static const Duration _playlistItemTimeout = Duration(seconds: 25);
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
            final videos = await _collectPlaylistVideos(
              playlistId,
              maxRequired: startIndex + limit,
            );
            final items = <PreviewItem>[];
            for (var index = startIndex; index < videos.length; index++) {
              items.add(_toPreviewItem(videos[index]));
              if (items.length >= limit) break;
            }

            if (items.isNotEmpty) return items;
          }
        }
      } on TimeoutException catch (_) {
        // Playlist stream stalled - fall through to single video fallback
      } catch (_) {
        // Any other failure - fall back
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

  Future<List<Video>> _collectPlaylistVideos(
    PlaylistId playlistId, {
    required int maxRequired,
  }) async {
    final byId = <String, Video>{};
    for (var attempt = 0; attempt < 3; attempt++) {
      final before = byId.length;
      final playlistVideos =
          _yt.playlists.getVideos(playlistId).timeout(_playlistItemTimeout);
      await for (final video in playlistVideos) {
        byId[video.id.value] = video;
        if (byId.length >= maxRequired) break;
      }
      if (byId.length >= maxRequired || byId.length == before) break;
    }
    return byId.values.toList();
  }
}
