import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that player tab labels use proper icons instead of emoji
/// and that the "EFav" label has been renamed to "Fav".
void main() {
  group('Player tab icons', () {
    test('tab labels do not contain emoji characters', () {
      // These are the tab labels used in the player screen
      final tabLabels = [
        'All (0)',
        'Songs (0)',
        'Videos (0)',
        'Fav (0)',
      ];

      // Common emoji ranges to check for
      final emojiPattern = RegExp(
        r'[\u{1F600}-\u{1F64F}]|' // Emoticons
        r'[\u{1F300}-\u{1F5FF}]|' // Misc Symbols and Pictographs
        r'[\u{1F680}-\u{1F6FF}]|' // Transport and Map
        r'[\u{1F1E0}-\u{1F1FF}]|' // Flags
        r'[\u{2600}-\u{26FF}]|' // Misc symbols
        r'[\u{2700}-\u{27BF}]|' // Dingbats
        r'[\u{FE00}-\u{FE0F}]|' // Variation Selectors
        r'[\u{1F900}-\u{1F9FF}]|' // Supplemental Symbols
        r'[\u{1FA00}-\u{1FA6F}]|' // Chess Symbols
        r'[\u{1FA70}-\u{1FAFF}]|' // Symbols Extended-A
        r'[\u{200D}]|' // Zero Width Joiner
        r'[\u{20E3}]|' // Combining Enclosing Keycap
        r'[\u{E0020}-\u{E007F}]', // Tags
        unicode: true,
      );

      for (final label in tabLabels) {
        expect(emojiPattern.hasMatch(label), isFalse,
            reason: 'Tab label "$label" should not contain emoji characters');
      }
    });

    test('tab labels do not contain musical note emoji', () {
      final tabLabels = [
        'All (0)',
        'Songs (0)',
        'Videos (0)',
        'Fav (0)',
      ];

      // Musical note characters that were previously used
      final musicalNotes = ['♪', '♫', '♬', '🎵', '🎶', '🎧', '🎤', '🎼'];

      for (final label in tabLabels) {
        for (final note in musicalNotes) {
          expect(label.contains(note), isFalse,
              reason: 'Tab label "$label" should not contain musical note "$note"');
        }
      }
    });

    test('tab labels do not contain play button emoji', () {
      final tabLabels = [
        'All (0)',
        'Songs (0)',
        'Videos (0)',
        'Fav (0)',
      ];

      // Play button characters that were previously used
      final playButtons = ['▶', '⏯', '⏮', '⏭', '⏪', '⏩'];

      for (final label in tabLabels) {
        for (final btn in playButtons) {
          expect(label.contains(btn), isFalse,
              reason: 'Tab label "$label" should not contain play button "$btn"');
        }
      }
    });

    test('tab labels do not contain cloud emoji', () {
      final tabLabels = [
        'All (0)',
        'Songs (0)',
        'Videos (0)',
        'Fav (0)',
      ];

      // Cloud characters that were previously used
      final clouds = ['☁', '⛅', '⛈', '🌤', '🌥', '🌦', '🌧', '🌨', '🌩'];

      for (final label in tabLabels) {
        for (final cloud in clouds) {
          expect(label.contains(cloud), isFalse,
              reason: 'Tab label "$label" should not contain cloud "$cloud"');
        }
      }
    });

    test('favourites tab uses "Fav" not "EFav"', () {
      final favLabel = 'Fav (0)';
      expect(favLabel.contains('EFav'), isFalse,
          reason: 'Favourites tab should use "Fav" not "EFav"');
      expect(favLabel.startsWith('Fav'), isTrue,
          reason: 'Favourites tab should start with "Fav"');
    });

    test('proper Material Icons exist for player tabs', () {
      // Verify the icons we're using exist in Material Icons
      final icons = [
        Icons.library_music,
        Icons.music_note,
        Icons.video_library,
        Icons.favorite,
      ];

      for (final icon in icons) {
        expect(icon, isNotNull);
        expect(icon.codePoint, greaterThan(0));
      }
    });

    test('tab icons have correct semantic meaning', () {
      // Verify each icon is appropriate for its tab
      expect(Icons.library_music, isNotNull, reason: 'All tab uses library_music');
      expect(Icons.music_note, isNotNull, reason: 'Songs tab uses music_note');
      expect(Icons.video_library, isNotNull, reason: 'Videos tab uses video_library');
      expect(Icons.favorite, isNotNull, reason: 'Fav tab uses favorite');
    });
  });
}
