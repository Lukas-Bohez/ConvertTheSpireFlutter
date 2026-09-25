import 'package:convert_the_spire_reborn/src/services/network_proxy_service.dart';
import 'package:convert_the_spire_reborn/src/utils/l10n.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/widgets/torrent_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The torrent settings are a card in the app's Settings screen now; if the
/// card threw, the whole Settings screen would fail with it.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: TorrentSettingsCard()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the torrent settings', (tester) async {
    await pumpCard(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(Card)));

    expect(find.text(l10n.tabTorrents), findsOneWidget);
    expect(find.text(l10n.enableDht), findsOneWidget);
    expect(find.text(l10n.listenPort), findsOneWidget);
    expect(find.text(l10n.saveConnectionSettings), findsOneWidget);
    // The proxy fields only show once the proxy is turned on.
    expect(find.text(l10n.proxyHost), findsNothing);
  });

  testWidgets('a switch saves straight away', (tester) async {
    await pumpCard(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(Card)));
    final before = SettingsService.instance.useDht;

    await tester.tap(find.text(l10n.enableDht));
    await tester.pumpAndSettle();

    expect(SettingsService.instance.useDht, !before);
  });

  testWidgets('saving keeps the connection numbers and the proxy',
      (tester) async {
    await pumpCard(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(Card)));

    await tester.enterText(
        find.widgetWithText(TextField, l10n.listenPort), '51413');
    await tester.tap(find.text(l10n.enableProxy));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, l10n.proxyHost), 'proxy.local');
    await tester.tap(find.text(l10n.saveConnectionSettings));
    await tester.pumpAndSettle();

    expect(SettingsService.instance.listenPort, 51413);
    final proxy = await NetworkProxyService.load();
    expect(proxy.enabled, isTrue);
    expect(proxy.host, 'proxy.local');
  });
}
