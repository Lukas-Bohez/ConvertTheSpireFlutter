import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/src/screens/browser_screen.dart';
import 'package:my_flutter_app/src/screens/onboarding_screen.dart';
import 'package:my_flutter_app/src/state/app_controller.dart';
import 'package:my_flutter_app/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Add more tests as needed to cover other widgets and functionalities

  testWidgets('Browser tab can be created', (WidgetTester tester) async {
    // supply a dummy callback; the test doesn't exercise downloading
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BrowserScreen(onAddToQueue: (_) {}))),
    );

    // pump long enough that the Windows initialization timeout (15s)
    // fires, avoiding a lingering pending Timer in the test harness.
    await tester.pump(const Duration(seconds: 15));

    // toolbar always contains a TextField for the URL, even if the
    // webview itself is still initializing or unsupported.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('Onboarding screen shows previews, supports theme toggle', (WidgetTester tester) async {
    ThemeMode? changed;

    // instantiate with a known starting mode and capture any changes
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinish: () {},
          themeMode: ThemeMode.dark,
          onThemeChanged: (m) => changed = m,
        ),
      ),
    );

    // let all entrance animations finish
    await tester.pumpAndSettle();

    // theme toggle should reflect dark mode initially
    expect(find.byTooltip('Theme: Dark — tap to cycle'), findsOneWidget);

    // exercising previews as before
    expect(find.text('Search'), findsWidgets);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('onboarding_preview_queue')), findsOneWidget);

    // tapping the toggle should notify the callback with the next mode
    await tester.tap(find.byTooltip('Theme: Dark — tap to cycle'));
    await tester.pumpAndSettle();
    expect(changed, ThemeMode.system);
  });



}