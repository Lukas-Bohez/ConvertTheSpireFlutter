import 'package:convert_the_spire_reborn/src/widgets/quick_download_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Quick Download card on small phones with 130% text. The quality
/// dropdown used to overflow its half-width slot.
void main() {
  for (final width in const [320.0, 360.0, 1280.0]) {
    testWidgets('fits at ${width.toInt()}px', (tester) async {
      final size = Size(width, 740);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: const TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: QuickDownloadCard(onDownload: (_, __, ___) async {}),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Download'), findsOneWidget);
    });
  }
}
