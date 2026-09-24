/// What a YouTube address points at: a video, a playlist, or both.
///
/// `watch?v=…&list=…` is what you are on while a playlist plays. Downloading
/// from there used to take only the video, silently, while a bare
/// `playlist?list=…` page was handed to the generic downloader, which has
/// nothing to do with a playlist. Knowing which of the two a link carries is
/// what lets the app ask instead of guessing.
class YouTubeLink {
  const YouTubeLink({this.videoId, this.playlistId});

  final String? videoId;
  final String? playlistId;

  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final RegExp _playlistIdPattern = RegExp(r'^[A-Za-z0-9_-]{2,}$');

  /// Parses [url], or returns null when it is not a YouTube address.
  static YouTubeLink? parse(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    final host = uri.host.toLowerCase();
    final isShortHost = host == 'youtu.be';
    final isYouTube = isShortHost ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
    if (!isYouTube) return null;

    String? video = uri.queryParameters['v'];
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (video == null && isShortHost && segments.isNotEmpty) {
      video = segments.first;
    }
    if (video == null &&
        segments.length >= 2 &&
        const {'shorts', 'embed', 'live', 'v'}.contains(segments.first)) {
      video = segments[1];
    }
    if (video != null && !_videoIdPattern.hasMatch(video)) video = null;

    var list = uri.queryParameters['list'];
    if (list != null && !_playlistIdPattern.hasMatch(list)) list = null;

    if (video == null && list == null) return const YouTubeLink();
    return YouTubeLink(videoId: video, playlistId: list);
  }

  bool get hasVideo => videoId != null;

  /// A playlist the app can download. Mixes ("RD…") are generated per
  /// listener and never end; Watch Later ("WL") and Liked ("LL") need the
  /// owner's sign-in. For those only the video makes sense.
  bool get hasDownloadablePlaylist {
    final id = playlistId;
    if (id == null) return false;
    if (id.startsWith('RD')) return false;
    if (id == 'WL' || id == 'LL' || id == 'LM') return false;
    return true;
  }

  /// Both a video and a playlist: the case where the app has to ask.
  bool get isVideoInPlaylist => hasVideo && hasDownloadablePlaylist;

  String get videoUrl => 'https://www.youtube.com/watch?v=$videoId';
  String get playlistUrl => 'https://www.youtube.com/playlist?list=$playlistId';
}
