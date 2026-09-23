import 'dart:io';
import 'dart:ui' as ui;

import 'package:convert_the_spire_reborn/src/browser/extensions/webview2_extension_host.dart';
import 'package:convert_the_spire_reborn/src/screens/browser/extensions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';

/// Walks the Extensions screen end to end on a real WebView2, the way a user
/// would: browse the addons.mozilla.org catalog, add Dark Reader through the
/// permission prompt, then open its popup (issue #10).
///
/// With EXT_SHOTS set, it saves a picture of the app at each step into that
/// folder. The picture is rendered from the app's own widget tree, never
/// taken from the screen, so nothing outside the app can end up in it.
///
///   flutter test -d windows integration_test/extensions_screen_ui_test.dart
///     --dart-define=EXT_PROFILE=C:\path\to\profile
///     --dart-define=EXT_SHOTS=C:\path\to\shots        (optional)
const _profile = String.fromEnvironment('EXT_PROFILE');
const _shots = String.fromEnvironment('EXT_SHOTS');

void main() {
  if (!Platform.isWindows || _profile.isEmpty) return;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> waitFor(WidgetTester tester, Finder finder,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(finder, findsWidgets);
  }

  final boundaryKey = GlobalKey();
  var shot = 0;
  Future<void> screenshot(WidgetTester tester, String name) async {
    if (_shots.isEmpty) return;
    shot++;
    await settle(tester, const Duration(milliseconds: 600));
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(p.join(_shots, '$shot-$name.png'))
          .writeAsBytes(png!.buffer.asUint8List());
    });
  }

  testWidgets('catalog, permission prompt, install, popup', (tester) async {
    await WebviewController.initializeEnvironment(userDataPath: _profile);
    final root = Directory(p.join(_profile, '..', 'ui-root'));
    if (await root.exists()) await root.delete(recursive: true);
    final host = WebView2ExtensionHost(rootDirectory: () async => root);

    await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: const Color(0xFF5B8DEF)),
            useMaterial3: true,
          ),
          home: ExtensionsScreen(host: host),
        )));
    await waitFor(tester, find.textContaining('No extensions yet'));
    await screenshot(tester, 'empty');

    // The catalog, straight from addons.mozilla.org.
    await tester.tap(find.text('Get extensions'));
    await waitFor(tester, find.widgetWithText(FilledButton, 'Add'));
    await screenshot(tester, 'catalog');

    await tester.enterText(find.byType(TextField), 'dark reader');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(tester, find.text('Dark Reader'));
    await screenshot(tester, 'search');

    // The permission prompt: nothing installs until "Add extension".
    final darkReaderTile = find.ancestor(
        of: find.text('Dark Reader'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: darkReaderTile.first,
        matching: find.widgetWithText(FilledButton, 'Add')));
    await waitFor(tester, find.text('Add Dark Reader?'));
    await screenshot(tester, 'permissions');

    await tester.tap(find.text('Add extension'));
    // The catalog row turns into an "Installed" chip. (The tab is also
    // called Installed, so look for the chip, not the text.)
    await waitFor(tester, find.widgetWithText(Chip, 'Installed'),
        timeout: const Duration(seconds: 60));
    expect((await host.list()).single.name, 'Dark Reader');

    await tester.tap(find.widgetWithText(Tab, 'Installed'));
    await waitFor(tester, find.text('Open'));
    await screenshot(tester, 'installed');

    // Its popup, hosted in the app's own webview.
    await tester.tap(find.text('Open'));
    await settle(tester, const Duration(seconds: 6));
    expect(find.byType(Webview), findsOneWidget);
    await screenshot(tester, 'popup');

    await tester.tap(find.byTooltip('Close'));
    await settle(tester, const Duration(seconds: 1));
    for (final extension in await host.list()) {
      await host.remove(extension.id);
    }
    host.close();
  });
}
