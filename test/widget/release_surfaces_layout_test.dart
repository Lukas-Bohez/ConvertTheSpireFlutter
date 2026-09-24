import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/whats_new_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/app_error_screen.dart';
import 'package:convert_the_spire_reborn/src/widgets/whats_new_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every surface new in this release, laid out on a phone and on a desktop
/// with 130% system text. An overflow anywhere fails the test.
///
/// People with larger text are exactly the ones who notice clipped text first,
/// and the browser toolbar shipped with that bug at every width until a test
/// like this one caught it.
void main() {
  const sizes = [Size(360, 740), Size(1280, 800)];

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: const TextScaler.linear(1.3)),
        child: child,
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final size in sizes) {
    final label = '${size.width.toInt()}px';

    testWidgets('What\u2019s new, with this release\u2019s notes, at $label',
        (tester) async {
      final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(File('pubspec.yaml').readAsStringSync())!
          .group(1)!;
      final entry = WhatsNewService.entryFor(
          File('CHANGELOG.md').readAsStringSync(), version)!;

      await pumpAt(tester, size, Scaffold(body: WhatsNewDialog(entry: entry)));

      expect(find.text('Got it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the error screen at $label', (tester) async {
      final details = FlutterErrorDetails(
        exception: StateError(
            'A long error message that goes on for a while, the way real '
            'ones do, with a path like C:\\Users\\someone\\AppData\\Local'),
        stack: StackTrace.current,
      );

      await pumpAt(tester, size, AppErrorScreen(details: details));

      expect(find.text('Copy details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
