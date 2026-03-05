import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/src/screens/browser_screen.dart';
import 'package:my_flutter_app/src/screens/onboarding_screen.dart';

void main() {
  testWidgets('Basic widget tree builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Smoke Test')),
        ),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Smoke Test'), findsOneWidget);
  });

  testWidgets('Browser tab can be created', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BrowserScreen(onAddToQueue: (_) {}))),
    );

    await tester.pump(const Duration(seconds: 15));

    // BrowserScreen should render without crashing, regardless of platform.
    // On Linux CI, webview is unsupported so no TextField appears.
    expect(find.byType(BrowserScreen), findsOneWidget);
  });

  testWidgets('Onboarding screen renders and supports navigation',
      (WidgetTester tester) async {
    // Use a larger surface so the onboarding layout doesn't overflow
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinish: () {},
          themeMode: ThemeMode.dark,
          onThemeChanged: (_) {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    // The screen should render without errors
    expect(find.byType(OnboardingScreen), findsOneWidget);

    // Search text should be present on the first page
    expect(find.text('Search'), findsWidgets);
  });
}
