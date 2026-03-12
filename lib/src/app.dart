import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, KeyEvent, KeyDownEvent;
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/browser_screen.dart';
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
import 'services/yt_dlp_service.dart';
import 'state/app_controller.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class MyApp extends StatefulWidget {
  final String? mediaKitInitError;
  final WebViewEnvironment? webViewEnvironment;

  const MyApp({super.key, this.mediaKitInitError, this.webViewEnvironment});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  AppController? _controller;
  YoutubeExplode? _ytExplode;
  String? _initError;
  bool _dismissedMediaKitError = false;
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();
  late final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initController();
    if (!kIsWeb && Platform.isWindows) {
      try {
        windowManager.addListener(this);
      } catch (_) {}
    }
    // If MediaKit failed to initialize on Linux, show a clear, copyable
    // dialog instructing the user how to install libmpv instead of
    // crashing silently.
    if (widget.mediaKitInitError != null && Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _dismissedMediaKitError) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Missing dependency'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'libmpv is required for media playback on Linux. '
                  'Install it with your package manager:',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SelectableText(
                    'Ubuntu/Debian:  sudo apt install libmpv1\n'
                    'Fedora:         sudo dnf install mpv-libs\n'
                    'Arch:           sudo pacman -S mpv',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Restart the app after installing.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _dismissedMediaKitError = true;
                  });
                },
                child: const Text('Continue without player'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    _ytExplode?.close();
    _controller?.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        windowManager.isFullScreen().then((isFull) {
          windowManager.setFullScreen(!isFull);
        }).catchError((e) {
          if (kDebugMode) debugPrint('Failed to toggle fullscreen: $e');
        });
      }
    }
  }

  Future<void> _initController() async {
    if (kDebugMode) debugPrint('MyApp: starting controller initialization');
    try {
      final logs = LogService();
      final settingsStore = SettingsStore();
      final ytExplode = YoutubeExplode();
      _ytExplode = ytExplode;
      final youtube = YouTubeService(yt: ytExplode);
      final ffmpeg = FfmpegService();
      final ytDlp = YtDlpService();
      final downloadService =
          DownloadService(yt: ytExplode, ffmpeg: ffmpeg, ytDlp: ytDlp);
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
        fetchPlaylistTracks: (url) =>
            playlistService.getYouTubePlaylistTracks(url),
        onNewTrack: (track) async {
          controller.addSearchResultToQueue(track);
        },
        logs: logs,
      );
      controller = AppController(
        webViewEnvironment: widget.webViewEnvironment,
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
      if (kDebugMode) debugPrint('MyApp: all services created, calling init()');
      await controller.init();
      if (kDebugMode) debugPrint('MyApp: init() completed');
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
  void onWindowClose() async {
    // Called when the user clicks the X button. Dispose WebViews first
    // to avoid WinRT composition DLL unload ordering hangs, then exit.
    if (kDebugMode)
      debugPrint('[App] Window close requested — disposing WebViews...');
    try {
      // Force the BrowserScreen to dispose all controllers.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          BrowserScreen.browserKey.currentState?.disposeAllWebViewControllers();
        } catch (_) {}
      });
      // Give widgets a short moment to run disposals.
      await Future.delayed(const Duration(milliseconds: 120));
    } catch (_) {}
    if (kDebugMode) debugPrint('[App] Exiting now.');
    try {
      exit(0);
    } catch (_) {
      // fallback
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
          home: widget.mediaKitInitError != null && !_dismissedMediaKitError
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text('MediaKit initialization failure',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(widget.mediaKitInitError!,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          if (widget.mediaKitInitError!
                              .contains('Unsupported platform'))
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
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              // Bypass the error and continue without video.
                              setState(() {
                                _dismissedMediaKitError = true;
                              });
                            },
                            child: const Text('Continue without video'),
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
                              const Icon(Icons.error_outline,
                                  size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text('Failed to start',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 8),
                              Text(_initError!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _initError = null;
                                  });
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
                      ? const Scaffold(
                          body: Center(child: CircularProgressIndicator()))
                      : FutureBuilder<SharedPreferences>(
                          future: _prefsFuture,
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const Scaffold(
                                  body: Center(
                                      child: CircularProgressIndicator()));
                            }

                            final prefs = snap.data!;

                            final controller = _controller!;
                            Widget contentChild;
                            if (!controller.onboardingChecked) {
                              contentChild = const Scaffold(
                                body:
                                    Center(child: CircularProgressIndicator()),
                              );
                            } else if (controller.needsOnboarding) {
                              contentChild = OnboardingScreen(
                                onFinish: () async {
                                  await controller.completeOnboarding();
                                },
                                onThemeChanged: (mode) =>
                                    controller.setThemeMode(mode),
                                themeMode: _resolveThemeMode(
                                    controller.settings?.themeMode),
                              );
                            } else {
                              contentChild = MultiProvider(
                                providers: [
                                  ChangeNotifierProvider(
                                      create: (_) => PlayerState(prefs)),
                                  ChangeNotifierProvider.value(
                                      value: controller),
                                ],
                                child: HomeScreen(controller: controller),
                              );
                            }

                            return KeyboardListener(
                              focusNode: _keyboardFocusNode,
                              autofocus: true,
                              onKeyEvent: _handleKey,
                              child: contentChild,
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
