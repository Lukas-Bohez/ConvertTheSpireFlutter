import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/main.dart' as app;
import 'package:convert_the_spire_reborn/src/features/colour_rewards/colour_reward_service.dart';
import 'package:convert_the_spire_reborn/src/screens/home_screen.dart';
import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_creator_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Google Play tour: the Play build (BitPlayer) on an Android phone,
/// tablet, Chromebook-sized screen or TV, through its main features, for
/// the Play listing's screenshots and trailer.
///
/// The device can't take its own screenshots of a video (it is a texture),
/// so scripts/play_tour.py runs this test and serves it over adb reverse:
/// the demo media, and a screenshot or a recording whenever it asks.
///
/// ```
/// python scripts/play_tour.py <demo media> <out> --form phone [--record]
/// ```
///
/// See docs/publishing/store-trailer.md.
const _host = String.fromEnvironment('TOUR_HOST');
const _form = String.fromEnvironment('TOUR_FORM', defaultValue: 'phone');
const _record = bool.fromEnvironment('TOUR_RECORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('play tour', (tester) async {
    if (_host.isEmpty) {
      markTestSkipped('run it with scripts/play_tour.py');
      return;
    }
    final host = _Host(_host);
    final sandbox = await Directory.systemTemp.createTemp('play_tour');
    final mediaDir = p.join(sandbox.path, 'Music');
    for (final name in (jsonDecode(await host.ask('/media')) as List)) {
      await host.download('/media/${Uri.encodeComponent(name as String)}',
          p.join(mediaDir, name));
    }
    PathProviderPlatform.instance = _SandboxPaths(sandbox.path);
    final version = (await PackageInfo.fromPlatform()).version;
    SharedPreferences.setMockInitialValues({
      // Past the first-run tour, the What's new dialog and the tips.
      'onboardingSeenVersion': version,
      'whats_new_last_shown_version': version,
      'onboarding_step': 4,
      'player_library_folder': mediaDir,
      'volume': 0.6,
      // The screenshots show the app, not an ad, and every colour.
      'purchase_remove_ads_is_ad_free': true,
      'colour_all_purchased': true,
      'use_dht': false,
      'use_pex': false,
      'use_lpd': false,
    });
    WidgetsApp.debugAllowBannerOverride = false;
    // Notifications allowed and a tidy status bar, before the app asks.
    await host.ask('/ready');

    final errorWidgetBuilder = ErrorWidget.builder;
    final onFlutterError = FlutterError.onError;
    final tour = _Tour(tester, host);
    try {
      await app.main();
      await tour.waitFor(() => find.byType(HomeScreen).evaluate().isNotEmpty,
          const Duration(seconds: 60));
      // The app's own handler keeps an overflow's details to itself.
      final appOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('TOUR ERROR: ${details.toString()}');
        appOnError?.call(details);
      };
      if (_form == 'tablet' || _form == 'chromebook') {
        // Android's taskbar, with other apps' icons, out of the shots.
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      await tour.hold(2500);

      final home = tester.state<HomeScreenState>(find.byType(HomeScreen));
      final controller = home.widget.controller;
      final player = Provider.of<PlayerState>(
          tester.element(find.byType(HomeScreen)),
          listen: false);
      String media(String name) => p.join(mediaDir, name);
      Future<void> menu(String item) async {
        // The now-playing card's menu, not a library card's.
        await tester.tap(find.byTooltip('Track actions').first);
        await tour.hold(600);
        await tester.tap(find.text(item).last);
        await tour.hold(900);
      }

      Future<void> press(String tooltip) async {
        final button = find.byTooltip(tooltip);
        if (button.evaluate().isEmpty) return;
        // Straight to the button: the controls over a video come and go.
        final widget = tester.widget(find
            .ancestor(of: button, matching: find.byType(IconButton))
            .first) as IconButton;
        widget.onPressed?.call();
        await tour.hold(600);
      }

      // A torrent of a demo video, seeding.
      final torrentDir = Directory(p.join(sandbox.path, 'torrents'))
        ..createSync(recursive: true);
      final created = await TorrentCreatorService.instance.createTorrent(
        entries: await TorrentCreatorService.instance.collectEntries(
          filePaths: [media('Fractal Dreams.mp4')],
          directoryPaths: const [],
        ),
        torrentName: 'Fractal Dreams.mp4',
        trackers: const [],
        isPrivate: false,
        outputDirectory: torrentDir.path,
      );
      TorrentViewState? torrent;
      final torrentSub = TorrentService.instance.torrentStatesStream
          .listen((states) => torrent = states.isEmpty ? null : states.first);
      await TorrentService.instance.addTorrentFromTorrentFile(
          created.torrentPath,
          destinationPath: mediaDir);
      final checked = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(checked) &&
          (torrent?.progress ?? 0) < 0.999) {
        await tour.hold(250);
      }
      await torrentSub.cancel();

      if (_record) await tour.startRecording();

      // Home.
      await tour.mark('home');
      await tour.hold(2500);
      await tour.shot('1-home');

      // The player and the library.
      await tour.mark('player');
      home.openPage('player.tab');
      await tour.waitFor(
          () => player.library.length >= 12, const Duration(seconds: 30));
      await player.playFileDirect(media('Neon Rain.mp3'));
      // Up next, beside the player on a wide screen.
      for (final song in const [
        'Midnight Drive',
        'Paper Planes',
        'Slow Sunrise',
        'Northern Coast',
        'City Lights'
      ]) {
        player.enqueue(player.mediaIndexForPath(media('$song.mp3')));
      }
      // Time for the library's covers to load.
      await tour.hold(5000);
      await tour.shot('2-player');

      // A video, with its subtitles.
      await tour.mark('video');
      await player.playFileDirect(media('Fractal Dreams.mp4'));
      await tour.hold(3600);
      await tour.shot('3-video-subtitles');

      // The large view.
      await tour.mark('large');
      await press('Large view');
      await tour.hold(1600);
      await tour.shot('4-large-view');
      await tour.hold(2000);
      await press('Exit large view');
      await tour.hold(700);

      if (_form != 'tv') {
        // Loop the best part of a song.
        await tour.mark('loop');
        await player.playFileDirect(media('Midnight Drive.mp3'));
        await tour.hold(800);
        await player.seek(const Duration(seconds: 58));
        await menu('Loop parts');
        await tester.tap(find.text('Start here'));
        await tour.hold(4200);
        await tester.tap(find.text('End here'));
        await tour.hold(1600);
        await tour.shot('5-loop-parts');
        // The back button closes the sheet.
        await tester.binding.handlePopRoute();
        await tour.hold(1200);

        // Speed.
        await tour.mark('speed');
        await menu('Playback speed');
        await tester.tap(find.text('1.5×'));
        await tour.hold(1800);
      }

      // Torrents.
      await tour.mark('torrents');
      home.openPage('torrents.tab');
      await tour.hold(3500);
      await tour.shot('6-torrents');

      // Colours, light and dark.
      await tour.mark('colours');
      home.openPage('player.tab');
      await tour.hold(800);
      for (final colour in const ['royal_amethyst', 'dragon_teal', 'ember']) {
        await ColourRewardService.instance.equipColour(colour);
        await tour.hold(1100);
      }
      await controller.setThemeMode(ThemeMode.dark);
      await ColourRewardService.instance.equipColour('ocean_blue');
      await tour.hold(1800);
      await tour.shot('7-player-dark');
      home.openPage('home');
      await tour.mark('end');
      await tour.hold(300);
    } finally {
      await tour.stopRecording();
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = onFlutterError;
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// scripts/play_tour.py, on the computer the device is attached to.
class _Host {
  _Host(this.base);

  final String base;

  Future<String> ask(String path) async {
    final client = HttpClient();
    try {
      final response =
          await (await client.getUrl(Uri.parse('$base$path'))).close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw StateError('$path: ${response.statusCode} $body');
      }
      return body;
    } finally {
      client.close();
    }
  }

  Future<void> download(String path, String to) async {
    final client = HttpClient();
    try {
      final response =
          await (await client.getUrl(Uri.parse('$base$path'))).close();
      final file = File(to);
      await file.parent.create(recursive: true);
      await response.pipe(file.openWrite());
    } finally {
      client.close();
    }
  }
}

class _Tour {
  _Tour(this.tester, this.host);

  final WidgetTester tester;
  final _Host host;
  bool _recording = false;

  /// Keeps the app running, frames and all, for [ms].
  Future<void> hold(int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> waitFor(bool Function() condition, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (!condition() && DateTime.now().isBefore(end)) {
      await hold(100);
    }
    expect(condition(), isTrue);
  }

  /// Where the recording is at: the host notes the time.
  Future<void> mark(String id) async {
    if (_recording) await host.ask('/mark/$id');
  }

  Future<void> shot(String name) => host.ask('/shot/$name');

  Future<void> startRecording() async {
    await host.ask('/record/start');
    _recording = true;
  }

  Future<void> stopRecording() async {
    if (!_recording) return;
    _recording = false;
    await host.ask('/record/stop');
  }
}

/// The app's folders, in the sandbox.
class _SandboxPaths extends PathProviderPlatform {
  _SandboxPaths(this.root);

  final String root;

  String _dir(String name) {
    final dir = Directory(p.join(root, name))..createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _dir('temp');
  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');
  @override
  Future<String?> getLibraryPath() async => _dir('library');
  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');
  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');
  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');
  @override
  Future<String?> getExternalStoragePath() async => _dir('external');
  @override
  Future<List<String>?> getExternalCachePaths() async => [_dir('external')];
  @override
  Future<List<String>?> getExternalStoragePaths(
          {StorageDirectory? type}) async =>
      [_dir('external')];
}
