import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    hide SearchResult;

import 'config/build_flags.dart';
import 'config/full_mode_access.dart';
import 'data/browser_db.dart';
import 'features/colour_rewards/colour_reward_service.dart';
import 'screens/browser_screen.dart';
// Use explicit show clauses to avoid ambiguous_import errors:
// home_screen.dart imports PlayerState from player.dart internally.
// Importing player.dart here with its own show clause would expose
// PlayerState from two different source libraries - ambiguous_import.
// The show clauses are kept non-overlapping: HomeScreen only from
// home_screen.dart, PlayerState only from player.dart.
import 'screens/home_screen.dart' show HomeScreen;
import 'screens/onboarding_screen.dart';
import 'screens/player.dart' show PlayerState;
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
import 'services/purchase_service.dart';
import 'services/settings_store.dart';
import 'services/statistics_service.dart';
import 'services/tray_service.dart';
import 'services/watched_playlist_service.dart';
import 'services/youtube_service.dart';
import 'services/yt_dlp_service.dart';
import 'state/app_controller.dart';
import 'vault/vault_bootstrap.dart';
import 'widgets/adaptive_ui_frame.dart';
import 'widgets/global_cursor_overlay.dart';
import 'widgets/tv_file_browser.dart';

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
  bool _dismissedMediaKitError = false;
  late final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 40 << 20;
    _initController();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);

    // Only add the window-manager listener on supported desktop platforms.
    if (!kIsWeb && Platform.isWindows) {
      try {
        windowManager.addListener(this);
      } catch (_) {}
    }

    if (widget.mediaKitInitError != null && !kIsWeb && Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _dismissedMediaKitError) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Missing dependency'),
            // overflow-fix: dialog body can exceed small screen height.
            content: SingleChildScrollView(
              child: Column(
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
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    try {
      _controller?.handleAppLifecycleState(state);
    } catch (_) {}
  }

  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint('MyApp: memory pressure, cleared image cache');
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.f11) return false;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }
    unawaited(
      windowManager.isFullScreen().then((isFs) {
        return windowManager.setFullScreen(!isFs);
      }),
    );
    return true;
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

      // Desktop platforms: resolve yt-dlp path for multi-platform search
      String? resolvedYtDlpPath;
      BiliSearcher? biliSearcher;
      RumbleSearcher? rumbleSearcher;
      DailymotionSearcher? dailymotionSearcher;
      OdyseeSearcher? odyseeSearcher;

      try {
        // Try to resolve yt-dlp from system PATH or app support dir
        // (configuredPath is null at startup since settings load asynchronously)
        resolvedYtDlpPath = await ytDlp.resolveAvailablePath(null);
        if (resolvedYtDlpPath != null) {
          // yt-dlp is available on desktop: instantiate platform-specific searchers
          biliSearcher =
              BiliSearcher(ytDlp: ytDlp, ytDlpPath: resolvedYtDlpPath);
          rumbleSearcher =
              RumbleSearcher(ytDlp: ytDlp, ytDlpPath: resolvedYtDlpPath);
          dailymotionSearcher =
              DailymotionSearcher(ytDlp: ytDlp, ytDlpPath: resolvedYtDlpPath);
          odyseeSearcher =
              OdyseeSearcher(ytDlp: ytDlp, ytDlpPath: resolvedYtDlpPath);
        }
      } catch (_) {
        // yt-dlp unavailable or error resolving - continue without it
      }

      final searchService = MultiSourceSearchService(
        youtubeSearcher: youtubeSearcher,
        soundcloudSearcher: soundcloudSearcher,
        biliSearcher: biliSearcher,
        rumbleSearcher: rumbleSearcher,
        dailymotionSearcher: dailymotionSearcher,
        odyseeSearcher: odyseeSearcher,
      );
      final previewPlayer = PreviewPlayerService();
      final playlistService = PlaylistService(yt: ytExplode, ytDlp: ytDlp, ytDlpPath: resolvedYtDlpPath, logs: logs);
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
      late final WatchedPlaylistService watchedPlaylistService;
      watchedPlaylistService = WatchedPlaylistService(
        fetchPlaylistTracks: (url) =>
            playlistService.getYouTubePlaylistTracks(url),
        onNewTrack: (playlistUrl, track) async {
          final defaultFormat =
              controller.settings?.defaultAudioFormat ?? 'mp3';
          final folderForFormat = await watchedPlaylistService
              .getFolderForPlaylist(playlistUrl, format: defaultFormat);
          final folder = folderForFormat ??
              await watchedPlaylistService.getFolderForPlaylist(playlistUrl);
          controller.addSearchResultToQueue(
            track,
            format: defaultFormat,
            outputFolder: folder?.trim().isNotEmpty == true ? folder : null,
          );
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

      await ColourRewardService.instance.init();

      // Prune old album art cache in background.
      unawaited(albumArtService.pruneOldAlbumArt());

      // Fix: set onSafAccessDenied only ONCE (after controller is fully created)
      // to avoid the earlier assignment being silently overwritten by the later one.
      downloadService.onSafAccessDenied = () async {
        final ctx = _navigatorKey.currentState?.context;
        if (ctx == null || !(ctx.mounted)) return null;

        final choose = await showDialog<bool>(
          context: ctx,
          builder: (dctx) => AlertDialog(
            title: const Text('Folder access lost'),
            // overflow-fix: keep long prompt scroll-safe inside dialog.
            content: const SingleChildScrollView(
              child: Text(
                'The app can no longer access your selected download folder. '
                'Would you like to pick it again? Choosing "No" will use Downloads instead.',
              ),
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

        final chosen = await pickDirectoryPath(
          ctx,
          dialogTitle: 'Select download folder',
        );
        if (chosen == null || chosen.isEmpty) return null;

        try {
          final current = controller.settings;
          if (current != null) {
            await controller
                .saveSettings(current.copyWith(downloadDir: chosen));
          }
        } catch (_) {}

        return chosen;
      };

      if (kDebugMode) debugPrint('MyApp: all services created, calling init()');
      await controller.init();
      unawaited(VaultBootstrap.ensureInitialized());
      if (kDebugMode) debugPrint('MyApp: init() completed');
      if (mounted) {
        setState(() {
          _controller = controller;
        });
        unawaited(_showGithubMigrationNotice());
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

  Future<void> _showGithubMigrationNotice() async {
    if (kIsWeb || !Platform.isAndroid || !kIsGithubRelease) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'github_migration_shown';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final context = _navigatorKey.currentContext;
        if (context == null) return;

        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('One-time setup'),
            content: const Text(
              'This version uses package name com.torrentspire.ai.github. If you cannot install alongside the Play Store version, uninstall the previous GitHub version first. Play Store version is unaffected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Github migration notice skipped: $e');
      }
    }
  }

  @override
  void onWindowClose() async {
    // Only execute close logic on desktop platforms.
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    // Close-to-tray must be a pure hide path. Do not dispose WebViews,
    // kill WebView2 processes, or destroy the window in this branch.
    final shouldMinimiseToTray = _controller?.settings?.minimizeToTrayOnClose ??
        TrayService.shouldMinimiseToTrayOnClose;
    if (TrayService.enabled && shouldMinimiseToTray) {
      if (kDebugMode) {
        debugPrint('[App] Tray mode active; hiding window (skip teardown)');
      }
      try {
        await windowManager.hide();
      } catch (e) {
        if (kDebugMode) debugPrint('[App] windowManager.hide failed: $e');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('[App] Window close requested - disposing WebViews...');
    }

    try {
      final future =
          BrowserScreen.browserKey.currentState?.disposeAllWebViewControllers();
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
          if (kDebugMode) {
            debugPrint('[App] taskkill msedgewebview2 failed: $e');
          }
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
    final listenables = <Listenable>[
      FullModeAccess.instance,
      ColourRewardService.instance
    ];
    final controller = _controller;
    if (controller != null) {
      listenables.add(controller);
    }

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final themeMode = _resolveThemeMode(_controller?.settings?.themeMode);
        final seed = ColourRewardService.instance.equipped.color;
        final lightScheme = ColorScheme.fromSeed(seedColor: seed);
        final darkScheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        );

        final lightTheme = ThemeData.from(
          colorScheme: lightScheme,
          useMaterial3: true,
        ).copyWith(
          iconTheme: IconThemeData(size: 20, color: lightScheme.onSurface),
          appBarTheme: AppBarTheme(
            backgroundColor: lightScheme.surface,
            foregroundColor: lightScheme.onSurface,
            iconTheme: IconThemeData(color: lightScheme.onSurface),
            titleTextStyle: TextStyle(
              color: lightScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: lightScheme.surface,
            selectedItemColor: lightScheme.primary,
            unselectedItemColor: lightScheme.onSurface.withValues(alpha: 0.7),
          ),
        );

        final darkTheme = ThemeData.from(
          colorScheme: darkScheme,
          useMaterial3: true,
        ).copyWith(
          iconTheme: IconThemeData(size: 20, color: darkScheme.onSurface),
          appBarTheme: AppBarTheme(
            backgroundColor: darkScheme.surface,
            foregroundColor: darkScheme.onSurface,
            iconTheme: IconThemeData(color: darkScheme.onSurface),
            titleTextStyle: TextStyle(
              color: darkScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottomNavigationBarTheme: BottomNavigationBarThemeData(
            backgroundColor: darkScheme.surface,
            selectedItemColor: darkScheme.primary,
            unselectedItemColor: darkScheme.onSurface.withValues(alpha: 0.7),
          ),
        );

        return ExcludeFocus(
          excluding: false,
          child: FocusTraversalGroup(
            policy: const _DeadTraversalPolicy(),
            child: MaterialApp(
              navigatorKey: _navigatorKey,
              title: getAppTitle(),
              shortcuts: const <ShortcutActivator, Intent>{},
              actions: const <Type, Action<Intent>>{},
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeMode,
              builder: (context, child) {
                return GlobalCursorOverlay(
                  child:
                      AdaptiveUiFrame(child: child ?? const SizedBox.shrink()),
                );
              },
              home: _buildHome(),
            ),
          ),
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
                Builder(
                    builder: (ctx) => Text('Failed to start',
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

    // Ready - build the actual app.
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
            themeMode: _resolveThemeMode(controller.settings?.themeMode),
          );
        } else {
          contentChild = MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: PurchaseService.instance),
              ChangeNotifierProvider.value(value: FullModeAccess.instance),
              ChangeNotifierProvider(create: (_) => PlayerState(prefs)),
              ChangeNotifierProvider.value(value: controller),
            ],
            child: HomeScreen(controller: controller),
          );
        }

        return contentChild;
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

class _DeadTraversalPolicy extends FocusTraversalPolicy {
  const _DeadTraversalPolicy();

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) =>
      const [];

  @override
  FocusNode? findFirstFocusInDirection(
    FocusNode scope,
    TraversalDirection direction,
  ) =>
      null;

  @override
  bool inDirection(
    FocusNode focusedNode,
    TraversalDirection direction,
  ) =>
      false;

  bool inVerticalGroupOf(FocusNode node) => false;

  bool inHorizontalGroupOf(FocusNode node) => false;

  @override
  bool next(FocusNode node) => false;

  @override
  bool previous(FocusNode node) => false;
}
