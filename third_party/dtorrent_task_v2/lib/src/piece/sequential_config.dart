/// Sequential download configuration for streaming optimization
///
/// This configuration allows fine-tuning of sequential download behavior
/// for optimal streaming performance.
///
/// Example:
/// ```dart
/// final config = SequentialConfig(
///   lookAheadSize: 10,
///   criticalZoneSize: 5 * 1024 * 1024, // 5MB
///   adaptiveStrategy: true,
///   autoDetectMoovAtom: true,
/// );
/// ```
class SequentialConfig {
  /// Size of look-ahead buffer in pieces
  ///
  /// This determines how many pieces ahead of the current playback position
  /// should be prioritized for download. Higher values provide better buffering
  /// but may slow down initial playback start.
  ///
  /// Default: 10 pieces
  final int lookAheadSize;

  /// Size of critical zone at the beginning of file in bytes
  ///
  /// This zone will be downloaded with highest priority to enable
  /// quick playback start. For MP4 files, this should be large enough
  /// to contain the moov atom.
  ///
  /// Default: 5MB
  final int criticalZoneSize;

  /// Enable adaptive strategy switching
  ///
  /// When enabled, the selector will automatically switch between
  /// rarest-first and sequential strategies based on peer availability
  /// and download speed.
  ///
  /// Default: true
  final bool adaptiveStrategy;

  /// Minimum download speed for sequential mode in bytes/second
  ///
  /// If download speed falls below this threshold and adaptiveStrategy
  /// is enabled, the selector will switch to rarest-first to improve
  /// overall download speed.
  ///
  /// Default: 50KB/s
  final int minSpeedForSequential;

  /// Auto-detect and prioritize moov atom for MP4 files
  ///
  /// When enabled, the selector will attempt to detect the moov atom
  /// position in MP4 files and prioritize downloading it first for
  /// faster playback start.
  ///
  /// Default: true
  final bool autoDetectMoovAtom;

  /// Seek latency tolerance in seconds
  ///
  /// Maximum acceptable delay when seeking to a new position.
  /// The selector will prioritize pieces more aggressively if
  /// seek operations take longer than this.
  ///
  /// Default: 2 seconds
  final int seekLatencyTolerance;

  /// Enable peer priority optimization (BEP 40)
  ///
  /// When enabled, peers will be scored and prioritized based on
  /// their ability to provide sequential pieces quickly.
  ///
  /// Default: true
  final bool enablePeerPriority;

  /// Enable fast piece resumption (BEP 53)
  ///
  /// When enabled, partially downloaded pieces will be resumed
  /// efficiently by prioritizing missing sub-pieces.
  ///
  /// Default: true
  final bool enableFastResumption;

  const SequentialConfig({
    this.lookAheadSize = 10,
    this.criticalZoneSize = 5 * 1024 * 1024, // 5MB
    this.adaptiveStrategy = true,
    this.minSpeedForSequential = 50 * 1024, // 50KB/s
    this.autoDetectMoovAtom = true,
    this.seekLatencyTolerance = 2,
    this.enablePeerPriority = true,
    this.enableFastResumption = true,
  });

  /// Create a configuration optimized for video streaming
  factory SequentialConfig.forVideoStreaming() {
    return const SequentialConfig(
      lookAheadSize: 15,
      criticalZoneSize: 10 * 1024 * 1024, // 10MB for moov atom
      adaptiveStrategy: true,
      minSpeedForSequential: 100 * 1024, // 100KB/s
      autoDetectMoovAtom: true,
      seekLatencyTolerance: 1,
      enablePeerPriority: true,
      enableFastResumption: true,
    );
  }

  /// Create a configuration optimized for audio streaming
  factory SequentialConfig.forAudioStreaming() {
    return const SequentialConfig(
      lookAheadSize: 20,
      criticalZoneSize: 2 * 1024 * 1024, // 2MB
      adaptiveStrategy: true,
      minSpeedForSequential: 30 * 1024, // 30KB/s
      autoDetectMoovAtom: false,
      seekLatencyTolerance: 1,
      enablePeerPriority: true,
      enableFastResumption: true,
    );
  }

  /// Create a minimal configuration for basic sequential download
  factory SequentialConfig.minimal() {
    return const SequentialConfig(
      lookAheadSize: 5,
      criticalZoneSize: 1 * 1024 * 1024, // 1MB
      adaptiveStrategy: false,
      minSpeedForSequential: 0,
      autoDetectMoovAtom: false,
      seekLatencyTolerance: 5,
      enablePeerPriority: false,
      enableFastResumption: false,
    );
  }

  @override
  String toString() {
    return 'SequentialConfig('
        'lookAheadSize: $lookAheadSize, '
        'criticalZoneSize: ${(criticalZoneSize / 1024 / 1024).toStringAsFixed(1)}MB, '
        'adaptiveStrategy: $adaptiveStrategy, '
        'minSpeedForSequential: ${(minSpeedForSequential / 1024).toStringAsFixed(1)}KB/s, '
        'autoDetectMoovAtom: $autoDetectMoovAtom, '
        'seekLatencyTolerance: ${seekLatencyTolerance}s, '
        'enablePeerPriority: $enablePeerPriority, '
        'enableFastResumption: $enableFastResumption'
        ')';
  }
}
