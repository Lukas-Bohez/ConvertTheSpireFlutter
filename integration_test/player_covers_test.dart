import 'dart:io';

import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' show MediaKit;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Song covers: read from the file (decoded off the UI thread), and kept
/// when the library is loaded again, as it is when a download lands in its
/// folder. They used to stay grey for the rest of the session then.
///
///   flutter test -d windows integration_test/player_covers_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PlayerState player;

  setUpAll(() {
    MediaKit.ensureInitialized();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('player_covers_test');
    // A cover cache of its own, not the installed app's.
    PathProviderPlatform.instance = _Paths(dir.path);
    SharedPreferences.setMockInitialValues({});
    player = PlayerState(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    player.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> waitFor(bool Function() condition, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a cover is found, and kept when the library loads again',
      (tester) async {
    final path = '${dir.path}${Platform.pathSeparator}song.mp3';
    await File('integration_test/fixtures/song_with_cover.mp3').copy(path);
    MediaItem song() => MediaItem(path, MediaType.audio, title: 'Cover Song');

    await player.setLibrary([song()]);
    await player.requestThumbnailForIndex(0);
    await waitFor(() => player.library.first.thumbnailData != null,
        const Duration(seconds: 10));
    expect(player.library.first.thumbnailData, isNotNull);

    // The folder changed: the same song comes back as a new item.
    await player.setLibrary([song()]);
    expect(player.library.first.thumbnailData, isNotNull,
        reason: 'the cover stays with its song');
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);

  final String root;

  String _dir(String name) {
    final dir = Directory('$root${Platform.pathSeparator}$name')
      ..createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _dir('temp');
  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');
  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');
}
