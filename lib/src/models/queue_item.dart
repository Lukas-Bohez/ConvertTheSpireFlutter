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
  final String? outputFolder;
  final String? error;
  final String? speed;
  final String? eta;

  /// Optional per-item video quality override (e.g., 1080p, 4K). If null, app-wide setting is used.
  final String? videoQuality;

  const QueueItem({
    required this.url,
    required this.title,
    required this.format,
    required this.uploader,
    required this.thumbnailBytes,
    required this.progress,
    required this.status,
    required this.outputPath,
    this.outputFolder,
    required this.error,
    this.videoQuality,
    this.speed,
    this.eta,
  });

  QueueItem copyWith({
    String? title,
    String? format,
    Uint8List? thumbnailBytes,
    int? progress,
    DownloadStatus? status,
    Object? outputPath = _unset,
    Object? outputFolder = _unset,
    Object? error = _unset,
    String? videoQuality,
    String? speed,
    String? eta,
  }) {
    return QueueItem(
      url: url,
      title: title ?? this.title,
      format: format ?? this.format,
      uploader: uploader,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      outputPath:
          outputPath == _unset ? this.outputPath : outputPath as String?,
      outputFolder: outputFolder == _unset ? this.outputFolder : outputFolder as String?,
      error: error == _unset ? this.error : error as String?,
      videoQuality: videoQuality ?? this.videoQuality,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem && url == other.url && format == other.format;

  @override
  int get hashCode => url.hashCode ^ format.hashCode;

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'format': format,
        'uploader': uploader,
        'status': status.name,
        'progress': progress,
        'outputPath': outputPath,
        'outputFolder': outputFolder,
        'error': error,
        'videoQuality': videoQuality,
        'speed': speed,
        'eta': eta,
      };

  factory QueueItem.fromJson(Map<String, dynamic> json) => QueueItem(
        url: json['url'] as String,
        title: json['title'] as String,
        format: json['format'] as String,
        uploader: json['uploader'] as String?,
        thumbnailBytes: null,
        progress: 0,
        status: () {
          final s = json['status'] as String? ?? 'queued';
          if (s == 'downloading' || s == 'converting')
            return DownloadStatus.queued;
          return DownloadStatus.values.firstWhere(
            (e) => e.name == s,
            orElse: () => DownloadStatus.queued,
          );
        }(),
        outputPath: json['outputPath'] as String?,
        outputFolder: json['outputFolder'] as String?,
        error: null,
        videoQuality: json['videoQuality'] as String?,
        speed: json['speed'] as String?,
        eta: json['eta'] as String?,
      );
}
