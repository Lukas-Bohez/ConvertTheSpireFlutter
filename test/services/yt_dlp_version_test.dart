import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/src/services/yt_dlp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Issue #45, fix 3: the engine check said "not available" for a yt-dlp that
/// worked but started slowly.
void main() {
  late Directory dir;
  late File binary;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ytdlp_version_test');
    binary = File(p.join(dir.path, Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp'));
    await binary.writeAsString('not a program');
  });

  tearDown(() => dir.delete(recursive: true));

  test('a remembered version is returned without starting the program',
      () async {
    final stat = await binary.stat();
    SharedPreferences.setMockInitialValues({
      'ytdlp_version_cache': jsonEncode({
        'path': binary.path,
        'stamp': '${stat.size}-${stat.modified.millisecondsSinceEpoch}',
        'version': '2026.10.21',
      }),
    });
    expect(await YtDlpService().getVersion(configuredPath: binary.path),
        '2026.10.21');
  });

  test('a changed binary is not trusted to have the remembered version',
      () async {
    SharedPreferences.setMockInitialValues({
      'ytdlp_version_cache': jsonEncode({
        'path': binary.path,
        'stamp': 'some-other-size-and-time',
        'version': '2026.10.21',
      }),
    });
    // It is run again; this one is not a real program, so that fails.
    await expectLater(
        YtDlpService().getVersion(configuredPath: binary.path), throwsA(anything));
  });

  test('a yt-dlp that is there but cannot run is not "not installed"',
      () async {
    SharedPreferences.setMockInitialValues({});
    // null means "not installed" and shows "not available"; this must throw,
    // which the page shows as an interrupted check that it retries.
    await expectLater(
        YtDlpService().getVersion(configuredPath: binary.path), throwsA(anything));
  });
}
