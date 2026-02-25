import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/player.dart';
import 'services/bulk_import_service.dart';
import 'services/convert_service.dart';
import 'services/download_service.dart';
import 'services/ffmpeg_service.dart';
import 'services/file_organization_service.dart';
import 'services/installer_service.dart';
import 'services/log_service.dart';
import 'services/metadata_service.dart';
import 'services/multi_source_search_service.dart';
import 'services/notification_service.dart';
import 'services/playlist_service.dart';
import 'services/preview_player_service.dart';
import 'services/settings_store.dart';
import 'services/statistics_service.dart';
import 'services/watched_playlist_service.dart';
import 'services/youtube_service.dart';
import 'state/app_controller.dart';

class MyApp extends StatefulWidget {
  final String? mediaKitInitError;

  const MyApp({super.key, this.mediaKitInitError});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppController? _controller;
  YoutubeExplode? _ytExplode;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void dispose() {
    _ytExplode?.close();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initController() async {
    debugPrint('MyApp: starting controller initialization');
    try {
      final logs = LogService();
      debugPrint('  created LogService');
      final settingsStore = SettingsStore();
      debugPrint('  created SettingsStore');
      final ytExplode = YoutubeExplode();
      debugPrint('  created YoutubeExplode');
      _ytExplode = ytExplode;
      final youtube = YouTubeService(yt: ytExplode);
      debugPrint('  created YouTubeService');
      final ffmpeg = FfmpegService();
      debugPrint('  created FfmpegService');
      final downloadService = DownloadService(yt: ytExplode, ffmpeg: ffmpeg);
      debugPrint('  created DownloadService');
      final convertService = ConvertService(ffmpeg: ffmpeg);
      debugPrint('  created ConvertService');
      final installerService = InstallerService();
      debugPrint('  created InstallerService');

      // ── New services ──────────────────────────────────────────────
      final youtubeSearcher = YouTubeSearcher(yt: ytExplode);
      debugPrint('  created YouTubeSearcher');
      final soundcloudSearcher = SoundCloudSearcher();
      debugPrint('  created SoundCloudSearcher');
      final searchService = MultiSourceSearchService(
        youtubeSearcher: youtubeSearcher,
        soundcloudSearcher: soundcloudSearcher,
      );
      debugPrint('  created MultiSourceSearchService');
      final previewPlayer = PreviewPlayerService();
      debugPrint('  created PreviewPlayerService');
      final playlistService = PlaylistService(yt: ytExplode);
      debugPrint('  created PlaylistService');
      final bulkImportService = BulkImportService();
      debugPrint('  created BulkImportService');
      final musicBrainzService = MusicBrainzService();
      debugPrint('  created MusicBrainzService');
      final lyricsService = LyricsService();
      debugPrint('  created LyricsService');
      final fileOrganizationService = FileOrganizationService();
      debugPrint('  created FileOrganizationService');
      final statisticsService = StatisticsService();
      debugPrint('  created StatisticsService');
      final notificationService = NotificationService();
      debugPrint('  created NotificationService');

      // WatchedPlaylistService needs callbacks referencing the controller,
      // so we create a placeholder and assign later.
      late final AppController controller;
      final watchedPlaylistService = WatchedPlaylistService(
        fetchPlaylistTracks: (url) => playlistService.getYouTubePlaylistTracks(url),
        onNewTrack: (track) async {
          controller.addSearchResultToQueue(track);
        },
        logs: logs,
      );
      debugPrint('  created WatchedPlaylistService');

      controller = AppController(
        settingsStore: settingsStore,
        youtube: youtube,
        downloadService: downloadService,
        convertService: convertService,
        installerService: installerService,
        logs: logs,
        searchService: searchService,
        previewPlayer: previewPlayer,
        playlistService: playlistService,
        watchedPlaylistService: watchedPlaylistService,
        bulkImportService: bulkImportService,
        musicBrainzService: musicBrainzService,
        lyricsService: lyricsService,
        fileOrganizationService: fileOrganizationService,
        statisticsService: statisticsService,
        notificationService: notificationService,
      );
      debugPrint('  created AppController, calling init()');
      await controller.init();
      debugPrint('  AppController.init() completed');
      if (mounted) {
        setState(() {
          _controller = controller;
        });
      }
    } catch (e, st) {
      debugPrint('MyApp: initialization failed: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() {
          _initError = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller ?? Listenable.merge([]),
      builder: (context, _) {
        final themeMode = _resolveThemeMode(_controller?.settings?.themeMode);
        return MaterialApp(
          title: 'Convert the Spire',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.teal,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: themeMode,
          home: widget.mediaKitInitError != null
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text('MediaKit initialization failure',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(widget.mediaKitInitError!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                                          if (widget.mediaKitInitError!.contains('Unsupported platform'))
                            const Text(
                              'Video playback is not supported on this platform. '
                              'Only audio will be available.',
                              textAlign: TextAlign.center,
                            )
                          else
                            const Text(
                              'The native mpv library could not be found in the APK.\n'
                              'Please follow the README to bundle libmpv or enable split-per-abi.',
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : _initError != null
                  ? Scaffold(
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text('Failed to start', style: Theme.of(context).textTheme.headlineSmall),
                              const SizedBox(height: 8),
                              Text(_initError!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() { _initError = null; });
                                  _initController();
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : _controller == null
                      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                      : FutureBuilder<SharedPreferences>(
                          future: SharedPreferences.getInstance(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Scaffold(body: Center(child: CircularProgressIndicator()));
                        }

                        final prefs = snap.data!;
                        final seen = prefs.getBool('seenOnboarding') ?? false;
                        if (!seen) {
                          // show onboarding once; caller will mark flag when finished
                          return OnboardingScreen(
                            onFinish: () {
                              prefs.setBool('seenOnboarding', true);
                              setState(() {
                                // force rebuild so home screen is shown next
                              });
                            },
                            themeMode: themeMode,
                            onThemeChanged: (mode) {
                              // update app controller settings if available
                              _controller?.setThemeMode(mode);
                            },
                          );
                        }

                        return ChangeNotifierProvider(
                          create: (_) => PlayerState(prefs),
                          child: HomeScreen(controller: _controller!),
                        );
                      },
                    ),
        );
      },
    );
  }

  static ThemeMode _resolveThemeMode(String? mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
