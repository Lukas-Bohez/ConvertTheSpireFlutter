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
        final playlistId = PlaylistId(url);
        final playlistVideos = _yt.playlists.getVideos(playlistId);
        final items = <PreviewItem>[];
        await for (final video in playlistVideos) {
          items.add(_toPreviewItem(video));
          if (items.length >= limit) {
            break;
          }
        }
        return items;
      } catch (_) {}
    }

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
}
