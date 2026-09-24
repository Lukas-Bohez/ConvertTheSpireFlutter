import 'dart:async';

import 'package:convert_the_spire_reborn/src/browser/extensions/extension_hosts.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/web_extension_host.dart';
import 'package:convert_the_spire_reborn/src/screens/browser/browser_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _toolbar({ValueChanged<String>? onMenuAction}) => MaterialApp(
      home: Material(
        child: BrowserToolbar(
          isLoading: false,
          isSecure: true,
          isIncognito: false,
          canGoBack: false,
          canGoForward: false,
          hasVideos: false,
          castBadgeAnimation: AnimationController(
              vsync: const TestVSync(),
              duration: const Duration(milliseconds: 1)),
          desktopMode: false,
          adBlockEnabled: false,
          pageTitle: 'Example',
          currentUrl: 'https://example.com',
          onBack: () {},
          onForward: () {},
          onReload: () {},
          onCastTap: () {},
          onMenuAction: onMenuAction ?? (_) {},
          onTabs: () {},
        ),
      ),
    );

void main() {
  testWidgets(
      'BrowserToolbar shows download and favourite buttons when enabled',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: BrowserToolbar(
          isLoading: false,
          isSecure: true,
          isIncognito: false,
          canGoBack: false,
          canGoForward: false,
          hasVideos: true,
          castBadgeAnimation: AnimationController(
              vsync: TestVSync(), duration: const Duration(milliseconds: 1)),
          desktopMode: false,
          adBlockEnabled: false,
          pageTitle: 'Example',
          currentUrl: 'https://example.com',
          onBack: () {},
          onForward: () {},
          onReload: () {},
          onCastTap: () {},
          onDownload: () {},
          downloadEnabled: true,
          isKnownDifficultSite: false,
          onMenuAction: (_) {},
          onTabs: () {},
          tabCount: 1,
          isFavourited: true,
          onFavouriteTap: () {},
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // Expect download icon present
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    // Expect star icon (filled) present
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });

  group('extension button (issue #10)', () {
    tearDown(() => ExtensionHosts.current =
        const UnsupportedExtensionHost('not in tests'));

    testWidgets('appears once an enabled extension has a popup',
        (tester) async {
      ExtensionHosts.current = _FakeHost([
        _extension('dr', 'Dark Reader', popup: 'popup.html'),
        _extension('off', 'Disabled One', popup: 'p.html', enabled: false),
        _extension('btn', 'Button Only'),
      ]);
      final actions = <String>[];
      await tester.pumpWidget(_toolbar(onMenuAction: actions.add));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Extensions'));
      await tester.pumpAndSettle();

      expect(find.text('Dark Reader'), findsOneWidget);
      expect(find.text('Disabled One'), findsNothing,
          reason: 'a switched-off extension has nothing to open');
      expect(find.text('Button Only'), findsNothing,
          reason: 'a button without a popup cannot be pressed from here');

      await tester.tap(find.text('Manage extensions'));
      await tester.pumpAndSettle();
      expect(actions, ['extensions']);
    });

    testWidgets('stays hidden when there is nothing to open', (tester) async {
      ExtensionHosts.current = _FakeHost([_extension('btn', 'Button Only')]);
      await tester.pumpWidget(_toolbar());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Extensions'), findsNothing);
    });

    testWidgets('platforms without extensions get no button and no menu item',
        (tester) async {
      ExtensionHosts.current =
          const UnsupportedExtensionHost('Windows only for now.');
      await tester.pumpWidget(_toolbar());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Extensions'), findsNothing);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Extensions'), findsNothing,
          reason: 'the Play build must not grow an Extensions entry');
      expect(find.text('Userscripts'), findsOneWidget);
    });

    testWidgets('the menu offers Extensions where they are supported',
        (tester) async {
      ExtensionHosts.current = _FakeHost(const []);
      await tester.pumpWidget(_toolbar());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Extensions'), findsOneWidget);
    });
  });

  group('layout at every width, with large text', () {
    tearDown(() => ExtensionHosts.current =
        const UnsupportedExtensionHost('not in tests'));

    for (final width in [360.0, 640.0, 800.0, 1280.0]) {
      testWidgets('no overflow at ${width.toInt()}px and 130% text',
          (tester) async {
        ExtensionHosts.current =
            _FakeHost([_extension('dr', 'Dark Reader', popup: 'p.html')]);
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
              size: Size(width, 720), textScaler: const TextScaler.linear(1.3)),
          child: _toolbar(),
        ));
        await tester.pumpAndSettle();

        // Both menus open without an overflow either.
        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Extensions'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });
}

InstalledExtension _extension(String id, String name,
        {String? popup, bool enabled = true}) =>
    InstalledExtension(
      id: id,
      name: name,
      enabled: enabled,
      version: '1.0',
      origin: ExtensionOrigin.file,
      popupPath: popup,
      hasAction: true,
    );

class _FakeHost implements WebExtensionHost {
  _FakeHost(this._list);

  final List<InstalledExtension> _list;

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  bool get runsChromiumPackages => true;

  @override
  Stream<ExtensionEvent> get events => const Stream.empty();

  @override
  Future<List<InstalledExtension>> list() async => _list;

  @override
  Future<InstalledExtension> install(ExtensionSource source) =>
      Future.error(UnimplementedError());

  @override
  Future<void> setEnabled(String id, bool enabled) async {}

  @override
  Future<void> remove(String id) async {}

  @override
  String? pageUrl(InstalledExtension extension, String relativePath) =>
      'chrome-extension://${extension.id}/$relativePath';
}
