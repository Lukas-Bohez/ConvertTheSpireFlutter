import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/src/screens/browser_screen.dart';
import 'package:my_flutter_app/src/state/app_controller.dart';

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
}