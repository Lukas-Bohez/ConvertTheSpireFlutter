import 'package:convert_the_spire_reborn/src/utils/l10n.dart';
import 'package:convert_the_spire_reborn/src/widgets/track_lists_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Playlists page header: its two tabs and the Track lists menu share one
/// row. On a phone, in every language and with large system text, nothing in
/// it may overflow.
void main() {
  Future<void> pumpHeader(WidgetTester tester, Size size, Locale locale,
      {VoidCallback? onImport, VoidCallback? onExport}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: const TextScaler.linear(1.3)),
        child: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TabBar(tabs: [
                          Tab(text: context.l10n.playlistManager),
                          Tab(text: context.l10n.watchedPlaylists),
                        ]),
                      ),
                      TrackListsMenu(
                        onImport: onImport ?? () {},
                        onExport: onExport ?? () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final locale in AppLocalizations.supportedLocales) {
    for (final width in [320.0, 360.0, 1280.0]) {
      testWidgets('fits at ${width.toInt()}px in ${locale.languageCode}',
          (tester) async {
        await pumpHeader(tester, Size(width, 740), locale);
        expect(tester.takeException(), isNull);

        // The menu itself, open, fits too.
        await tester.tap(find.byType(TrackListsMenu));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.upload_file), findsOneWidget);
        expect(find.byIcon(Icons.download), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a phone shows only the icon, a wide window its name too',
      (tester) async {
    const english = Locale('en');
    await pumpHeader(tester, const Size(360, 740), english);
    expect(find.text('Track lists'), findsNothing);
    expect(find.byIcon(Icons.import_export), findsOneWidget);

    await pumpHeader(tester, const Size(1280, 800), english);
    expect(find.text('Track lists'), findsOneWidget);
  });

  testWidgets('each menu item does what it says', (tester) async {
    var imports = 0;
    var exports = 0;
    await pumpHeader(tester, const Size(360, 740), const Locale('en'),
        onImport: () => imports++, onExport: () => exports++);

    await tester.tap(find.byType(TrackListsMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import track lists'));
    await tester.pumpAndSettle();
    expect((imports, exports), (1, 0));

    await tester.tap(find.byType(TrackListsMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export track lists'));
    await tester.pumpAndSettle();
    expect((imports, exports), (1, 1));
  });
}
