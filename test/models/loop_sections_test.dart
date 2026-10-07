import 'package:convert_the_spire_reborn/src/models/loop_sections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Looping parts of a song or video (issue #41): only the marked parts
/// play, in order, over and over.
void main() {
  Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());
  LoopSection part(num from, num to) => LoopSection(s(from), s(to));

  group('where playback goes', () {
    // The intro and the bit at the end of a song.
    final parts = [part(0, 30), part(190, 220)];

    test('inside a part it carries on', () {
      expect(LoopSectionStore.target(s(0), parts), isNull);
      expect(LoopSectionStore.target(s(29.9), parts), isNull);
      expect(LoopSectionStore.target(s(200), parts), isNull);
    });

    test('after a part it goes to the next, after the last to the first', () {
      expect(LoopSectionStore.target(s(30), parts), s(190));
      expect(LoopSectionStore.target(s(120), parts), s(190));
      expect(LoopSectionStore.target(s(220), parts), s(0));
      expect(LoopSectionStore.target(s(230), parts), s(0));
    });

    test('before the first part it goes to the first', () {
      expect(LoopSectionStore.target(s(5), [part(60, 90)]), s(60));
    });

    test('no parts, no jumps', () {
      expect(LoopSectionStore.target(s(5), const []), isNull);
    });
  });

  group('parts are tidied', () {
    test('in order, overlapping ones joined', () {
      expect(
        LoopSectionStore.normalized([part(100, 120), part(10, 20), part(15, 30)]),
        [part(10, 30), part(100, 120)],
      );
    });

    test('kept within the track, taps dropped', () {
      expect(
        LoopSectionStore.normalized(
          [part(-5, 10), part(50, 50.2), part(170, 400)],
          duration: s(180),
        ),
        [part(0, 10), part(170, 180)],
      );
    });

    test('a part that ends before it starts is dropped', () {
      expect(LoopSectionStore.normalized([part(20, 10)]), isEmpty);
    });
  });

  test('parts are kept across restarts, per file', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LoopSectionStore(prefs);
    await store.save('/music/song.mp3',
        LoopSettings(on: true, sections: [part(190, 220), part(0, 30)]));
    await store.save('/music/other.mp3',
        LoopSettings(on: false, sections: [part(5, 10)]));

    final again = LoopSectionStore(prefs);
    final song = again.settingsFor('/music/song.mp3');
    expect(song.on, isTrue);
    expect(song.looping, isTrue);
    expect(song.sections, [part(0, 30), part(190, 220)]);
    expect(again.settingsFor('/music/other.mp3').looping, isFalse);
    expect(again.settingsFor('/music/none.mp3').sections, isEmpty);

    // A file with no parts left is forgotten.
    await again.save(
        '/music/other.mp3', const LoopSettings(on: true, sections: []));
    expect(LoopSectionStore(prefs).settingsFor('/music/other.mp3').sections,
        isEmpty);

    await again.rename('/music/song.mp3', '/music/renamed.mp3');
    expect(LoopSectionStore(prefs).settingsFor('/music/renamed.mp3').looping,
        isTrue);
  });

  test('unreadable saved parts are ignored', () async {
    SharedPreferences.setMockInitialValues(
        {LoopSectionStore.prefsKey: '{"x": nonsense'});
    final store = LoopSectionStore(await SharedPreferences.getInstance());
    expect(store.settingsFor('x').sections, isEmpty);
  });
}
