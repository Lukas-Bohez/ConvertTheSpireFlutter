import 'dart:convert';
import 'dart:io';

import 'package:convert_the_spire_reborn/main.dart' as app;
import 'package:convert_the_spire_reborn/src/features/colour_rewards/colour_reward_service.dart';
import 'package:convert_the_spire_reborn/src/screens/home_screen.dart';
import 'package:convert_the_spire_reborn/src/screens/player.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_creator_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// The store tour: the real app, filling the main 1920x1080 display,
/// through its main features, for the store screenshots and trailer.
///
/// It runs in a sandbox: settings in memory and a data folder of its own,
/// so none of the computer's own library, torrents or settings show, and
/// with a library of generated demo media (made-up artists, generated
/// pictures and tones: nothing anyone holds the rights to).
///
/// ```
/// flutter test -d windows integration_test/store_tour_test.dart \
///   --dart-define=DEMO_MEDIA=<folder> --dart-define=TOUR_OUT=<folder> \
///   --dart-define=FFMPEG=<ffmpeg.exe> [--dart-define=TOUR_RECORD=true]
/// ```
///
/// See docs/publishing/store-trailer.md.
const _media = String.fromEnvironment('DEMO_MEDIA');
const _out = String.fromEnvironment('TOUR_OUT');
const _ffmpeg = String.fromEnvironment('FFMPEG');
const _record = bool.fromEnvironment('TOUR_RECORD');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store tour', (tester) async {
    if (_media.isEmpty || _out.isEmpty || _ffmpeg.isEmpty) {
      markTestSkipped('DEMO_MEDIA, TOUR_OUT and FFMPEG are needed');
      return;
    }
    await Directory(_out).create(recursive: true);
    final sandbox = await Directory.systemTemp.createTemp('store_tour');
    PathProviderPlatform.instance = _SandboxPaths(sandbox.path);
    // A download folder without anyone's user name in it, on Home.
    await File(p.join(sandbox.path, 'support', 'config.json'))
        .create(recursive: true)
        .then((f) => f.writeAsString(
            jsonEncode({'download_dir': r'C:\Users\Public\Music'})));
    // FFmpeg where the app downloads it to, for the video thumbnails.
    final ffmpegDir =
        Directory(p.join(sandbox.path, 'support', 'ffmpeg', 'bin'));
    await ffmpegDir.create(recursive: true);
    await File(_ffmpeg).copy(p.join(ffmpegDir.path, 'ffmpeg.exe'));
    final version = (await PackageInfo.fromPlatform()).version;
    SharedPreferences.setMockInitialValues({
      // Past the first-run tour, the What's new dialog and the tips.
      'onboardingSeenVersion': version,
      'whats_new_last_shown_version': version,
      'onboarding_step': 4,
      'player_library_folder': _media,
      'volume': 0.6,
      // No peers looked for: a security program's warning about one would
      // be in the video.
      'use_dht': false,
      'use_pex': false,
      'use_lpd': false,
    });
    WidgetsApp.debugAllowBannerOverride = false;

    final errorWidgetBuilder = ErrorWidget.builder;
    final onFlutterError = FlutterError.onError;
    final tour = _Tour(tester);
    try {
      await app.main();
      await tour.waitFor(() => find.byType(HomeScreen).evaluate().isNotEmpty,
          const Duration(seconds: 60));
      // The whole main display, as a window: full screen would be the
      // player's own full screen for a video.
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
          windowButtonVisibility: false);
      // A window without a frame keeps an invisible 8-pixel border left,
      // right and below: the desktop showed through it.
      await windowManager.setBounds(const Rect.fromLTWH(-8, 0, 1936, 1088));
      await windowManager.setAlwaysOnTop(true);
      await tour.hold(2500);

      final home = tester.state<HomeScreenState>(find.byType(HomeScreen));
      final controller = home.widget.controller;
      final player = Provider.of<PlayerState>(
          tester.element(find.byType(HomeScreen)),
          listen: false);
      String media(String name) => p.join(_media, name);
      Future<void> menu(String item) async {
        // The now-playing card's menu, not a library card's.
        await tester.tap(find.byTooltip('Track actions').first);
        await tour.hold(600);
        await tester.tap(find.text(item).last);
        await tour.hold(900);
      }

      Future<void> closeSheet() async {
        await tester.tapAt(const Offset(960, 40));
        await tour.hold(700);
      }

      // A torrent of a demo video, seeding: a single file sits right in the
      // folder it is added with, so its data is found and checked.
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
          destinationPath: _media);
      final checked = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(checked) &&
          (torrent?.progress ?? 0) < 0.999) {
        await tour.hold(250);
      }
      await torrentSub.cancel();

      if (_record) await tour.startRecording();

      // Home: a link pasted in.
      tour.mark('home');
      await tour.hold(1200);
      final link = find.byType(TextField).first;
      await tester.tap(link);
      const url = 'https://www.youtube.com/watch?v=C0nv3rtSp1r';
      for (var i = 1; i <= url.length; i += 2) {
        await tester.enterText(link, url.substring(0, i));
        await tour.hold(45);
      }
      await tester.enterText(link, url);
      await tour.hold(1500);
      await tour.shot('1-home');
      await tester.enterText(link, '');
      FocusManager.instance.primaryFocus?.unfocus();

      // The player.
      tour.mark('player');
      home.openPage('player.tab');
      await tour.waitFor(
          () => player.library.length >= 12, const Duration(seconds: 30));
      await player.playFileDirect(media('Neon Rain.mp3'));
      await tour.hold(3200);
      await tour.shot('2-player');

      // A video, with its subtitles.
      tour.mark('video');
      await player.playFileDirect(media('Fractal Dreams.mp4'));
      await tour.hold(3600);
      await tour.shot('3-video-subtitles');

      // The large view.
      tour.mark('large');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(900, 200));
      await mouse.moveTo(const Offset(905, 210));
      await tour.hold(300);
      await tester.tap(find.byTooltip('Large view'));
      await tour.hold(600);
      await mouse.moveTo(const Offset(900, 600));
      await tour.hold(1400);
      await tour.shot('4-large-view');
      await tour.hold(2600);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tour.hold(700);
      await mouse.removePointer();

      // Loop the best part of a song.
      tour.mark('loop');
      await player.playFileDirect(media('Midnight Drive.mp3'));
      await tour.hold(800);
      await player.seek(const Duration(seconds: 58));
      await menu('Loop parts');
      await tester.tap(find.text('Start here'));
      await tour.hold(4200);
      await tester.tap(find.text('End here'));
      await tour.hold(1600);
      await tour.shot('5-loop-parts');
      await closeSheet();
      await tour.hold(1200);

      // Speed.
      tour.mark('speed');
      await menu('Playback speed');
      await tester.tap(find.text('1.5×'));
      await tour.hold(1800);

      // Torrents.
      tour.mark('torrents');
      home.openPage('torrents.tab');
      await tour.hold(3500);
      await tour.shot('6-torrents');

      // The browser.
      tour.mark('browser');
      home.openPage('browser.tab');
      await tour.hold(3000);

      // Colours, light and dark.
      tour.mark('colours');
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
      tour.mark('end');
      await tour.hold(300);
    } finally {
      await tour.stopRecording();
      await File(p.join(_out, 'marks.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(tour.marks));
      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (_) {}
      ErrorWidget.builder = errorWidgetBuilder;
      FlutterError.onError = onFlutterError;
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

class _Tour {
  _Tour(this.tester);

  final WidgetTester tester;
  final marks = <Map<String, Object>>[];
  final _clock = Stopwatch();
  Process? _recorder;

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

  void mark(String id) {
    if (_clock.isRunning) {
      marks.add({'id': id, 't': _clock.elapsedMilliseconds / 1000});
    }
  }

  /// The main display, as it shows: the video is a texture the app's own
  /// screenshots leave black.
  Future<void> shot(String name) async {
    final result = await Process.run(_ffmpeg, [
      '-hide_banner', '-loglevel', 'error', '-y', //
      '-f', 'gdigrab', '-offset_x', '0', '-offset_y', '0',
      '-video_size', '1920x1080', '-draw_mouse', '0', '-i', 'desktop',
      '-frames:v', '1', p.join(_out, '$name.png'),
    ]);
    if (result.exitCode != 0) debugPrint('screenshot failed: ${result.stderr}');
  }

  Future<void> startRecording() async {
    _recorder = await Process.start(_ffmpeg, [
      '-hide_banner', '-loglevel', 'error', '-y', //
      '-f', 'gdigrab', '-framerate', '30', '-offset_x', '0', '-offset_y', '0',
      '-video_size', '1920x1080', '-draw_mouse', '0', '-i', 'desktop',
      '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '14',
      '-pix_fmt', 'yuv420p', p.join(_out, 'tour.mp4'),
    ]);
    _clock.start();
  }

  Future<void> stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;
    recorder.stdin.write('q');
    await recorder.stdin.flush();
    await recorder.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
      recorder.kill();
      return -1;
    });
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
}
