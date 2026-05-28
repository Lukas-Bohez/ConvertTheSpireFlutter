import 'package:convert_the_spire_reborn/src/services/network_proxy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('formats ytdlp proxy URLs with auth encoding', () {
    const settings = ProxySettings(
      enabled: true,
      host: 'proxy.example',
      port: 1080,
      username: 'user name',
      password: 'p@ss word',
      useForTrackers: true,
      useForPeers: false,
    );

    expect(
      settings.toYtDlpProxyUrl(),
      'socks5://user%20name:p%40ss%20word@proxy.example:1080',
    );
  });

  test('persists and reloads proxy settings', () async {
    const settings = ProxySettings(
      enabled: true,
      host: '127.0.0.1',
      port: 1081,
      username: 'alice',
      password: 'secret',
      useForTrackers: false,
      useForPeers: true,
    );

    await NetworkProxyService.save(settings);
    final loaded = await NetworkProxyService.load();

    expect(loaded.enabled, isTrue);
    expect(loaded.host, '127.0.0.1');
    expect(loaded.port, 1081);
    expect(loaded.username, 'alice');
    expect(loaded.password, 'secret');
    expect(loaded.useForTrackers, isFalse);
    expect(loaded.useForPeers, isTrue);

    await NetworkProxyService.clear();
    final cleared = await NetworkProxyService.load();
    expect(cleared.enabled, isFalse);
    expect(cleared.host, isEmpty);
  });
}
