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
  static const _unset = Object();

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
    String? title,
    String? format,
    Uint8List? thumbnailBytes,
    int? progress,
    DownloadStatus? status,
    Object? outputPath = _unset,
    Object? error = _unset,
  }) {
    return QueueItem(
      url: url,
      title: title ?? this.title,
      format: format ?? this.format,
      uploader: uploader,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      outputPath: outputPath == _unset ? this.outputPath : outputPath as String?,
      error: error == _unset ? this.error : error as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem && url == other.url && format == other.format;

  @override
  int get hashCode => url.hashCode ^ format.hashCode;
}
