/// A search result from any music source (YouTube, SoundCloud, etc.).
class SearchResult {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String thumbnailUrl;
  final String source; // 'youtube', 'soundcloud', etc.
  final String? audioUrl; // Direct audio URL (if available before download)

  /// The result's own page, for sources other than YouTube. Without it a
  /// SoundCloud or Bilibili result was queued as a YouTube link made from
  /// its id, which could never download (issue #45, fix 10).
  final String? pageUrl;

  const SearchResult({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
    required this.source,
    this.audioUrl,
    this.pageUrl,
  });

  bool get isYouTube => source.toLowerCase() == 'youtube';

  /// Where the result is watched or downloaded from, or null when unknown.
  String? get url {
    if (source == 'generic') return id;
    if (isYouTube) return 'https://www.youtube.com/watch?v=$id';
    return pageUrl;
  }

  /// Convert to a search query string (for cross-platform matching).
  String toSearchQuery() => '$artist - $title';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult && id == other.id && source == other.source;

  @override
  int get hashCode => id.hashCode ^ source.hashCode;

  @override
  String toString() => 'SearchResult($source: $artist - $title)';
}
