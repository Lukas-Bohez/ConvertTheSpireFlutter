import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, KeyEvent, KeyDownEvent;
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform, Process;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

// Use explicit show clauses to avoid ambiguous_import errors:
// home_screen.dart imports PlayerState from player.dart internally.
// Importing player.dart here with its own show clause would expose
// PlayerState from two different source libraries — ambiguous_import.
// The show clauses are kept non-overlapping: HomeScreen only from
// home_screen.dart, PlayerState only from player.dart.
import 'screens/home_screen.dart' show HomeScreen;
import 'screens/player.dart' show PlayerState;

import 'screens/onboarding_screen.dart';
import 'screens/browser_screen.dart';
import 'services/bulk_import_service.dart';
import 'services/convert_service.dart';
import 'services/android_saf.dart';
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
import 'data/browser_db.dart';

class MyApp extends StatefulWidget {
  final String? mediaKitInitError;
  final WebViewEnvironment? webViewEnvironment;

  const MyApp({super.key, this.mediaKitInitError, this.webViewEnvironment});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WindowListener, WidgetsBindingObserver {
  AppController? _controller;
  YoutubeExplode? _ytExplode;
  String? _initError;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final AndroidSaf _androidSaf = AndroidSaf();
  bool _dismissedMediaKitError = false;
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  // Fix: declare as a regular field, initialised in initState, to avoid
  // "accessed before initialization" issues on some platforms.
  FocusNode? _keyboardFocusNode;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
    WidgetsBinding.instance.addObserver(this);
    _initController();

    // Only add the window-manager listener on supported desktop platforms.
    if (!kIsWeb && Platform.isWindows) {
      try {
        windowManager.addListener(this);
      } catch (_) {}
    }

    if (widget.mediaKitInitError != null &&
        !kIsWeb &&
        Platform.isLinux) {
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
                  setState(() => _dismissedMediaKitError = true);
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
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isWindows) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    _ytExplode?.close();
    _controller?.dispose();
    try {
      BrowserDb.close();
    } catch (_) {}
    _keyboardFocusNode?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    try {
      _controller?.handleAppLifecycleState(state);
    } catch (_) {}
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
      final albumArtService = AlbumArtService();
      final fileOrganizationService = FileOrganizationService();
      final statisticsService = StatisticsService();
      final notificationService = NotificationService();

      // WatchedPlaylistService needs a controller reference for callbacks,
      // so we use a late variable with a forward reference.
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

      // Prune old album art cache in background.
      albumArtService.pruneOldAlbumArt();

      // Fix: set onSafAccessDenied only ONCE (after controller is fully created)
      // to avoid the earlier assignment being silently overwritten by the later one.
      downloadService.onSafAccessDenied = () async {
        final ctx = _navigatorKey.currentState?.context;
        if (ctx == null || !(ctx.mounted)) return null;

        final choose = await showDialog<bool>(
          context: ctx,
          builder: (dctx) => AlertDialog(
            title: const Text('Folder access lost'),
            content: const Text(
              'The app can no longer access your selected download folder. '
              'Would you like to pick it again? Choosing "No" will use Downloads instead.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Use Downloads'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Pick folder'),
              ),
            ],
          ),
        );

        if (choose != true) return null;

        final uri = await _androidSaf.pickTree();
        if (uri == null || uri.isEmpty) return null;

        try {
          final current = controller.settings;
          if (current != null) {
            await controller.saveSettings(current.copyWith(downloadDir: uri));
          }
        } catch (_) {}

        return uri;
      };

      if (kDebugMode) debugPrint('MyApp: all services created, calling init()');
      await controller.init();
      if (kDebugMode) debugPrint('MyApp: init() completed');
      if (mounted) {
        setState(() {
          _controller = controller;
        });
      }
    } catch (e, st) {
      debugPrint('MyApp: initialization failed: $e\n$st');
      if (mounted) {
        setState(() {
          _initError = '$e';
        });
      }
    }
  }

  @override
  void onWindowClose() async {
    // Only execute close logic on desktop platforms.
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    if (kDebugMode) {
      debugPrint('[App] Window close requested — disposing WebViews...');
    }

    try {
      final future = BrowserScreen.browserKey.currentState
          ?.disposeAllWebViewControllers();
      if (future != null) {
        await future.timeout(const Duration(seconds: 3), onTimeout: () {
          if (kDebugMode) {
            debugPrint('[App] disposeAllWebViewControllers timed out');
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[App] disposeAllWebViewControllers failed: $e');
      }
    }

    // On Windows, poll for WebView2 helper process to disappear (up to 5 s).
    if (!kIsWeb && Platform.isWindows) {
      const maxWaitMs = 5000;
      const intervalMs = 250;
      var elapsed = 0;
      var gone = false;
      while (elapsed < maxWaitMs) {
        try {
          final listed = await Process.run(
              'tasklist', ['/FI', 'IMAGENAME eq msedgewebview2.exe', '/NH']);
          final out = (listed.stdout?.toString() ?? '').toLowerCase();
          if (!out.contains('msedgewebview2.exe')) {
            gone = true;
            break;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[App] tasklist failed: $e');
          break;
        }
        await Future.delayed(const Duration(milliseconds: intervalMs));
        elapsed += intervalMs;
      }

      if (!gone) {
        try {
          final r = await Process.run(
              'taskkill', ['/F', '/IM', 'msedgewebview2.exe']);
          if (r.exitCode != 0 && kDebugMode) {
            debugPrint(
                '[App] taskkill msedgewebview2 exit=${r.exitCode} stderr=${r.stderr}');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[App] taskkill msedgewebview2 failed: $e');
        }
      }
    }

    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (e) {
      if (kDebugMode) debugPrint('[App] windowManager.destroy failed: $e');
    }

    if (kDebugMode) debugPrint('[App] window manager destroyed; allowing exit');
    try {
      await BrowserDb.close();
    } catch (e) {
      if (kDebugMode) debugPrint('[App] BrowserDb.close failed: $e');
    }
    // Let the host process tear down normally rather than forcing exit(),
    // which could race with WebView2 teardown.
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller ?? Listenable.merge([]),
      builder: (context, _) {
        final themeMode = _resolveThemeMode(_controller?.settings?.themeMode);
        return MaterialApp(
          navigatorKey: _navigatorKey,
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
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    // Show MediaKit error screen (and allow dismissal to continue without video).
    if (widget.mediaKitInitError != null && !_dismissedMediaKitError) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Builder(builder: (ctx) {
                  return Text('MediaKit initialization failure',
                      style: Theme.of(ctx).textTheme.headlineSmall);
                }),
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
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      setState(() => _dismissedMediaKitError = true),
                  child: const Text('Continue without video'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Initialisation error.
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Builder(builder: (ctx) => Text('Failed to start',
                    style: Theme.of(ctx).textTheme.headlineSmall)),
                const SizedBox(height: 8),
                Text(_initError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _initError = null);
                    _initController();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Still loading.
    if (_controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Ready — build the actual app.
    return FutureBuilder<SharedPreferences>(
      future: _prefsFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final prefs = snap.data!;
        final controller = _controller!;

        Widget contentChild;
        if (!controller.onboardingChecked) {
          contentChild = const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (controller.needsOnboarding) {
          contentChild = OnboardingScreen(
            onFinish: controller.completeOnboarding,
            onThemeChanged: (mode) => controller.setThemeMode(mode),
            themeMode:
                _resolveThemeMode(controller.settings?.themeMode),
          );
        } else {
          contentChild = MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => PlayerState(prefs)),
              ChangeNotifierProvider.value(value: controller),
            ],
            child: HomeScreen(controller: controller),
          );
        }

        // Wrap in KeyboardListener for F11 fullscreen toggling.
        // Fix: _keyboardFocusNode is now initialised in initState so it's
        // guaranteed non-null here.
        return KeyboardListener(
          focusNode: _keyboardFocusNode!,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: contentChild,
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