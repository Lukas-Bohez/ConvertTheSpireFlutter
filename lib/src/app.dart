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
  const MyApp({super.key});

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
    try {
      final logs = LogService();
      final settingsStore = SettingsStore();
      final ytExplode = YoutubeExplode();
      _ytExplode = ytExplode;
      final youtube = YouTubeService(yt: ytExplode);
      final ffmpeg = FfmpegService();
      final downloadService = DownloadService(yt: ytExplode, ffmpeg: ffmpeg);
      final convertService = ConvertService(ffmpeg: ffmpeg);
      final installerService = InstallerService();

      // ── New services ──────────────────────────────────────────────
      final youtubeSearcher = YouTubeSearcher(yt: ytExplode);
      final soundcloudSearcher = SoundCloudSearcher();
      final searchService = MultiSourceSearchService(
        youtubeSearcher: youtubeSearcher,
        soundcloudSearcher: soundcloudSearcher,
      );
      final previewPlayer = PreviewPlayerService();
      final playlistService = PlaylistService(yt: ytExplode);
      final bulkImportService = BulkImportService();
      final musicBrainzService = MusicBrainzService();
      final lyricsService = LyricsService();
      final fileOrganizationService = FileOrganizationService();
      final statisticsService = StatisticsService();
      final notificationService = NotificationService();

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
      await controller.init();
      if (mounted) {
        setState(() {
          _controller = controller;
        });
      }
    } catch (e) {
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
          home: _initError != null
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
