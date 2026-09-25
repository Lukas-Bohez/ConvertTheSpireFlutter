/// File priority levels for torrent file selection and prioritization.
///
/// Priorities determine the order in which files (and their pieces) are downloaded.
/// Higher priority files are downloaded first, while skipped files are not downloaded at all.
enum FilePriority {
  /// File should not be downloaded (skipped)
  skip,

  /// Low priority - downloaded after normal and high priority files
  low,

  /// Normal priority - default priority for files
  normal,

  /// High priority - downloaded first
  high,
}

/// Extension methods for FilePriority
extension FilePriorityExtension on FilePriority {
  /// Get numeric value for priority (higher = more priority)
  /// skip: 0, low: 1, normal: 2, high: 3
  int get value {
    switch (this) {
      case FilePriority.skip:
        return 0;
      case FilePriority.low:
        return 1;
      case FilePriority.normal:
        return 2;
      case FilePriority.high:
        return 3;
    }
  }

  /// Check if file should be downloaded
  bool get shouldDownload => this != FilePriority.skip;
}
