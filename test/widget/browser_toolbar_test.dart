import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convert_the_spire_reborn/src/screens/browser/browser_toolbar.dart';

void main() {
  testWidgets(
      'BrowserToolbar shows download and favourite buttons when enabled',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: BrowserToolbar(
          isLoading: false,
          isSecure: true,
          isIncognito: false,
          canGoBack: false,
          canGoForward: false,
          hasVideos: true,
          castBadgeAnimation: AnimationController(
              vsync: TestVSync(), duration: const Duration(milliseconds: 1)),
          desktopMode: false,
          adBlockEnabled: false,
          pageTitle: 'Example',
          currentUrl: 'https://example.com',
          onBack: () {},
          onForward: () {},
          onReload: () {},
          onCastTap: () {},
          onDownload: () {},
          downloadEnabled: true,
          isKnownDifficultSite: false,
          onMenuAction: (_) {},
          onTabs: () {},
          tabCount: 1,
          isFavourited: true,
          onFavouriteTap: () {},
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Expect download icon present
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    // Expect star icon (filled) present
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}
