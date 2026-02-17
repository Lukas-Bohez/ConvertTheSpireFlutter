/// Metadata about an audio file's quality.
class AudioInfo {
  final int bitrate; // kbps
  final int sampleRate; // Hz
  final String codec; // mp3, aac, etc.
  final int fileSize; // bytes
  final Duration duration;

  const AudioInfo({
    required this.bitrate,
    required this.sampleRate,
    required this.codec,
    required this.fileSize,
    required this.duration,
  });

  /// Human-readable file size.
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// Heuristic: detect if the declared quality might be fake (upscaled).
  bool get isFakeQuality {
    if (duration.inSeconds == 0) return false;
    // Expected bytes per second at declared bitrate
    final expectedBytesPerSec = (bitrate * 1000) / 8;
    final actualBytesPerSec = fileSize / duration.inSeconds;
    // If actual size is 30 % less than expected, likely upscaled
    return actualBytesPerSec < (expectedBytesPerSec * 0.7);
  }

  /// Quality label for UI display.
  String get qualityLabel {
    if (bitrate >= 320) return 'High ($bitrate kbps)';
    if (bitrate >= 192) return 'Medium ($bitrate kbps)';
    return 'Low ($bitrate kbps)';
  }
}

/// Result of analysing an audio file.
class AudioAnalysis {
  final AudioInfo info;
  final bool meetsMinimumQuality;
  final String? warning;

  const AudioAnalysis({
    required this.info,
    required this.meetsMinimumQuality,
    this.warning,
  });
}

/// Track metadata fetched from external sources (MusicBrainz, etc.).
class TrackMetadata {
  final String artist;
  final String title;
  final String album;
  final int? year;
  final String? genre;
  final String? albumArtUrl;

  const TrackMetadata({
    required this.artist,
    required this.title,
    required this.album,
    this.year,
    this.genre,
    this.albumArtUrl,
  });

  TrackMetadata copyWith({
    String? artist,
    String? title,
    String? album,
    int? year,
    String? genre,
    String? albumArtUrl,
  }) {
    return TrackMetadata(
      artist: artist ?? this.artist,
      title: title ?? this.title,
      album: album ?? this.album,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      albumArtUrl: albumArtUrl ?? this.albumArtUrl,
    );
  }
}

/// Spotify track representation used during playlist import.
class SpotifyTrack {
  final String title;
  final String artist;
  final String album;
  final Duration duration;

  const SpotifyTrack({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
  });

  String toSearchQuery() => '$artist - $title';
}

/// Result of comparing a playlist to a local folder.
class PlaylistComparison {
  final int total;
  final List<dynamic> downloaded;
  final List<dynamic> missing;
  final double completionPercentage;

  const PlaylistComparison({
    required this.total,
    required this.downloaded,
    required this.missing,
    required this.completionPercentage,
  });
}

/// Result of a bulk import operation.
class BulkImportResult {
  final List<String> successful = [];
  final List<String> failed = [];
  double progress = 0.0;
}
