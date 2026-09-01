/// TrackSpire Downloads — unified model for the cross-protocol download
/// dashboard (Direct HTTP + BitTorrent).
///
/// IMPORTANT NAMING NOTE: `lib/src/models/queue_item.dart` already defines
/// its own `DownloadStatus` enum for the existing yt-dlp media queue
/// (`QueueItem`, driven by `lib/src/services/download_service.dart`). Every
/// type here is deliberately prefixed `Unified*` so it can never collide
/// with that enum or with `DownloadStats`/`DownloadToken`/`DownloadResult`
/// in `download_service.dart`. This file does NOT replace the yt-dlp
/// pipeline — it sits alongside it for direct-HTTP files (APKs, archives,
/// browser-detected media links) and BitTorrent downloads, the two things
/// the app can't currently show in one place. See `UnifiedDownloadService`
/// for how the two pipelines are merged for display only.
library;

enum UnifiedDownloadType { directHttp, torrent }

enum UnifiedDownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

enum UnifiedDownloadCategory { media, appUpdate, archive, other }

/// What, if anything, should happen automatically once the bytes are on
/// disk. `promptInstall` never fires itself from this model — it only
/// flags intent; `UnifiedDownloadService` is the single place that acts on
/// it, and only ever behind the kPlayStoreBuild guard.
enum UnifiedPostDownloadAction { none, promptInstall, revealInFolder }

class UnifiedDownloadTask {
  final String id;
  final String title;
  final String sourceUrl;
  final UnifiedDownloadType type;
  final UnifiedDownloadCategory category;
  final UnifiedPostDownloadAction postDownloadAction;
  final DateTime createdAt;

  final UnifiedDownloadStatus status;
  final int bytesDownloaded;
  final int totalBytes;
  final int downloadSpeedBytesPerSec;
  final String? savePath;
  final DateTime? completedAt;
  final String? errorMessage;

  const UnifiedDownloadTask({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.type,
    required this.category,
    required this.createdAt,
    this.postDownloadAction = UnifiedPostDownloadAction.none,
    this.status = UnifiedDownloadStatus.queued,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.downloadSpeedBytesPerSec = 0,
    this.savePath,
    this.completedAt,
    this.errorMessage,
  });

  double get progress =>
      totalBytes > 0 ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0) : 0.0;

  bool get isActive =>
      status == UnifiedDownloadStatus.downloading ||
      status == UnifiedDownloadStatus.queued;

  bool get isFinished =>
      status == UnifiedDownloadStatus.completed ||
      status == UnifiedDownloadStatus.failed ||
      status == UnifiedDownloadStatus.canceled;

  static const _unset = Object();

  UnifiedDownloadTask copyWith({
    UnifiedDownloadStatus? status,
    int? bytesDownloaded,
    int? totalBytes,
    int? downloadSpeedBytesPerSec,
    String? savePath,
    DateTime? completedAt,
    Object? errorMessage = _unset,
  }) {
    return UnifiedDownloadTask(
      id: id,
      title: title,
      sourceUrl: sourceUrl,
      type: type,
      category: category,
      postDownloadAction: postDownloadAction,
      createdAt: createdAt,
      status: status ?? this.status,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadSpeedBytesPerSec:
          downloadSpeedBytesPerSec ?? this.downloadSpeedBytesPerSec,
      savePath: savePath ?? this.savePath,
      completedAt: completedAt ?? this.completedAt,
      errorMessage:
          errorMessage == _unset ? this.errorMessage : errorMessage as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceUrl': sourceUrl,
        'type': type.name,
        'category': category.name,
        'postDownloadAction': postDownloadAction.name,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'bytesDownloaded': bytesDownloaded,
        'totalBytes': totalBytes,
        'savePath': savePath,
        'completedAt': completedAt?.toIso8601String(),
        'errorMessage': errorMessage,
      };

  factory UnifiedDownloadTask.fromJson(Map<String, dynamic> json) {
    return UnifiedDownloadTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Download',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      type: UnifiedDownloadType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => UnifiedDownloadType.directHttp,
      ),
      category: UnifiedDownloadCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => UnifiedDownloadCategory.other,
      ),
      postDownloadAction: UnifiedPostDownloadAction.values.firstWhere(
        (e) => e.name == json['postDownloadAction'],
        orElse: () => UnifiedPostDownloadAction.none,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      // Anything that was mid-flight when the app last closed reopens as
      // queued, never as "downloading" with no worker actually behind it —
      // same defensive rule QueueItem.fromJson already uses today.
      status: () {
        final raw = json['status'] as String? ?? 'queued';
        if (raw == 'downloading') return UnifiedDownloadStatus.queued;
        return UnifiedDownloadStatus.values.firstWhere(
          (e) => e.name == raw,
          orElse: () => UnifiedDownloadStatus.queued,
        );
      }(),
      bytesDownloaded: (json['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      savePath: json['savePath'] as String?,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
