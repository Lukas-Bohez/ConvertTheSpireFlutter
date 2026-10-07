import 'dart:async';

import 'package:convert_the_spire_reborn/l10n/app_localizations.dart';
import 'package:convert_the_spire_reborn/src/models/loop_sections.dart';
import 'package:convert_the_spire_reborn/src/screens/loop_sections_sheet.dart';
import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The loop editor on a phone (issue #41): parts are marked while the
/// track plays, and the sheet fits a small screen without overflowing.
void main() {
  const path = '/music/song.mp3';

  Future<_FakePlayer> open(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = _FakePlayer();
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChangeNotifierProvider<PlayerState>.value(
          value: player,
          child: const LoopSectionsSheet(path: path),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return player;
  }

  testWidgets('a part is marked with Start here and End here',
      (tester) async {
    final player = await open(tester);
    expect(find.text('Loop parts'), findsOneWidget);
    expect(find.textContaining('press Start here'), findsOneWidget);

    player.position = const Duration(seconds: 190);
    await tester.tap(find.text('Start here'));
    await tester.pump();
    expect(find.text('Starts at 3:10.0'), findsOneWidget);

    player.position = const Duration(seconds: 220);
    await tester.tap(find.text('End here'));
    await tester.pumpAndSettle();

    final saved = player.loopSettingsFor(path);
    expect(saved.on, isTrue, reason: 'a new part turns looping on');
    expect(saved.sections, [
      const LoopSection(Duration(seconds: 190), Duration(seconds: 220)),
    ]);
    expect(find.byType(RangeSlider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('several parts fit a phone screen and can be deleted',
      (tester) async {
    final player = _FakePlayer();
    await player.setLoopSettings(
      path,
      const LoopSettings(on: true, sections: [
        LoopSection(Duration.zero, Duration(seconds: 30)),
        LoopSection(Duration(seconds: 90), Duration(seconds: 100)),
        LoopSection(Duration(seconds: 190), Duration(seconds: 220)),
      ]),
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      // German has the longest labels.
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChangeNotifierProvider<PlayerState>.value(
          value: player,
          child: const LoopSectionsSheet(path: path),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(find.byType(RangeSlider), findsNWidgets(3));

    await tester.tap(find.byTooltip('Diesen Abschnitt löschen').first);
    await tester.pumpAndSettle();
    expect(player.loopSettingsFor(path).sections, hasLength(2));

    // Tapping an end sets it to where playback is now.
    player.position = const Duration(seconds: 95);
    await tester.tap(find.text('1:40.0'));
    await tester.pumpAndSettle();
    expect(player.loopSettingsFor(path).sections.first,
        const LoopSection(Duration(seconds: 90), Duration(seconds: 95)));
    expect(tester.takeException(), isNull);
  });
}

/// The few things of the player the editor uses; the real one starts the
/// native players.
class _FakePlayer extends ChangeNotifier implements PlayerState {
  final _settings = <String, LoopSettings>{};
  final _positions = StreamController<PositionUiState>.broadcast();

  @override
  Duration position = Duration.zero;

  @override
  Duration? duration = const Duration(minutes: 4);

  @override
  bool loopEditing = false;

  @override
  LoopSettings loopSettingsFor(String path) =>
      _settings[path] ?? const LoopSettings(on: false, sections: []);

  @override
  Future<void> setLoopSettings(String path, LoopSettings settings) async {
    _settings[path] = LoopSettings(
      on: settings.on,
      sections:
          LoopSectionStore.normalized(settings.sections, duration: duration),
    );
    notifyListeners();
  }

  @override
  Stream<PositionUiState> get positionUiStream => _positions.stream;

  @override
  bool get isPlaying => true;

  @override
  Future<void> seek(Duration d) async => position = d;

  @override
  Future<void> togglePlay() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
