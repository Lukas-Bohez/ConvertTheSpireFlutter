import 'package:convert_the_spire_reborn/main.dart' as app;
import 'package:convert_the_spire_reborn/src/screens/home_screen.dart';
import 'package:convert_the_spire_reborn/src/screens/onboarding_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Starts the real app, the way a user does, and requires it to get past the
/// startup spinner.
///
/// 14.4.0 shipped stuck on that spinner on every platform: the MaterialApp
/// shown while loading was replaced by a new one once the app was ready, and
/// the shared navigator key carried the old home route - the spinner - into
/// it. Every unit and widget test passed, because none of them started the
/// app itself. This one does.
///
///   flutter test -d windows integration_test/app_startup_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app reaches its first real screen', (tester) async {
    // main() installs the app's own error screen and error handlers. The test
    // harness checks they are back before the body returns - before any
    // tearDown runs - so they are put back here.
    final errorWidgetBuilder = ErrorWidget.builder;
    final onFlutterError = FlutterError.onError;
    try {
      await app.main();

      final firstScreen = find
          .byWidgetPredicate((w) => w is HomeScreen || w is OnboardingScreen);
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (
          firstScreen.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(firstScreen, findsOneWidget,
          reason: 'the app must not stay on the startup spinner');
    } finally {
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = onFlutterError;
    }
  });
}
