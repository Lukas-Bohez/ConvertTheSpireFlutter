import 'package:convert_the_spire_reborn/src/services/linux_updater.dart';
import 'package:convert_the_spire_reborn/src/services/release_checksums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = 'a' * 64;
  final b = 'B' * 64;
  final sums = '$a  ConvertTheSpireReborn-Setup.exe\n'
      '$b  ConvertTheSpireReborn-linux-x86_64.AppImage\n'
      'cafe  ConvertTheSpireReborn-linux-x64.tar.gz\n';

  test('finds the AppImage in the release checksums', () {
    expect(releaseFileHash(sums, 'ConvertTheSpireReborn-linux-x86_64.AppImage'),
        'b' * 64);
    expect(releaseFileHash(sums, 'ConvertTheSpireReborn-Setup.exe'), a);
  });

  test('a file that is not listed, or not with a SHA-256, has no hash', () {
    expect(
        releaseFileHash(sums, 'ConvertTheSpireReborn-linux-aarch64.AppImage'),
        isNull);
    expect(releaseFileHash(sums, 'ConvertTheSpireReborn-linux-x64.tar.gz'),
        isNull);
  });

  test('reads the older lines with a folder', () {
    expect(
        releaseFileHash(
            '$a  ./linux-x64/ConvertTheSpireReborn-linux-x86_64.AppImage',
            'ConvertTheSpireReborn-linux-x86_64.AppImage'),
        a);
  });

  test('only an AppImage updates itself', () {
    expect(
        LinuxUpdater.runningAppImage(
            {'APPIMAGE': '/home/me/Apps/ConvertTheSpireReborn.AppImage'}),
        '/home/me/Apps/ConvertTheSpireReborn.AppImage');
    expect(LinuxUpdater.runningAppImage({'APPIMAGE': ''}), isNull);
    expect(LinuxUpdater.runningAppImage({'HOME': '/home/me'}), isNull);
  });
}
