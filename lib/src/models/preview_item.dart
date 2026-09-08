class PreviewItem {
  final String id;
  final String title;
  final String url;
  final String uploader;
  final Duration? duration;
  final String? thumbnailUrl;

  const PreviewItem({
    required this.id,
    required this.title,
    required this.url,
    required this.uploader,
    required this.duration,
    required this.thumbnailUrl,
  });
}
