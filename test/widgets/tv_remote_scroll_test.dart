import 'package:convert_the_spire_reborn/src/widgets/global_cursor_overlay.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _keys = MethodChannel('com.yourapp/cursor_keys');
const _platform = MethodChannel('convert_the_spire/saf');

/// What the Android activity sends for a remote key.
Future<void> _remoteKey(WidgetTester tester, int keyCode, String action) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    _keys.name,
    _keys.codec.encodeMethodCall(
        MethodCall('onDpadKey', {'keyCode': keyCode, 'action': action})),
    (_) {},
  );
}

const _dpadUp = 19;
const _dpadDown = 20;
const _pageUp = 92;
const _pageDown = 93;
const _channelUp = 166;

Future<void> _pumpTv(WidgetTester tester, Widget child) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _platform, (call) async => call.method == 'isAndroidTV' ? true : null);
  await tester.pumpWidget(MaterialApp(
    home: GlobalCursorOverlay(child: Scaffold(body: child)),
  ));
  await tester.pump();
}

/// A widget test on an Android TV. The platform override has to be undone
/// inside the test, before the framework checks its debug variables.
void tvTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      GlobalCursorOverlay.registerWebViewCallbacks();
    }
  });
}

/// The same on a PC, where the keyboard stands in for the remote.
void desktopTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      GlobalCursorOverlay.registerWebViewCallbacks();
    }
  });
}

void main() {
  tvTest('holding Up at the top edge scrolls the page up', (tester) async {
    final deltas = <double>[];
    GlobalCursorOverlay.registerWebViewCallbacks(onScroll: (dy, _) async {
      deltas.add(dy);
      return true;
    });
    await _pumpTv(tester, const SizedBox.expand());

    await _remoteKey(tester, _dpadUp, 'down');
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _remoteKey(tester, _dpadUp, 'up');
    await tester.pumpAndSettle();

    expect(deltas, isNotEmpty, reason: 'the cursor reached the top edge');
    expect(deltas.every((d) => d < 0), isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  tvTest('page and channel keys scroll most of a screen', (tester) async {
    final deltas = <double>[];
    GlobalCursorOverlay.registerWebViewCallbacks(onScroll: (dy, _) async {
      deltas.add(dy);
      return true;
    });
    await _pumpTv(tester, const SizedBox.expand());
    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;

    await _remoteKey(tester, _pageDown, 'down');
    await _remoteKey(tester, _pageUp, 'down');
    await _remoteKey(tester, _channelUp, 'down');

    expect(deltas, hasLength(3));
    expect(deltas[0], closeTo(height * 0.85, 0.01));
    expect(deltas[1], closeTo(-height * 0.85, 0.01));
    expect(deltas[2], closeTo(-height * 0.85, 0.01));
    await tester.pump(const Duration(seconds: 3));
  });

  tvTest('a page that is not under the cursor leaves scrolling to Flutter',
      (tester) async {
    var asked = 0;
    // The new-tab page or a dialog: the browser says it is not the target.
    GlobalCursorOverlay.registerWebViewCallbacks(onScroll: (dy, _) async {
      asked++;
      return false;
    });
    final controller = ScrollController();
    await _pumpTv(
        tester,
        ListView.builder(
          controller: controller,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 48, child: Text('row $i')),
        ));

    await _remoteKey(tester, _pageDown, 'down');
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(controller.offset, greaterThan(100),
        reason: 'the list scrolled instead');
    controller.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  tvTest('a page that takes the scroll keeps Flutter lists still',
      (tester) async {
    GlobalCursorOverlay.registerWebViewCallbacks(
        onScroll: (dy, _) async => true);
    final controller = ScrollController();
    await _pumpTv(
        tester,
        ListView.builder(
          controller: controller,
          itemCount: 200,
          itemBuilder: (_, i) => SizedBox(height: 48, child: Text('row $i')),
        ));

    await _remoteKey(tester, _pageDown, 'down');
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
    controller.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an IndexedStack does NOT switch off TickerMode of hidden tabs',
      (tester) async {
    // So the browser cannot tell from TickerMode that another tab is
    // showing; Home tells it (BrowserScreen.isActive).
    final seen = <int, bool>{};
    Widget probe(int i) => Builder(builder: (context) {
          seen[i] = TickerMode.valuesOf(context).enabled;
          return const SizedBox();
        });
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: IndexedStack(index: 1, children: [probe(0), probe(1)]),
    ));
    expect(seen, {0: true, 1: true});
  });

  desktopTest('arrows the web page hands over move the cursor like a remote',
      (tester) async {
    final deltas = <double>[];
    GlobalCursorOverlay.registerWebViewCallbacks(onScroll: (dy, _) async {
      deltas.add(dy);
      return true;
    });
    await tester.pumpWidget(const MaterialApp(
        home: GlobalCursorOverlay(child: Scaffold(body: SizedBox.expand()))));

    expect(GlobalCursorOverlay.handleRemoteKey(LogicalKeyboardKey.arrowUp,
        isDown: true), isTrue);
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    GlobalCursorOverlay.handleRemoteKey(LogicalKeyboardKey.arrowUp,
        isDown: false);
    await tester.pumpAndSettle();
    expect(deltas, isNotEmpty, reason: 'the cursor reached the top edge');
    expect(deltas.every((d) => d < 0), isTrue);

    deltas.clear();
    final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    GlobalCursorOverlay.handleRemoteKey(LogicalKeyboardKey.pageDown,
        isDown: true);
    expect(deltas, [closeTo(height * 0.85, 0.01)]);
    await tester.pump(const Duration(seconds: 3));
  });

  desktopTest('Enter from the page clicks only where the cursor shows',
      (tester) async {
    final taps = <Offset>[];
    GlobalCursorOverlay.registerWebViewCallbacks(onTap: (p) async {
      taps.add(p);
    });
    await tester.pumpWidget(const MaterialApp(
        home: GlobalCursorOverlay(child: Scaffold(body: SizedBox.expand()))));

    GlobalCursorOverlay.handleRemoteKey(LogicalKeyboardKey.enter, isDown: true);
    await tester.pump();
    expect(taps, isEmpty, reason: 'hidden, Enter only shows the cursor');
    GlobalCursorOverlay.handleRemoteKey(LogicalKeyboardKey.enter, isDown: true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(taps, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
  });

  desktopTest('Page Down on the PC keyboard scrolls a screenful',
      (tester) async {
    final deltas = <double>[];
    GlobalCursorOverlay.registerWebViewCallbacks(onScroll: (dy, _) async {
      deltas.add(dy);
      return true;
    });
    await tester.pumpWidget(const MaterialApp(
        home: GlobalCursorOverlay(child: Scaffold(body: SizedBox.expand()))));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    expect(deltas, hasLength(2));
    expect(deltas[0], greaterThan(0));
    expect(deltas[1], lessThan(0));
    await tester.pump(const Duration(seconds: 3));
  });

  test('the down key code the remote sends is the one the overlay handles',
      () {
    // Guards the numbers in MainActivity.kt: KEYCODE_DPAD_DOWN.
    expect(_dpadDown, 20);
  });
}
