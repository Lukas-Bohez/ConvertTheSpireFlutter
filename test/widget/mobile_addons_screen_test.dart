import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:convert_the_spire_reborn/src/browser/adblock/adblock_service.dart';
import 'package:convert_the_spire_reborn/src/browser/userscripts/userscript.dart';
import 'package:convert_the_spire_reborn/src/browser/userscripts/userscript_service.dart';
import 'package:convert_the_spire_reborn/src/screens/browser/mobile_addons_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The page's own list, not the scrollable inside the search field.
  final page = find
      .descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  /// Pushes the page from a button and returns what it popped with.
  Future<Future<String?> Function()> pump(WidgetTester tester,
      {required UserScriptService scripts,
      Size size = const Size(360, 740)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? popped;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: const TextScaler.linear(1.3)),
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => MobileAddonsScreen(
                      userScripts: scripts,
                      adBlock: AdBlockService(),
                    ),
                  ),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    return () async {
      expect(done, isTrue);
      return popped;
    };
  }

  testWidgets('says what runs on this device, and finds add-ons',
      (tester) async {
    final scripts = UserScriptService()
      ..seedForTesting([
        UserScript(id: 'a', name: 'A', source: '', enabled: true),
        UserScript(id: 'b', name: 'B', source: '', enabled: false),
      ]);
    final result = await pump(tester, scripts: scripts);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Ad and tracker blocking'), findsOneWidget);
    expect(find.text('1 of 2 switched on'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
        find.text('See YouTube dislikes again'), 200,
        scrollable: page);
    await tester.tap(find.text('See YouTube dislikes again'));
    await tester.pumpAndSettle();
    expect(
      await result(),
      'https://greasyfork.org/scripts?q=Return+YouTube+Dislike&sort=total_installs',
    );
  });

  testWidgets('searching opens Greasy Fork with the words typed',
      (tester) async {
    final result = await pump(tester, scripts: UserScriptService());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Tampermonkey-compatible. None installed yet'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.byType(TextField), 200,
        scrollable: page);
    await tester.enterText(find.byType(TextField), 'old reddit');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(await result(),
        'https://greasyfork.org/scripts?q=old+reddit&sort=total_installs');
  });

  testWidgets('fits a desktop window too', (tester) async {
    await pump(tester,
        scripts: UserScriptService(), size: const Size(1280, 800));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Full extensions'), 200,
        scrollable: page);
    expect(find.text('Full extensions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
