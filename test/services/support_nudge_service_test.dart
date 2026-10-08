import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:convert_the_spire_reborn/src/services/support_nudge_service.dart';
import 'package:convert_the_spire_reborn/src/widgets/support_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home's donation card (issue #41) asks only someone the app has served
/// for a while, and stays away when told to.
void main() {
  final nudge = SupportNudgeService.instance;
  final day = DateTime(2026, 10, 7);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nudge.resetForTesting();
    SupportNudgeService.enabledInBuild = () => true;
  });

  Future<void> use({int launches = 10, int successes = 5}) async {
    for (var i = 0; i < launches; i++) {
      await nudge.trackLaunch(now: day);
    }
    for (var i = 0; i < successes; i++) {
      await nudge.recordSuccess(now: day);
    }
  }

  test('only after ten starts and five things that went well', () async {
    await use(launches: 9, successes: 5);
    expect(nudge.show, isFalse);
    await nudge.trackLaunch(now: day);
    expect(nudge.show, isTrue);

    SharedPreferences.setMockInitialValues({});
    nudge.resetForTesting();
    await use(launches: 20, successes: 4);
    expect(nudge.show, isFalse);
  });

  test('"Not now" for six weeks, a donation for four months', () async {
    await use();
    await nudge.notNow(now: day);
    expect(nudge.show, isFalse);
    await nudge.trackLaunch(now: day.add(const Duration(days: 44)));
    expect(nudge.show, isFalse);
    await nudge.trackLaunch(now: day.add(const Duration(days: 46)));
    expect(nudge.show, isTrue);

    await nudge.donated(now: day.add(const Duration(days: 46)));
    await nudge.trackLaunch(now: day.add(const Duration(days: 150)));
    expect(nudge.show, isFalse);
    await nudge.trackLaunch(now: day.add(const Duration(days: 170)));
    expect(nudge.show, isTrue);
  });

  test('"Don\'t show again" is for good', () async {
    await use();
    await nudge.never();
    await nudge.trackLaunch(now: day.add(const Duration(days: 3650)));
    expect(nudge.show, isFalse);
  });

  test('never in the Play version', () async {
    SupportNudgeService.enabledInBuild = () => false;
    await use(launches: 50, successes: 50);
    expect(nudge.show, isFalse);
  });

  testWidgets('the card fits a phone and goes on "Not now"', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => use());
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: SupportCard())),
    ));
    expect(find.text('Buy Me a Coffee'), findsOneWidget);
    expect(find.text('Nicht jetzt'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.tap(find.text('Nicht jetzt'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.text('Nicht jetzt'), findsNothing);
  });
}
