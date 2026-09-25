/// Sequential download statistics
///
/// Provides metrics and health indicators for sequential download performance.
class SequentialStats {
  /// Current buffer health percentage (0-100)
  ///
  /// Indicates how well buffered the playback is. Values above 80% are good,
  /// below 50% may cause buffering during playback.
  final double bufferHealth;

  /// Time to first byte in milliseconds
  ///
  /// Time from download start to receiving the first piece of data.
  final int? timeToFirstByte;

  /// Current playback position in bytes
  final int playbackPosition;

  /// Number of pieces in look-ahead buffer
  final int bufferedPieces;

  /// Number of pieces being downloaded
  final int downloadingPieces;

  /// Current download strategy (sequential or rarest-first)
  final DownloadStrategy currentStrategy;

  /// Average seek latency in milliseconds
  final int? averageSeekLatency;

  /// Number of completed seeks
  final int seekCount;

  /// Whether moov atom has been downloaded (for MP4)
  final bool? moovAtomDownloaded;

  const SequentialStats({
    required this.bufferHealth,
    this.timeToFirstByte,
    required this.playbackPosition,
    required this.bufferedPieces,
    required this.downloadingPieces,
    required this.currentStrategy,
    this.averageSeekLatency,
    required this.seekCount,
    this.moovAtomDownloaded,
  });

  @override
  String toString() {
    return 'SequentialStats('
        'bufferHealth: ${bufferHealth.toStringAsFixed(1)}%, '
        'timeToFirstByte: ${timeToFirstByte ?? "N/A"}ms, '
        'playbackPosition: ${(playbackPosition / 1024 / 1024).toStringAsFixed(2)}MB, '
        'bufferedPieces: $bufferedPieces, '
        'downloadingPieces: $downloadingPieces, '
        'strategy: ${currentStrategy.name}, '
        'seekCount: $seekCount'
        ')';
  }
}

/// Download strategy type
enum DownloadStrategy {
  /// Sequential download (in order)
  sequential,

  /// Rarest-first download (for better peer cooperation)
  rarestFirst,

  /// Hybrid strategy (adaptive)
  hybrid,
}
