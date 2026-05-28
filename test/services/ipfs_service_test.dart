import 'package:convert_the_spire_reborn/src/services/ipfs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('resolves IPFS and IPNS URLs using the configured gateway', () async {
    await IpfsService.setCustomGateway('https://gateway.example/');

    expect(
      await IpfsService.resolveUrl('ipfs://bafytestcid'),
      'https://gateway.example/ipfs/bafytestcid',
    );
    expect(
      await IpfsService.resolveUrl('ipns://my-name'),
      'https://gateway.example/ipns/my-name',
    );
  });

  test('normalizes bare content hashes into gateway URLs', () async {
    expect(
      await IpfsService.resolveUrl('bafybasiccid'),
      startsWith('https://ipfs.io/ipfs/'),
    );
  });
}
