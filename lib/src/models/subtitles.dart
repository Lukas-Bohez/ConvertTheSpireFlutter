import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// One subtitle: its text shows from [start] until [end].
@immutable
class SubtitleCue {
  const SubtitleCue(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SubtitleCue &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'SubtitleCue($start, $end, $text)';
}

/// Subtitles from an SRT or WebVTT file, for videos and for songs alike
/// (issue #41), and synced lyrics from an LRC file.
class Subtitles {
  Subtitles(List<SubtitleCue> cues)
      : cues = List.unmodifiable(
            [...cues]..sort((a, b) => a.start.compareTo(b.start)));

  final List<SubtitleCue> cues;

  static const extensions = {'.srt', '.vtt', '.lrc'};

  /// The text showing at [position], or null between subtitles.
  String? textAt(Duration position) {
    // The last cue starting at or before the position...
    var lo = 0, hi = cues.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].start <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // ...and the ones before it that still show (overlapping cues).
    final lines = <String>[];
    for (var i = found; i >= 0 && i > found - 4; i--) {
      final cue = cues[i];
      if (position < cue.end) lines.insert(0, cue.text);
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Reads a subtitle or lyrics file.
  static Future<Subtitles> load(String path) async {
    final text = decode(await File(path).readAsBytes());
    return p.extension(path).toLowerCase() == '.lrc'
        ? parseLrc(text)
        : parse(text);
  }

  /// The text of a subtitle file, whatever it was saved as. Subtitles made
  /// on Windows are often UTF-16 (read as anything else, not one line was
  /// found: issue #41's Die Hard), older ones Windows-1252, which is read as
  /// Latin-1: its letters right but for a few punctuation marks.
  @visibleForTesting
  static String decode(List<int> bytes) {
    bool starts(List<int> mark) =>
        bytes.length >= mark.length &&
        Iterable.generate(mark.length).every((i) => bytes[i] == mark[i]);
    if (starts(const [0xEF, 0xBB, 0xBF])) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    if (starts(const [0xFF, 0xFE])) return _utf16(bytes.sublist(2), little: true);
    if (starts(const [0xFE, 0xFF])) return _utf16(bytes.sublist(2), little: false);
    // UTF-16 without a mark: in text that is mostly ASCII, every other byte
    // is a zero.
    final sample = bytes.length < 400 ? bytes.length : 400;
    if (sample >= 4) {
      var zerosOdd = 0, zerosEven = 0;
      for (var i = 0; i < sample; i++) {
        if (bytes[i] == 0) i.isOdd ? zerosOdd++ : zerosEven++;
      }
      if (zerosOdd > sample / 4) return _utf16(bytes, little: true);
      if (zerosEven > sample / 4) return _utf16(bytes, little: false);
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String _utf16(List<int> bytes, {required bool little}) {
    final units = <int>[
      for (var i = 0; i + 1 < bytes.length; i += 2)
        little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
    ];
    return String.fromCharCodes(units);
  }

  /// SRT and WebVTT: blocks of a time line `00:01:02,500 --> 00:01:04,000`
  /// (or with a dot) and the text under it, separated by blank lines.
  static Subtitles parse(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = const LineSplitter().convert(text);
    final cues = <SubtitleCue>[];
    var i = 0;
    while (i < lines.length) {
      final times = _timeLine.firstMatch(lines[i]);
      if (times == null) {
        i++;
        continue;
      }
      final start = _time(times.group(1)!);
      final end = _time(times.group(2)!);
      i++;
      final body = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        // A time line straight after another, without a blank line.
        if (_timeLine.hasMatch(lines[i])) break;
        body.add(lines[i]);
        i++;
      }
      final cueText = _clean(body.join('\n'));
      if (start != null && end != null && end > start && cueText.isNotEmpty) {
        cues.add(SubtitleCue(start, end, cueText));
      }
    }
    return Subtitles(cues);
  }

  /// LRC lyrics: one or more `[01:02.50]` in front of each line, which
  /// shows until the next one starts. `[offset:+250]` shows them all that
  /// many milliseconds earlier; word timings (`<01:02.80>`) and tags such
  /// as `[ar:Artist]` are left out.
  static Subtitles parseLrc(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final offsetMs =
        int.tryParse(_lrcOffset.firstMatch(text)?.group(1) ?? '') ?? 0;
    final timed = <(Duration, String)>[];
    for (final line in const LineSplitter().convert(text)) {
      var rest = line.trim();
      final times = <Duration>[];
      for (var m = _lrcTime.matchAsPrefix(rest);
          m != null;
          m = _lrcTime.matchAsPrefix(rest)) {
        final fraction = (m.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        final at = Duration(
              minutes: int.parse(m.group(1)!),
              seconds: int.parse(m.group(2)!),
              milliseconds: int.parse(fraction),
            ) -
            Duration(milliseconds: offsetMs);
        times.add(at < Duration.zero ? Duration.zero : at);
        rest = rest.substring(m.end).trimLeft();
      }
      final words = _clean(rest);
      for (final at in times) {
        timed.add((at, words));
      }
    }
    timed.sort((a, b) => a.$1.compareTo(b.$1));
    final cues = <SubtitleCue>[];
    for (var i = 0; i < timed.length; i++) {
      final (start, words) = timed[i];
      // A time with no words only ends the line before it.
      if (words.isEmpty) continue;
      var end = start + _lastLyricLine;
      for (var j = i + 1; j < timed.length; j++) {
        if (timed[j].$1 > start) {
          end = timed[j].$1;
          break;
        }
      }
      cues.add(SubtitleCue(start, end, words));
    }
    return Subtitles(cues);
  }

  /// How long the last line of lyrics shows, with no line after it.
  static const _lastLyricLine = Duration(seconds: 8);
  static final _lrcTime = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _lrcOffset = RegExp(r'^\s*\[offset:\s*([+-]?\d+)\s*\]',
      caseSensitive: false, multiLine: true);

  static final _timeLine = RegExp(
      r'((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})');

  static Duration? _time(String s) {
    final parts = s.replaceAll(',', '.').split(':');
    try {
      final secParts = parts.last.split('.');
      final seconds = int.parse(secParts[0]);
      final fraction = secParts.length > 1 ? secParts[1].padRight(3, '0') : '0';
      final ms = int.parse(fraction.substring(0, 3));
      final minutes = int.parse(parts[parts.length - 2]);
      final hours = parts.length > 2 ? int.parse(parts[parts.length - 3]) : 0;
      return Duration(
          hours: hours, minutes: minutes, seconds: seconds, milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  static final _tags = RegExp(r'<[^>]*>|\{\\[^}]*\}');

  /// Without formatting tags (`<i>`, `<font ...>`, `{\an8}`) and the
  /// entities WebVTT uses.
  static String _clean(String text) => text
      .replaceAll(_tags, '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .trim();

  /// Subtitle files that belong to [mediaPath], best first: next to it with
  /// the same name (`Film.srt`, `Film.en.srt`), then in a `Subs` or
  /// `Subtitles` folder next to it, where torrents put them, preferring
  /// English ones there.
  static Future<List<String>> findFor(String mediaPath) async {
    if (mediaPath.startsWith('content://') || mediaPath.startsWith('http')) {
      return const [];
    }
    final dir = Directory(p.dirname(mediaPath));
    final base = p.basenameWithoutExtension(mediaPath).toLowerCase();
    final sameName = <String>[];
    final inSubsFolder = <String>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        final lower = name.toLowerCase();
        if (entity is File) {
          if (!extensions.contains(p.extension(lower))) continue;
          final stem = p.basenameWithoutExtension(lower);
          if (stem == base || stem.startsWith('$base.')) {
            sameName.add(entity.path);
          }
        } else if (entity is Directory &&
            (lower == 'subs' || lower == 'subtitles' || lower == 'sub')) {
          await for (final sub in entity.list(recursive: true)) {
            if (sub is File &&
                extensions.contains(p.extension(sub.path).toLowerCase())) {
              inSubsFolder.add(sub.path);
            }
          }
        }
      }
    } catch (_) {
      return const [];
    }
    int rank(String path) {
      final lower = p.basename(path).toLowerCase();
      if (lower.contains('english') ||
          RegExp(r'[._ -]en[g]?[._ -]').hasMatch(lower)) {
        return 0;
      }
      return 1;
    }

    sameName.sort((a, b) {
      // Film.srt before Film.en.srt before the rest.
      final aExact = p.basenameWithoutExtension(a).toLowerCase() == base;
      final bExact = p.basenameWithoutExtension(b).toLowerCase() == base;
      if (aExact != bExact) return aExact ? -1 : 1;
      return rank(a).compareTo(rank(b));
    });
    // In a folder of a single film's subtitles any file goes; in a folder
    // with a folder per episode, only the one named after this file.
    final forThis = inSubsFolder
        .where((s) => p.split(s).any((part) => part.toLowerCase() == base))
        .toList();
    final folder = forThis.isNotEmpty ? forThis : inSubsFolder;
    folder.sort((a, b) => rank(a).compareTo(rank(b)));
    return [...sameName, ...folder];
  }
}
