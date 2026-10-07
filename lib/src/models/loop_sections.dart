import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A part of a song or video that plays over and over (issue #41): to hear
/// just the best bit of a song, or two bits of it.
@immutable
class LoopSection {
  const LoopSection(this.start, this.end);

  final Duration start;
  final Duration end;

  Duration get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is LoopSection && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'LoopSection($start, $end)';
}

/// The parts to loop of one file, and whether they loop now.
@immutable
class LoopSettings {
  const LoopSettings({required this.on, required this.sections});

  final bool on;
  final List<LoopSection> sections;

  bool get looping => on && sections.isNotEmpty;
}

/// The looped parts of every file, kept across restarts, and where playback
/// goes to stay in them.
class LoopSectionStore {
  LoopSectionStore(this._prefs) {
    _load();
  }

  static const prefsKey = 'player_loop_sections';

  /// Parts shorter than this are taps, not parts.
  static const minLength = Duration(milliseconds: 500);

  final SharedPreferences _prefs;
  final Map<String, LoopSettings> _byPath = {};

  LoopSettings settingsFor(String path) =>
      _byPath[path] ?? const LoopSettings(on: false, sections: []);

  Future<void> save(String path, LoopSettings settings) async {
    if (settings.sections.isEmpty) {
      _byPath.remove(path);
    } else {
      _byPath[path] = LoopSettings(
          on: settings.on, sections: normalized(settings.sections));
    }
    await _prefs.setString(prefsKey, jsonEncode(_toJson()));
  }

  /// A file moved or renamed keeps its parts.
  Future<void> rename(String from, String to) async {
    final settings = _byPath.remove(from);
    if (settings == null) return;
    await save(to, settings);
  }

  void _load() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in json.entries) {
        final value = entry.value as Map<String, dynamic>;
        final sections = [
          for (final s in value['parts'] as List)
            LoopSection(Duration(milliseconds: (s as List)[0] as int),
                Duration(milliseconds: s[1] as int)),
        ];
        if (sections.isEmpty) continue;
        _byPath[entry.key] = LoopSettings(
            on: value['on'] == true, sections: normalized(sections));
      }
    } catch (e) {
      debugPrint('LoopSectionStore: unreadable saved parts: $e');
    }
  }

  Map<String, Object> _toJson() => {
        for (final entry in _byPath.entries)
          entry.key: {
            'on': entry.value.on,
            'parts': [
              for (final s in entry.value.sections)
                [s.start.inMilliseconds, s.end.inMilliseconds],
            ],
          },
      };

  /// [sections] in order, overlapping ones joined, ones too short dropped,
  /// and within [duration] when it is known.
  static List<LoopSection> normalized(Iterable<LoopSection> sections,
      {Duration? duration}) {
    final sorted = [
      for (final s in sections)
        if (_clamp(s, duration) case final c? when c.length >= minLength) c,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final out = <LoopSection>[];
    for (final s in sorted) {
      if (out.isNotEmpty && s.start <= out.last.end) {
        final last = out.removeLast();
        out.add(LoopSection(last.start, s.end > last.end ? s.end : last.end));
      } else {
        out.add(s);
      }
    }
    return out;
  }

  static LoopSection? _clamp(LoopSection s, Duration? duration) {
    final start = s.start < Duration.zero ? Duration.zero : s.start;
    var end = s.end;
    if (duration != null && duration > Duration.zero && end > duration) {
      end = duration;
    }
    if (end <= start) return null;
    return LoopSection(start, end);
  }

  /// Where playback at [position] goes to stay in [sections] (in order, as
  /// [normalized] leaves them), or null to carry on. Past the end of a part
  /// it goes to the start of the next, and after the last back to the
  /// first.
  static Duration? target(Duration position, List<LoopSection> sections) {
    if (sections.isEmpty) return null;
    for (final s in sections) {
      if (position >= s.start && position < s.end) return null;
    }
    for (final s in sections) {
      if (s.start > position) return s.start;
    }
    return sections.first.start;
  }
}
