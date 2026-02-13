import 'dart:typed_data';

enum DownloadStatus {
  queued,
  downloading,
  converting,
  completed,
  failed,
  cancelled,
}

class QueueItem {
  final String url;
  final String title;
  final String format;
  final String? uploader;
  final Uint8List? thumbnailBytes;
  final int progress;
  final DownloadStatus status;
  final String? outputPath;
  final String? error;

  const QueueItem({
    required this.url,
    required this.title,
    required this.format,
    required this.uploader,
    required this.thumbnailBytes,
    required this.progress,
    required this.status,
    required this.outputPath,
    required this.error,
  });

  QueueItem copyWith({
    Uint8List? thumbnailBytes,
    int? progress,
    DownloadStatus? status,
    String? outputPath,
    String? error,
  }) {
    return QueueItem(
      url: url,
      title: title,
      format: format,
      uploader: uploader,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      outputPath: outputPath ?? this.outputPath,
      error: error,
    );
  }
}
