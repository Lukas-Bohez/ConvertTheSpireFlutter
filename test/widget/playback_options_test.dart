import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:convert_the_spire_reborn/src/screens/playback_options.dart';
import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Playback speed and the sleep timer pickers (issue #41).
void main() {
  test('speeds read as the player shows them', () {
    expect(formatSpeed(1.0), '1×');
    expect(formatSpeed(1.5), '1.5×');
    expect(formatSpeed(0.75), '0.75×');
    expect(formatSpeed(2.0), '2×');
  });

  Future<_FakePlayer> openWith(WidgetTester tester,
      Future<void> Function(BuildContext, PlayerState) show) async {
    final player = _FakePlayer();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => show(context, player),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return player;
  }

  testWidgets('the speed picked is the speed set', (tester) async {
    final player = await openWith(tester, showSpeedDialog);
    expect(find.text('Playback speed'), findsOneWidget);
    expect(find.text('0.5×'), findsOneWidget);
    await tester.tap(find.text('1.25×'));
    await tester.pumpAndSettle();
    expect(player.speed, 1.25);
    expect(find.text('Playback speed'), findsNothing);
  });

  testWidgets('the sleep timer picked is the one set', (tester) async {
    final player = await openWith(tester, showSleepTimerDialog);
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(player.sleepAfter, const Duration(minutes: 30));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('At the end of this track'));
    await tester.pumpAndSettle();
    expect(player.sleepAtTrackEnd, isTrue);
  });
}

class _FakePlayer extends ChangeNotifier implements PlayerState {
  @override
  double speed = 1.0;

  @override
  DateTime? sleepAt;

  @override
  bool sleepAtTrackEnd = false;

  Duration? sleepAfter;

  @override
  Future<void> setSpeed(double value) async => speed = value;

  @override
  void setSleepTimer(Duration? after) {
    sleepAfter = after;
    sleepAt = after == null ? null : DateTime.now().add(after);
    sleepAtTrackEnd = false;
  }

  @override
  void setSleepAtTrackEnd() {
    setSleepTimer(null);
    sleepAtTrackEnd = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
