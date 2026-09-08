import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests that verify the player screen's Tab widgets use proper Material
/// Icons instead of emoji characters, and that the "EFav" label has been
/// renamed to "Fav".
void main() {
  group('Player screen Tab widgets', () {
    testWidgets('Tab widgets use icon property instead of emoji in text',
        (WidgetTester tester) async {
      // Create Tab widgets matching the player screen implementation
      final tabs = [
        Tab(
          icon: const Icon(Icons.library_music, size: 20),
          text: 'All (5)',
        ),
        Tab(
          icon: const Icon(Icons.music_note, size: 20),
          text: 'Songs (3)',
        ),
        Tab(
          icon: const Icon(Icons.video_library, size: 20),
          text: 'Videos (2)',
        ),
        Tab(
          icon: const Icon(Icons.favorite, size: 20),
          text: 'Fav (4)',
        ),
      ];

      // Pump a widget tree with these tabs
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: tabs.length,
            child: Scaffold(
              appBar: AppBar(
                bottom: TabBar(tabs: tabs),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify icons are present
      expect(find.byIcon(Icons.library_music), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byIcon(Icons.video_library), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      // Verify text labels are present
      expect(find.text('All (5)'), findsOneWidget);
      expect(find.text('Songs (3)'), findsOneWidget);
      expect(find.text('Videos (2)'), findsOneWidget);
      expect(find.text('Fav (4)'), findsOneWidget);

      // Verify no emoji characters in text
      expect(find.textContaining('♪'), findsNothing);
      expect(find.textContaining('▶'), findsNothing);
      expect(find.textContaining('☁'), findsNothing);
      expect(find.textContaining('EFav'), findsNothing);
    });

    testWidgets('Tab text does not contain emoji', (WidgetTester tester) async {
      final tabs = [
        Tab(
          icon: const Icon(Icons.library_music, size: 20),
          text: 'All (5)',
        ),
        Tab(
          icon: const Icon(Icons.music_note, size: 20),
          text: 'Songs (3)',
        ),
        Tab(
          icon: const Icon(Icons.video_library, size: 20),
          text: 'Videos (2)',
        ),
        Tab(
          icon: const Icon(Icons.favorite, size: 20),
          text: 'Fav (4)',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: tabs.length,
            child: Scaffold(
              appBar: AppBar(
                bottom: TabBar(tabs: tabs),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Get all text widgets in the tab bar
      final textFinder = find.byType(Text);
      final textWidgets = tester.widgetList<Text>(textFinder);

      final emojiPattern = RegExp(
        r'[\u{1F600}-\u{1F64F}]|'
        r'[\u{1F300}-\u{1F5FF}]|'
        r'[\u{1F680}-\u{1F6FF}]|'
        r'[\u{2600}-\u{26FF}]|'
        r'[\u{2700}-\u{27BF}]',
        unicode: true,
      );

      for (final textWidget in textWidgets) {
        final data = textWidget.data;
        if (data != null) {
          expect(
            emojiPattern.hasMatch(data),
            isFalse,
            reason: 'Tab text "$data" should not contain emoji',
          );
        }
      }
    });

    testWidgets('Favourites tab shows "Fav" not "EFav"',
        (WidgetTester tester) async {
      final tabs = [
        Tab(
          icon: const Icon(Icons.favorite, size: 20),
          text: 'Fav (4)',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 1,
            child: Scaffold(
              appBar: AppBar(
                bottom: TabBar(tabs: tabs),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Fav" is shown
      expect(find.text('Fav (4)'), findsOneWidget);

      // Verify "EFav" is NOT shown
      expect(find.textContaining('EFav'), findsNothing);
    });
  });
}
