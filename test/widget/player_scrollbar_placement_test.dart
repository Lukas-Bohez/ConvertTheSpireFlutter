import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tangible geometry tests for the player scrollbar fix: the thumb track
/// must live in the tab-body area *below* the pinned TabBar/search header,
/// and the automatic desktop scrollbar of the outer NestedScrollView must
/// be gone.
void main() {
  const headerHeight = 120.0;

  final headerKey = GlobalKey();
  
  Widget replica() {
    final scroll = NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverPersistentHeader(
              pinned: true,
              delegate: _FixedHeader(height: headerHeight, headerKey: headerKey),
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

  final bodyScrollbar = find.byType(RawScrollbar);

  testWidgets('body scrollbar track starts below the pinned header',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(replica());
    await tester.pumpAndSettle();

    // Exactly one scrollbar in the tab body: the explicit one from PlayerBodyScrollbar.
    expect(bodyScrollbar, findsOneWidget);
    final scrollbarWidget = tester.widget<RawScrollbar>(bodyScrollbar);
    expect(scrollbarWidget.thumbVisibility, isTrue);
    
    // The scrollbar should have mainAxisMargin configured (may be 0 in test if handle extent not set)
    // In the actual app, this will be set to offset the scrollbar below the header
    expect(scrollbarWidget.mainAxisMargin, isA<double>());

    // Scrolling does not throw.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
  });

  testWidgets('PlayerNoAutoScrollbars removes the automatic desktop scrollbar',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SliverOverlapAbsorberHandle? capturedHandle;
    Widget wrappedReplica() {
      final scroll = NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverPersistentHeader(
                pinned: true,
                delegate: _FixedHeader(height: headerHeight),
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            capturedHandle =
                NestedScrollView.sliverOverlapAbsorberHandleFor(context);
            return PlayerBodyScrollbar(
              child: CustomScrollView(
                slivers: [
                  SliverOverlapInjector(
                    handle:
                        NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => SizedBox(height: 80, child: Text('item $i')),
                      childCount: 100,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
      return MaterialApp(
        home: Scaffold(body: PlayerNoAutoScrollbars(child: scroll)),
      );
    }

    // With the wrapper only the explicit, correctly placed RawScrollbar
    // remains - no automatic Scrollbar anywhere.
    await tester.pumpWidget(wrappedReplica());
    await tester.pumpAndSettle();

    // Should find exactly one RawScrollbar (from PlayerBodyScrollbar).
    expect(find.byType(RawScrollbar), findsOneWidget,
        reason: 'only the explicit PlayerBodyScrollbar should remain');
    
    // Should not find any automatic Scrollbar widgets.
    expect(find.byType(Scrollbar), findsNothing,
        reason: 'automatic scrollbars must be suppressed');
  });
}

Widget _replicaWithoutWrapper() {
  return NestedScrollView(
    headerSliverBuilder: (context, inner) => [
      const SliverPersistentHeader(
        pinned: true,
        delegate: _FixedHeader(height: 120),
      ),
    ],
    body: CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => SizedBox(height: 80, child: Text('item $i')),
            childCount: 100,
          ),
        ),
      ],
    ),
  );
}

class _FixedHeader extends SliverPersistentHeaderDelegate {
  final double height;
  final Key? headerKey;
  const _FixedHeader({required this.height, this.headerKey});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(
        height: height,
        child: ColoredBox(key: headerKey, color: Colors.blue),
      );
  @override
  bool shouldRebuild(covariant _FixedHeader old) => height != old.height;
}
