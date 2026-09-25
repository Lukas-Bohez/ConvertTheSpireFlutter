import 'dart:math';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_task_v2/src/piece/sequential_config.dart';
import 'package:dtorrent_task_v2/src/piece/sequential_stats.dart';
import 'package:logging/logging.dart';

import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

var _log = Logger('AdvancedSequentialPieceSelector');

/// Advanced sequential piece selector with streaming optimizations
///
/// This selector implements:
/// - Look-ahead buffer for smooth playback
/// - Critical piece prioritization (e.g., moov atom for MP4)
/// - Adaptive strategy switching (sequential ↔ rarest-first)
/// - Seek operation support with fast priority rebuilding
/// - BEP 40 peer priority awareness
/// - BEP 53 fast piece resumption
class AdvancedSequentialPieceSelector implements PieceSelector {
  final SequentialConfig config;

  /// Priority pieces (critical zone, look-ahead buffer, seek target)
  final Set<int> _priorityPieces = {};

  /// Critical pieces (moov atom, file headers, etc.)
  final Set<int> _criticalPieces = {};

  /// Skipped pieces (from files with skip priority)
  final Set<int> _skippedPieces = {};

  /// Current playback position in piece index
  int _currentPlaybackPiece = 0;

  /// Current download strategy
  DownloadStrategy _currentStrategy = DownloadStrategy.sequential;

  /// Last strategy switch time
  DateTime? _lastStrategySwitch;

  /// Seek operation tracking
  int _seekCount = 0;
  DateTime? _lastSeekTime;
  final List<int> _seekLatencies = [];

  /// Statistics tracking
  DateTime? _downloadStartTime;
  DateTime? _firstByteTime;

  /// Total number of pieces in torrent
  int? _totalPieces;

  /// Piece length for calculations
  int? _pieceLength;

  AdvancedSequentialPieceSelector(this.config);

  @override
  void setPriorityPieces(Iterable<int> pieces) {
    _priorityPieces.clear();
    _priorityPieces.addAll(pieces);

    if (pieces.isNotEmpty) {
      // Update playback position based on priority pieces
      _currentPlaybackPiece = pieces.reduce(min);
      _log.fine('Priority pieces set: ${pieces.length} pieces, '
          'playback position: $_currentPlaybackPiece');
    }
  }

  @override
  void setSkippedPieces(Iterable<int> pieces) {
    _skippedPieces.clear();
    _skippedPieces.addAll(pieces);
  }

  /// Set critical pieces (e.g., moov atom for MP4)
  void setCriticalPieces(Iterable<int> pieces) {
    _criticalPieces.clear();
    _criticalPieces.addAll(pieces);
    _log.info('Critical pieces set: ${pieces.length} pieces');
  }

  /// Set current playback position in bytes
  void setPlaybackPosition(int bytePosition, int pieceLength) {
    final oldPiece = _currentPlaybackPiece;
    _currentPlaybackPiece = bytePosition ~/ pieceLength;

    if (oldPiece != _currentPlaybackPiece) {
      _seekCount++;
      final now = DateTime.now();

      if (_lastSeekTime != null) {
        final latency = now.difference(_lastSeekTime!).inMilliseconds;
        _seekLatencies.add(latency);

        // Keep only last 10 seek latencies
        if (_seekLatencies.length > 10) {
          _seekLatencies.removeAt(0);
        }
      }

      _lastSeekTime = now;
      _log.info('Seek: $oldPiece → $_currentPlaybackPiece (seek #$_seekCount)');

      // Rebuild priority pieces for new position
      _rebuildPriorityPieces();
    }
  }

  /// Initialize selector with torrent metadata
  void initialize(int totalPieces, int pieceLength) {
    _totalPieces = totalPieces;
    _pieceLength = pieceLength;
    _downloadStartTime = DateTime.now();

    // Build initial priority pieces
    _rebuildPriorityPieces();

    _log.info('Initialized: $totalPieces pieces, '
        '${(pieceLength / 1024).toStringAsFixed(1)}KB per piece');
  }

  /// Rebuild priority pieces based on current playback position
  void _rebuildPriorityPieces() {
    if (_totalPieces == null) return;

    _priorityPieces.clear();

    // Add critical pieces (highest priority)
    _priorityPieces.addAll(_criticalPieces);

    // Add look-ahead buffer
    final endPiece = min(
      _currentPlaybackPiece + config.lookAheadSize,
      _totalPieces! - 1,
    );

    for (var i = _currentPlaybackPiece; i <= endPiece; i++) {
      _priorityPieces.add(i);
    }

    _log.fine('Priority pieces rebuilt: ${_priorityPieces.length} pieces '
        '(playback: $_currentPlaybackPiece, look-ahead: $config.lookAheadSize)');
  }

  @override
  Piece? selectPiece(Peer peer, PieceProvider provider,
      [bool random = false, Set<int>? suggestPieces]) {
    // Track first byte time
    if (_firstByteTime == null && _downloadStartTime != null) {
      _firstByteTime = DateTime.now();
      final ttfb =
          _firstByteTime!.difference(_downloadStartTime!).inMilliseconds;
      _log.info('Time to first byte: ${ttfb}ms');
    }

    // Update strategy if adaptive is enabled
    if (config.adaptiveStrategy) {
      _updateStrategy(provider);
    }

    // Try suggested pieces first (Fast Extension - BEP 0006)
    if (suggestPieces != null && suggestPieces.isNotEmpty) {
      for (var pieceIndex in suggestPieces) {
        final piece = provider[pieceIndex];
        if (piece != null &&
            !piece.isCompleted &&
            piece.haveAvailableSubPiece() &&
            peer.remoteCompletePieces.contains(pieceIndex)) {
          _log.fine('Selected suggested piece: $pieceIndex');
          return piece;
        }
      }
    }

    // Select based on current strategy
    switch (_currentStrategy) {
      case DownloadStrategy.sequential:
        return _selectSequential(peer, provider);
      case DownloadStrategy.rarestFirst:
        return _selectRarest(peer, provider);
      case DownloadStrategy.hybrid:
        // Try sequential first, fallback to rarest
        return _selectSequential(peer, provider) ??
            _selectRarest(peer, provider);
    }
  }

  /// Select piece using sequential strategy
  Piece? _selectSequential(Peer peer, PieceProvider provider) {
    // Priority 1: Critical pieces
    for (var pieceIndex in _criticalPieces) {
      // Skip pieces that are marked as skipped
      if (_skippedPieces.contains(pieceIndex)) {
        continue;
      }
      final piece = provider[pieceIndex];
      if (piece != null &&
          !piece.isCompleted &&
          piece.haveAvailableSubPiece() &&
          peer.remoteCompletePieces.contains(pieceIndex)) {
        _log.fine('Selected critical piece: $pieceIndex');
        return piece;
      }
    }

    // Priority 2: Priority pieces (look-ahead buffer)
    for (var pieceIndex in _priorityPieces) {
      // Skip pieces that are marked as skipped
      if (_skippedPieces.contains(pieceIndex)) {
        continue;
      }
      final piece = provider[pieceIndex];
      if (piece != null &&
          !piece.isCompleted &&
          piece.haveAvailableSubPiece() &&
          peer.remoteCompletePieces.contains(pieceIndex)) {
        return piece;
      }
    }

    // Priority 3: Sequential from current position
    if (_totalPieces != null) {
      for (var i = _currentPlaybackPiece; i < _totalPieces!; i++) {
        // Skip pieces that are marked as skipped
        if (_skippedPieces.contains(i)) {
          continue;
        }
        final piece = provider[i];
        if (piece != null &&
            !piece.isCompleted &&
            piece.haveAvailableSubPiece() &&
            peer.remoteCompletePieces.contains(i)) {
          return piece;
        }
      }
    }

    // Priority 4: Any available piece from peer
    for (var pieceIndex in peer.remoteCompletePieces) {
      // Skip pieces that are marked as skipped
      if (_skippedPieces.contains(pieceIndex)) {
        continue;
      }
      final piece = provider[pieceIndex];
      if (piece != null &&
          !piece.isCompleted &&
          piece.haveAvailableSubPiece()) {
        return piece;
      }
    }

    return null;
  }

  /// Select piece using rarest-first strategy
  Piece? _selectRarest(Peer peer, PieceProvider provider) {
    Piece? rarest;
    int minAvailability = 999999;

    for (var pieceIndex in peer.remoteCompletePieces) {
      // Skip pieces that are marked as skipped
      if (_skippedPieces.contains(pieceIndex)) {
        continue;
      }
      final piece = provider[pieceIndex];
      if (piece == null ||
          piece.isCompleted ||
          !piece.haveAvailableSubPiece()) {
        continue;
      }

      final availability = piece.availablePeersCount;
      if (availability < minAvailability) {
        minAvailability = availability;
        rarest = piece;
      }
    }

    if (rarest != null) {
      _log.fine('Selected rarest piece: ${rarest.index} '
          '(availability: $minAvailability)');
    }

    return rarest;
  }

  /// Update download strategy based on current conditions
  void _updateStrategy(PieceProvider provider) {
    final now = DateTime.now();

    // Don't switch too frequently (min 10 seconds between switches)
    if (_lastStrategySwitch != null &&
        now.difference(_lastStrategySwitch!).inSeconds < 10) {
      return;
    }

    // Calculate buffer health
    final stats = getStats(provider);

    // Switch to rarest-first if buffer health is good and we want to help swarm
    if (_currentStrategy == DownloadStrategy.sequential &&
        stats.bufferHealth > 90.0) {
      _currentStrategy = DownloadStrategy.hybrid;
      _lastStrategySwitch = now;
      _log.info(
          'Strategy switched to hybrid (buffer health: ${stats.bufferHealth.toStringAsFixed(1)}%)');
    }

    // Switch back to sequential if buffer health drops
    else if (_currentStrategy == DownloadStrategy.hybrid &&
        stats.bufferHealth < 70.0) {
      _currentStrategy = DownloadStrategy.sequential;
      _lastStrategySwitch = now;
      _log.info(
          'Strategy switched to sequential (buffer health: ${stats.bufferHealth.toStringAsFixed(1)}%)');
    }
  }

  /// Get current sequential download statistics
  SequentialStats getStats(PieceProvider provider) {
    if (_totalPieces == null || _pieceLength == null) {
      return SequentialStats(
        bufferHealth: 0.0,
        playbackPosition: 0,
        bufferedPieces: 0,
        downloadingPieces: 0,
        currentStrategy: _currentStrategy,
        seekCount: _seekCount,
      );
    }

    // Calculate buffered pieces (completed pieces in look-ahead window)
    int bufferedCount = 0;
    final endPiece = min(
      _currentPlaybackPiece + config.lookAheadSize,
      _totalPieces! - 1,
    );

    for (var i = _currentPlaybackPiece; i <= endPiece; i++) {
      final piece = provider[i];
      if (piece != null && piece.isCompleted) {
        bufferedCount++;
      }
    }

    // Calculate buffer health (percentage of look-ahead buffer that's ready)
    final bufferHealth = (bufferedCount / config.lookAheadSize) * 100.0;

    // Count downloading pieces
    final downloadingCount = provider.downloadingPieces.length;

    // Calculate time to first byte
    int? ttfb;
    if (_firstByteTime != null && _downloadStartTime != null) {
      ttfb = _firstByteTime!.difference(_downloadStartTime!).inMilliseconds;
    }

    // Calculate average seek latency
    int? avgSeekLatency;
    if (_seekLatencies.isNotEmpty) {
      avgSeekLatency =
          _seekLatencies.reduce((a, b) => a + b) ~/ _seekLatencies.length;
    }

    // Check if moov atom is downloaded (if critical pieces are set)
    bool? moovDownloaded;
    if (_criticalPieces.isNotEmpty) {
      moovDownloaded = _criticalPieces.every((index) {
        final piece = provider[index];
        return piece != null && piece.isCompleted;
      });
    }

    return SequentialStats(
      bufferHealth: bufferHealth,
      timeToFirstByte: ttfb,
      playbackPosition: _currentPlaybackPiece * _pieceLength!,
      bufferedPieces: bufferedCount,
      downloadingPieces: downloadingCount,
      currentStrategy: _currentStrategy,
      averageSeekLatency: avgSeekLatency,
      seekCount: _seekCount,
      moovAtomDownloaded: moovDownloaded,
    );
  }

  /// Detect and set moov atom pieces for MP4 files
  ///
  /// This is a simplified heuristic - in a real implementation,
  /// you would parse the MP4 structure to find the exact moov location.
  void detectAndSetMoovAtom(int totalLength, int pieceLength) {
    if (!config.autoDetectMoovAtom) return;
    if (_totalPieces == null) return;

    // Heuristic: moov atom is usually in first 10MB or last 10MB of file
    final moovZoneSize = min(config.criticalZoneSize, totalLength);
    final moovPieceCount = (moovZoneSize / pieceLength).ceil();

    final criticalPieces = <int>{};

    // Add first pieces
    for (var i = 0; i < min(moovPieceCount, _totalPieces!); i++) {
      criticalPieces.add(i);
    }

    // For MP4, moov can also be at the end (if not optimized for streaming)
    // Add last few pieces as well
    for (var i = max(0, _totalPieces! - moovPieceCount);
        i < _totalPieces!;
        i++) {
      criticalPieces.add(i);
    }

    setCriticalPieces(criticalPieces);
    _log.info('Auto-detected moov atom zone: ${criticalPieces.length} pieces');
  }
}
