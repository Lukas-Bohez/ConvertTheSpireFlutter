import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/browser/extensions/amo_catalog.dart';
import 'package:convert_the_spire_reborn/src/browser/extensions/web_extension_host.dart';
import 'package:convert_the_spire_reborn/src/screens/browser/extensions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Guards the Extensions screen (issue #10): the permission prompt must never
/// install on its own, managing must reach the host, and platforms without an
/// engine must say so instead of showing a broken screen.
void main() {
  final search =
      File('test/fixtures/amo/search_dark_reader.json').readAsStringSync();

  AmoCatalog catalog() => AmoCatalog(
      client: MockClient((_) async => http.Response.bytes(
          utf8.encode(search), 200,
          headers: {'content-type': 'application/json'})));

  Future<void> pump(WidgetTester tester, WebExtensionHost host) async {
    await tester.pumpWidget(MaterialApp(
      home: ExtensionsScreen(host: host, catalog: catalog()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty, unmodifiable list from the host is fine',
      (tester) async {
    // reconcile() returns a const [] when nothing is installed; sorting it in
    // place used to show an error the moment the screen opened.
    await pump(tester, _FakeHost.constEmpty());

    expect(find.textContaining('No extensions yet'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an unsupported platform explains itself', (tester) async {
    await pump(tester,
        const UnsupportedExtensionHost('Extensions need the Windows app.'));

    expect(find.text('Extensions need the Windows app.'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('installed extensions are listed and can be switched off',
      (tester) async {
    final host = _FakeHost([_darkReader]);
    await pump(tester, host);

    expect(find.text('Dark Reader'), findsOneWidget);
    expect(find.textContaining('4.9.132'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(host.enabledCalls, [('dr', false)]);
  });

  testWidgets('removing asks first, and Cancel keeps it', (tester) async {
    final host = _FakeHost([_darkReader]);
    await pump(tester, host);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Dark Reader?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(host.removed, isEmpty);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(host.removed, ['dr']);
  });

  testWidgets('the catalog shows AMO results and asks before installing',
      (tester) async {
    final host = _FakeHost([]);
    await pump(tester, host);

    await tester.tap(find.text('Get extensions'));
    await tester.pumpAndSettle();
    expect(find.text('Dark Reader'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Dark Reader?'), findsOneWidget);

    // Cancel holds the focus, so a stray OK on a remote installs nothing.
    final cancel =
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'));
    expect(cancel.autofocus, isTrue);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(host.installed, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add extension'));
    await tester.pumpAndSettle();

    final source = host.installed.single as AmoExtensionSource;
    expect(source.guid, 'addon@darkreader.org');
    expect(source.sha256, hasLength(64),
        reason: 'the published checksum must travel with the download');
  });

  group('describePermissions', () {
    test('all sites reads as all sites', () {
      expect(describePermissions(const [], const ['<all_urls>']),
          ['Read and change everything on every website']);
    });

    test('specific sites are named', () {
      expect(describePermissions(const [], const ['https://*.example.com/*']),
          ['Read and change data on example.com']);
    });

    test('host patterns inside permissions read as sites, not APIs', () {
      // AMO passes MV2 add-ons' host patterns through inside `permissions`.
      expect(describePermissions(const ['storage', '<all_urls>'], const []), [
        'Read and change everything on every website',
        'Store its own data',
      ]);
    });

    test('known permissions get a sentence, unknown ones their name', () {
      expect(describePermissions(const ['tabs', 'mystery'], const []), [
        'See the address and title of your open tabs',
        'Use "mystery"',
      ]);
    });
  });
}

const _darkReader = InstalledExtension(
  id: 'dr',
  name: 'Dark Reader',
  enabled: true,
  version: '4.9.132',
  origin: ExtensionOrigin.file,
  popupPath: 'ui/popup/index.html',
  hasAction: true,
);

class _FakeHost implements WebExtensionHost {
  _FakeHost(List<InstalledExtension> initial)
      : _list = [...initial],
        _constEmpty = false;

  _FakeHost.constEmpty()
      : _list = [],
        _constEmpty = true;

  final List<InstalledExtension> _list;
  final bool _constEmpty;
  final List<(String, bool)> enabledCalls = [];
  final List<String> removed = [];
  final List<ExtensionSource> installed = [];
  final _events = StreamController<ExtensionEvent>.broadcast();

  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  bool get runsChromiumPackages => true;

  @override
  Stream<ExtensionEvent> get events => _events.stream;

  @override
  Future<List<InstalledExtension>> list() async =>
      _constEmpty ? const [] : [..._list];

  @override
  Future<InstalledExtension> install(ExtensionSource source) async {
    installed.add(source);
    const added = InstalledExtension(
      id: 'new',
      name: 'Dark Reader',
      enabled: true,
      version: '4.9.131',
      origin: ExtensionOrigin.amo,
      amoGuid: 'addon@darkreader.org',
    );
    _list.add(added);
    return added;
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    enabledCalls.add((id, enabled));
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    _list.removeWhere((e) => e.id == id);
  }

  @override
  String? pageUrl(InstalledExtension extension, String relativePath) =>
      'chrome-extension://${extension.id}/$relativePath';
}
