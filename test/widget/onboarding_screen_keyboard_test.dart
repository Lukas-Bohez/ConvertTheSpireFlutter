import 'package:convert_the_spire_reborn/src/screens/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'Onboarding advances with right arrow and goes back with left arrow',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(onFinish: () {}),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.textContaining('Step 1 of'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 2 of'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.textContaining('Step 1 of'), findsOneWidget);
  });
}
