import 'package:convert_the_spire_reborn/src/widgets/global_cursor_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _cursor() => find.byWidgetPredicate((w) =>
    w is CustomPaint && w.painter.runtimeType.toString() == '_CursorPainter');

void main() {
  Widget app({Widget? child}) => MaterialApp(
        home: GlobalCursorOverlay(
          child: Scaffold(body: child ?? const SizedBox.expand()),
        ),
      );

  testWidgets('draws no frames while the cursor is still', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(app());
      await tester.pump();
      // It used to tick for as long as the app was open: a new frame 60
      // times a second with nothing changing.
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);
      expect(_cursor(), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

      // Slows down, stops, and stops asking for frames.
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);

      // The cursor hides after a while.
      await tester.pump(const Duration(seconds: 3));
      expect(_cursor(), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('arrow keys in a text field leave the cursor alone',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = TextEditingController(text: 'abcd');
      await tester.pumpWidget(app(child: TextField(controller: controller)));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 4);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(_cursor(), findsNothing);
      expect(controller.selection.baseOffset, 3);
      await tester.pumpAndSettle();
      controller.dispose();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Enter clicks only where the cursor is seen', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var pageTaps = 0;
      await tester.pumpWidget(app(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => pageTaps++,
        ),
      ));

      // Hidden: Enter used to click wherever the cursor last was.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(pageTaps, 0);
      expect(_cursor(), findsOneWidget, reason: 'Enter shows the cursor');

      // Shown: Enter clicks where it is.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(pageTaps, 1);
      await tester.pump(const Duration(seconds: 3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Enter in a text field does not click the page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var pageTaps = 0;
      await tester.pumpWidget(app(
        child: Column(children: [
          const TextField(),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => pageTaps++,
            ),
          ),
        ]),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(pageTaps, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
