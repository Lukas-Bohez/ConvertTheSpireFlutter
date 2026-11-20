import 'package:convert_the_spire_reborn/src/browser/js/scroll_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds up steps below a pixel instead of dropping them', () async {
    final scripts = <String>[];
    final scroller = WebViewScroller((s) async => scripts.add(s));

    // 6.67 px a frame, the cursor's edge scroll, scrolling up.
    for (var i = 0; i < 3; i++) {
      await scroller.scroll(-0.4, const Offset(10, 20));
    }
    expect(scripts, hasLength(1), reason: '1.2 px is worth one pixel');
    expect(scripts.single, contains('(-1.00, 10.0, 20.0)'));

    await scroller.scroll(-0.9, const Offset(10, 20));
    expect(scripts, hasLength(2), reason: '0.2 + 0.9 px carries over');
  });

  test('steps that arrive while a script runs are merged into the next',
      () async {
    final scripts = <String>[];
    final gate = <void Function()>[];
    final scroller = WebViewScroller((s) {
      scripts.add(s);
      final done = Future<void>.value();
      return gate.isEmpty ? done : done;
    });

    // Not awaited: the first call is still "running" when the next arrives.
    final first = scroller.scroll(5, Offset.zero);
    final second = scroller.scroll(7, Offset.zero);
    await Future.wait([first, second]);

    final total = scripts
        .map((s) => RegExp(r'\}\)\((-?[\d.]+),').firstMatch(s)!.group(1)!)
        .map(double.parse)
        .fold<double>(0, (a, b) => a + b);
    expect(total, 12);
  });

  test('keeps going in both directions', () async {
    final scripts = <String>[];
    final scroller = WebViewScroller((s) async => scripts.add(s));
    await scroller.scroll(40, Offset.zero);
    await scroller.scroll(-40, Offset.zero);
    expect(scripts.first, contains('(40.00,'));
    expect(scripts.last, contains('(-40.00,'));
  });

  test('scripts scroll instantly and do not depend on one element', () {
    final script = pageScrollScript(-6, const Offset(500, 40));
    expect(script, contains("behavior: 'instant'"));
    expect(script, contains('elementsFromPoint'));
    expect(script, contains('(-6.00, 500.0, 40.0)'));
  });
}
