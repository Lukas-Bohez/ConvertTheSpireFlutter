import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:convert_the_spire_reborn/src/config/full_mode_access.dart';
import 'package:convert_the_spire_reborn/src/services/purchase_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/adaptive_ui_frame.dart';
import 'package:convert_the_spire_reborn/src/widgets/quick_links_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #35: the home page shows which version this is, at the title's
/// bottom right on wide screens and under it on phones.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Convert the Spire Reborn',
      packageName: 'convert_the_spire_reborn',
      version: '15.2.0',
      buildNumber: '1301',
      buildSignature: '',
    );
  });

  Future<void> show(WidgetTester tester, Size size,
      {bool appFrame = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<FullModeAccess>.value(
            value: FullModeAccess.instance),
        ChangeNotifierProvider<PurchaseService>.value(
            value: PurchaseService.instance),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The frame the app puts around every page (app.dart), which sizes
        // the buttons for the screen.
        builder: appFrame
            ? (context, child) => AdaptiveUiFrame(child: child!)
            : null,
        home: Scaffold(
          body: QuickLinksPage(
            onNavigate: (_) {},
            onDownload: (_, __, ___, {parts = const []}) async {},
            getYtDlpVersion: () async => null,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Rect titleRect(WidgetTester tester) =>
      tester.getRect(find.text('Convert the Spire Reborn'));

  testWidgets('wide: at the bottom right of the title', (tester) async {
    await show(tester, const Size(1280, 900));
    final version = find.byKey(const ValueKey('app-version'));
    expect(version, findsOneWidget);
    expect(tester.widget<Text>(version).data, 'v15.2.0');

    final title = titleRect(tester);
    final label = tester.getRect(version);
    expect(label.left, greaterThanOrEqualTo(title.right));
    expect(label.bottom, closeTo(title.bottom, title.height / 2));
    // Between a quarter and half the title's size.
    expect(label.height, lessThan(title.height * 0.6));
    expect(label.height, greaterThan(title.height * 0.2));
  });

  testWidgets('phone: under the title', (tester) async {
    await show(tester, const Size(390, 844));
    final version = find.byKey(const ValueKey('app-version'));
    expect(version, findsOneWidget);
    final title = titleRect(tester);
    final label = tester.getRect(version);
    expect(label.top, greaterThanOrEqualTo(title.bottom));
    expect(label.center.dx, closeTo(title.center.dx, 1));
  });

  // The museum button (the filled one) was shorter than the three beside it.
  for (final (name, size, height) in [
    // Tall enough that Home's last card is on screen. Narrow is under the
    // frame's 840 but wide enough that the test font (every letter a
    // square) keeps each label on one line.
    ('wide', const Size(1280, 4000), 56.0),
    ('narrow', const Size(700, 6000), 48.0),
  ]) {
    testWidgets('$name: the project buttons are the same height',
        (tester) async {
      await show(tester, size, appFrame: true);
      final labels = [
        'Play Spire Museum',
        'View portfolio',
        'Support with a donation',
        'Copy app download link',
      ];
      for (final label in labels) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(button, findsOneWidget);
        expect(tester.getSize(button).height, height, reason: label);
      }
    });
  }
}
