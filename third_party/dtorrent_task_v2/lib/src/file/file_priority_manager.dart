import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:logging/logging.dart';
import 'file_priority.dart';

var _log = Logger('FilePriorityManager');

/// Manages file priorities for a torrent.
///
/// This class tracks priorities for each file in a torrent and provides
/// methods to get pieces that should be prioritized based on file priorities.
class FilePriorityManager {
  final TorrentModel _metainfo;
  final Map<int, FilePriority> _priorities = {};
  final int _pieceLength;

  FilePriorityManager(this._metainfo) : _pieceLength = _metainfo.pieceLength {
    // Initialize all files with normal priority by default
    for (var i = 0; i < _metainfo.files.length; i++) {
      _priorities[i] = FilePriority.normal;
    }
  }

  /// Set priority for a single file
  void setPriority(int fileIndex, FilePriority priority) {
    if (fileIndex < 0 || fileIndex >= _metainfo.files.length) {
      _log.warning(
          'Invalid file index: $fileIndex (total files: ${_metainfo.files.length})');
      return;
    }

    _priorities[fileIndex] = priority;
    _log.fine('Set priority for file $fileIndex: $priority');
  }

  /// Set priorities for multiple files
  void setPriorities(Map<int, FilePriority> priorities) {
    for (var entry in priorities.entries) {
      setPriority(entry.key, entry.value);
    }
  }

  /// Get priority for a file
  FilePriority getPriority(int fileIndex) {
    if (fileIndex < 0 || fileIndex >= _metainfo.files.length) {
      return FilePriority.skip;
    }
    return _priorities[fileIndex] ?? FilePriority.normal;
  }

  /// Get all priorities as a map
  Map<int, FilePriority> getAllPriorities() {
    return Map.unmodifiable(_priorities);
  }

  /// Get pieces that belong to files with a specific priority or higher
  Set<int> getPiecesForPriority(FilePriority minPriority) {
    final pieces = <int>{};
    final minValue = minPriority.value;

    for (var i = 0; i < _metainfo.files.length; i++) {
      final priority = getPriority(i);
      if (priority.value >= minValue && priority.shouldDownload) {
        final file = _metainfo.files[i];
        final startPiece = file.offset ~/ _pieceLength;
        var endPiece = file.end ~/ _pieceLength;

        // Adjust endPiece if file.end is exactly on piece boundary
        if (file.end.remainder(_pieceLength) == 0) {
          endPiece--;
        }

        if (_metainfo.pieces != null) {
          for (var pieceIndex = startPiece;
              pieceIndex <= endPiece;
              pieceIndex++) {
            if (pieceIndex >= 0 && pieceIndex < _metainfo.pieces!.length) {
              pieces.add(pieceIndex);
            }
          }
        }
      }
    }

    return pieces;
  }

  /// Get pieces that should be skipped (from files with skip priority)
  Set<int> getSkippedPieces() {
    return getPiecesForPriority(FilePriority.skip);
  }

  /// Get pieces for high priority files
  Set<int> getHighPriorityPieces() {
    return getPiecesForPriority(FilePriority.high);
  }

  /// Get pieces for normal and high priority files
  Set<int> getNormalAndHighPriorityPieces() {
    return getPiecesForPriority(FilePriority.normal);
  }

  /// Get pieces grouped by priority level
  Map<FilePriority, Set<int>> getPiecesByPriority() {
    final result = <FilePriority, Set<int>>{
      FilePriority.skip: {},
      FilePriority.low: {},
      FilePriority.normal: {},
      FilePriority.high: {},
    };

    for (var i = 0; i < _metainfo.files.length; i++) {
      final priority = getPriority(i);
      final file = _metainfo.files[i];
      final startPiece = file.offset ~/ _pieceLength;
      var endPiece = file.end ~/ _pieceLength;

      if (file.end.remainder(_pieceLength) == 0) {
        endPiece--;
      }

      if (_metainfo.pieces != null) {
        for (var pieceIndex = startPiece;
            pieceIndex <= endPiece;
            pieceIndex++) {
          if (pieceIndex >= 0 && pieceIndex < _metainfo.pieces!.length) {
            result[priority]!.add(pieceIndex);
          }
        }
      }
    }

    return result;
  }

  /// Check if a piece should be skipped
  bool isPieceSkipped(int pieceIndex) {
    // Find which file(s) this piece belongs to
    for (var i = 0; i < _metainfo.files.length; i++) {
      final file = _metainfo.files[i];
      final startPiece = file.offset ~/ _pieceLength;
      var endPiece = file.end ~/ _pieceLength;

      if (file.end.remainder(_pieceLength) == 0) {
        endPiece--;
      }

      if (pieceIndex >= startPiece && pieceIndex <= endPiece) {
        final priority = getPriority(i);
        if (priority == FilePriority.skip) {
          return true;
        }
      }
    }
    return false;
  }

  /// Get priority for a piece (highest priority of files containing this piece)
  FilePriority getPiecePriority(int pieceIndex) {
    FilePriority maxPriority = FilePriority.skip;

    for (var i = 0; i < _metainfo.files.length; i++) {
      final file = _metainfo.files[i];
      final startPiece = file.offset ~/ _pieceLength;
      var endPiece = file.end ~/ _pieceLength;

      if (file.end.remainder(_pieceLength) == 0) {
        endPiece--;
      }

      if (pieceIndex >= startPiece && pieceIndex <= endPiece) {
        final priority = getPriority(i);
        if (priority.value > maxPriority.value) {
          maxPriority = priority;
        }
      }
    }

    return maxPriority;
  }

  /// Reset all priorities to normal
  void resetPriorities() {
    for (var i = 0; i < _metainfo.files.length; i++) {
      _priorities[i] = FilePriority.normal;
    }
    _log.info('Reset all file priorities to normal');
  }

  /// Get count of files by priority
  Map<FilePriority, int> getPriorityCounts() {
    final counts = <FilePriority, int>{
      FilePriority.skip: 0,
      FilePriority.low: 0,
      FilePriority.normal: 0,
      FilePriority.high: 0,
    };

    for (var i = 0; i < _metainfo.files.length; i++) {
      final priority = getPriority(i);
      counts[priority] = (counts[priority] ?? 0) + 1;
    }

    return counts;
  }
}
