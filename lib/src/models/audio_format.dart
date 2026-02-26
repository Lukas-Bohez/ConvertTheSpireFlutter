/// Supported audio output formats for conversion.
enum AudioFormat {
  mp3('mp3', 'MP3', 'Widely compatible, good quality'),
  m4a('m4a', 'M4A', 'Apple-compatible, higher quality than MP3 at same bitrate');

  const AudioFormat(this.extension, this.label, this.description);

  final String extension;
  final String label;
  final String description;

  /// FFmpeg codec flag for this format.
  String get codec {
    switch (this) {
      case AudioFormat.mp3:
        return 'libmp3lame';
      case AudioFormat.m4a:
        return 'aac';
    }
  }

  static AudioFormat? fromExtension(String ext) {
    final lower = ext.toLowerCase().replaceAll('.', '');
    for (final fmt in values) {
      if (fmt.extension == lower) return fmt;
    }
    return null;
  }
}

/// Quality presets for lossy encoders.
enum QualityPreset {
  best(320, 'Best', 'Highest available'),
  high(320, 'High', 'High quality'),
  medium(192, 'Medium', '192 kbps'),
  low(128, 'Low', '128 kbps'),
  custom(0, 'Custom', 'User sets specific bitrate');

  const QualityPreset(this.bitrate, this.label, this.description);

  final int bitrate;
  final String label;
  final String description;
}
