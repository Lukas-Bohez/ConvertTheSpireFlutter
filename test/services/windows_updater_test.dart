import 'package:flutter_test/flutter_test.dart';

import 'package:convert_the_spire_reborn/src/services/update_service.dart';
import 'package:convert_the_spire_reborn/src/services/windows_updater.dart';

void main() {
  const hash =
      '9999c02a7a422d7e6c7fa3536f1db7a907ec269dd5c2e3ad490de09043f6d56c';

  group('WindowsUpdater.expectedHash', () {
    test('finds the installer in the release checksums', () {
      const sums = '''
1111111111111111111111111111111111111111111111111111111111111111  ./android-apk/ConvertTheSpireReborn.apk
$hash  ./windows-installer/ConvertTheSpireReborn-Setup.exe
2222222222222222222222222222222222222222222222222222222222222222  ./windows-x64/ConvertTheSpireReborn-windows-x64.zip
''';
      expect(WindowsUpdater.expectedHash(sums), hash);
    });

    test('is null when the installer is not listed', () {
      expect(
          WindowsUpdater.expectedHash(
              '$hash  ./windows-x64/ConvertTheSpireReborn-windows-x64.zip'),
          isNull);
    });

    test('ignores a line whose hash is not a SHA-256', () {
      expect(
          WindowsUpdater.expectedHash(
              'abc  ./windows-installer/ConvertTheSpireReborn-Setup.exe'),
          isNull);
    });
  });

  group('WindowsUpdater.isInstalledCopy', () {
    const env = {'LOCALAPPDATA': r'C:\Users\me\AppData\Local'};

    test('the copy Setup installed updates silently', () {
      expect(
          WindowsUpdater.isInstalledCopy(
              r'C:\Users\me\AppData\Local\Programs\ConvertTheSpireReborn\convert_the_spire_reborn.exe',
              env),
          isTrue);
      expect(WindowsUpdater.setupArguments(true), contains('/VERYSILENT'));
    });

    test('a copy run from an extracted zip gets the normal installer', () {
      expect(
          WindowsUpdater.isInstalledCopy(
              r'C:\Users\me\Downloads\ConvertTheSpireReborn\convert_the_spire_reborn.exe',
              env),
          isFalse);
      expect(WindowsUpdater.setupArguments(false), isEmpty);
    });
  });

  test('the banner preview skips the release page HTML and Markdown', () {
    const body = '''
<p align="center">
  <a href="https://youtu.be/x"><img src="https://img.youtube.com/x.jpg"></a>
</p>

## Double-click install on Windows

### New

- **Setup.exe** installs the app. See [the README](https://example.com).
''';
    final preview = UpdateService.releaseNotesPreview(body);
    expect(preview, startsWith('Double-click install on Windows'));
    expect(preview, contains('Setup.exe installs the app. See the README.'));
    expect(preview, isNot(contains('<')));
    expect(preview, isNot(contains('**')));
  });
}
