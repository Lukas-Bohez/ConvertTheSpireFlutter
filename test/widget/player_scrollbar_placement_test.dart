import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Geometry tests for the player scrollbar: the thumb must move over the
/// whole area *below* the pinned TabBar/search header, from just under the
/// header down to the bottom of the screen (issue #41), and the automatic
/// desktop scrollbar of the outer NestedScrollView must be gone.
void main() {
  const screen = Size(1280, 800);
  const nowPlayingHeight = 200.0;
  const headerHeight = 160.0;

  /// Same shape as the player: a now-playing card that scrolls away, then
  /// the pinned tab/search header, then a tab body with its own scrollbar.
  Widget replica() {
    final scroll = NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          const SliverToBoxAdapter(
            child: SizedBox(height: nowPlayingHeight),
          ),
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: const SliverPersistentHeader(
              pinned: true,
              delegate: _FixedHeader(height: headerHeight),
            ),
          ),
        ];
      },
      body: Builder(
        builder: (context) => PlayerBodyScrollbar(
          child: CustomScrollView(
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => SizedBox(height: 80, child: Text('item $i')),
                  childCount: 100,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return MaterialApp(
      home: Scaffold(body: PlayerNoAutoScrollbars(child: scroll)),
    );
  }

  /// The global top and bottom of the painted thumb, found by hit testing
  /// the scrollbar painter down its right edge one pixel at a time.
  ({double top, double bottom}) thumbSpan(WidgetTester tester) {
    final scrollbar = find.byType(RawScrollbar);
    final paint = tester
        .widgetList<CustomPaint>(
          find.descendant(of: scrollbar, matching: find.byType(CustomPaint)),
        )
        .firstWhere((p) => p.foregroundPainter is ScrollbarPainter);
    final painter = paint.foregroundPainter! as ScrollbarPainter;
    final box = tester.getRect(scrollbar);
    double? top;
    double? bottom;
    for (var y = 0.0; y < box.height; y++) {
      final hit = painter.hitTestOnlyThumbInteractive(
        Offset(box.width - 4, y),
        PointerDeviceKind.mouse,
      );
      if (hit) {
        top ??= box.top + y;
        bottom = box.top + y;
      }
    }
    expect(top, isNotNull, reason: 'the thumb should be painted');
    return (top: top!, bottom: bottom!);
  }

  testWidgets('the thumb starts below the header and reaches the bottom',
      (tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(replica());
    await tester.pumpAndSettle();
    expect(find.byType(RawScrollbar), findsOneWidget);

    // At rest the header sits below the now-playing card; the thumb starts
    // under the header, never inside it.
    final headerBottom = nowPlayingHeight + headerHeight;
    var span = thumbSpan(tester);
    expect(span.top, greaterThanOrEqualTo(headerBottom - 1));

    // Scrolled to the very end: the now-playing card is gone, the header is
    // pinned at the top, and the thumb touches the bottom of the screen.
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    span = thumbSpan(tester);
    expect(span.top, greaterThanOrEqualTo(headerHeight - 1));
    expect(span.bottom, greaterThanOrEqualTo(screen.height - 2),
        reason: 'the thumb used to stop short of the bottom of the screen');
  });

  testWidgets('PlayerNoAutoScrollbars removes the automatic desktop scrollbar',
      (tester) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(replica());
    await tester.pumpAndSettle();

    // Only the explicit, correctly placed RawScrollbar remains.
    expect(find.byType(RawScrollbar), findsOneWidget,
        reason: 'only the explicit PlayerBodyScrollbar should remain');
    expect(find.byType(Scrollbar), findsNothing,
        reason: 'automatic scrollbars must be suppressed');
  });
}

class _FixedHeader extends SliverPersistentHeaderDelegate {
  final double height;
  const _FixedHeader({required this.height});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(
        height: height,
        child: const ColoredBox(color: Colors.blue),
      );
  @override
  bool shouldRebuild(covariant _FixedHeader old) => height != old.height;
}
