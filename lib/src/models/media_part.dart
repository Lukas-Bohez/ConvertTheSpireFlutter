import 'package:flutter/foundation.dart';

/// A part of a video or song to download instead of all of it (issue #41):
/// from [start] to [end].
@immutable
class MediaPart {
  const MediaPart(this.start, this.end);

  final Duration start;
  final Duration end;

  bool get isValid => start >= Duration.zero && end > start;

  /// For the file's name, which can't have colons on Windows:
  /// `1m05s-2m30s`.
  String get fileLabel => '${_label(start)}-${_label(end)}';

  /// yt-dlp's `--download-sections`: a time range is `*` and seconds.
  String get ytDlpSection =>
      '*${_seconds(start)}-${_seconds(end)}';

  static String _seconds(Duration d) =>
      (d.inMilliseconds / 1000).toStringAsFixed(3);

  static String _label(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h}h${m}m${s}s' : '${d.inMinutes}m${s}s';
  }

  /// `1:05`, or `1:02:03` from an hour on.
  static String formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  /// What someone types for a time: `75`, `1:15`, `1:02:03`, `1:15.5`.
  /// Null when it isn't one.
  static Duration? parseTime(String text) {
    final parts = text.trim().replaceAll(',', '.').split(':');
    if (parts.isEmpty || parts.length > 3 || parts.any((p) => p.isEmpty)) {
      return null;
    }
    final seconds = double.tryParse(parts.last);
    if (seconds == null || seconds < 0) return null;
    var total = seconds;
    for (var i = parts.length - 2, unit = 60; i >= 0; i--, unit *= 60) {
      final v = int.tryParse(parts[i]);
      if (v == null || v < 0) return null;
      total += v * unit;
    }
    // Minutes and seconds past 59 only make sense as the first field.
    if (parts.length > 1 && seconds >= 60) return null;
    return Duration(milliseconds: (total * 1000).round());
  }

  Map<String, int> toJson() =>
      {'start': start.inMilliseconds, 'end': end.inMilliseconds};

  static MediaPart? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = json['start'], end = json['end'];
    if (start is! int || end is! int) return null;
    return MediaPart(
        Duration(milliseconds: start), Duration(milliseconds: end));
  }

  @override
  bool operator ==(Object other) =>
      other is MediaPart && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'MediaPart($start, $end)';
}
