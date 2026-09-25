import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../config/build_flags.dart';
import '../config/full_mode_access.dart';
import '../models/app_languages.dart';
import '../models/app_settings.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../services/ad_service.dart';
import '../services/android_saf.dart';
import '../services/bug_report_service.dart';
import '../services/folder_access_service.dart';
import '../services/ipfs_service.dart';
import '../services/open_request_service.dart';
import '../services/review_service.dart';
import '../services/session_log_service.dart';
import '../services/shortcut_service.dart';
import '../services/tray_service.dart';
import '../services/update_service.dart';
import '../state/app_controller.dart';
import '../theme/app_colors.dart';
import '../utils/folder_label.dart';
import '../utils/l10n.dart';
import '../utils/snack.dart';
import '../vault/screens/torrents_screen.dart';
import '../vault/services/torrent_service.dart';
import '../vault/widgets/torrent_settings_card.dart';
import '../widgets/browser_shell.dart';
import '../widgets/onboarding_tooltip_service.dart';
import '../widgets/quick_links_page.dart';
import '../widgets/quick_links_service.dart';
import '../widgets/tv_file_browser.dart';
import '../widgets/update_banner.dart';
import '../widgets/whats_new_dialog.dart';
import 'browser_screen.dart';
import 'bulk_import_screen.dart';
import 'guide_screen.dart';
import 'player.dart' show PlayerPage, PlayerState, MediaType;
import 'playlist_screen.dart';
import 'search_screen.dart';
import 'statistics_screen.dart';
import 'support_screen.dart';
import 'watched_playlists_screen.dart';

class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// Sliver delegate used to keep the search bar pinned at the top.
class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  final double minExtent;
  @override
  final double maxExtent;
  final Widget child;

  _SearchHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.child,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Clip so content can never paint over the scrollable body below if it
    // ever exceeds the fixed header extent (same defence as the player's
    // pinned header).
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: SizedBox.expand(child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.maxExtent != maxExtent ||
        oldDelegate.minExtent != minExtent;
  }
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static final Uri _buyMeCoffeeUri =
      Uri.parse('https://buymeacoffee.com/orokaconner');

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

  static final Uri _websiteUri = Uri.parse('https://quizthespire.com/');
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _downloadDirController = TextEditingController();
  final TextEditingController _downloadDirMp3Controller =
      TextEditingController();
  final TextEditingController _downloadDirM4aController =
      TextEditingController();
  final TextEditingController _downloadDirMp4Controller =
      TextEditingController();
  final TextEditingController _downloadDirTorrentsController =
      TextEditingController();
  final TextEditingController _workersController = TextEditingController();
  final TextEditingController _retryCountController = TextEditingController();
  final TextEditingController _retryBackoffController = TextEditingController();
  final TextEditingController _ffmpegPathController = TextEditingController();
  final TextEditingController _ytDlpPathController = TextEditingController();
  final TextEditingController _ytCookiesFileController =
      TextEditingController();
  final TextEditingController _rangeFromController = TextEditingController();
  final TextEditingController _rangeToController = TextEditingController();
  final AndroidSaf _androidSaf = AndroidSaf();

  bool _expandPlaylist = false;
  String _downloadFormat = 'mp3';
  String _videoQuality = '1080p';
  int _audioBitrate = 320;
  bool _useFormatSubfolders = true;
  bool _settingsInitialized = false;
  bool _minimizeToTrayOnClose = true;
  bool _sponsorBlockEnabled = false;
  bool _youtubeAuthEnabled = false;
  String _youtubeCookiesFromBrowser = '';
  bool _isRefreshing = false;

  late final TabController _playlistTabController;

  File? _convertFile;
  String _convertTarget = 'mp4';
  bool _converting = false;
  String _androidDownloadUri = '';
  int _selectedPageIndex = 13;
  DateTime? _lastLocalNavigation;

  final GlobalKey<ScaffoldState> _shellScaffoldKey = GlobalKey<ScaffoldState>();
  final List<int> _navHistory = [13];
  int _navHistoryIndex = 0;
  bool _queueOnRight = true;
  int _playQueueViewIndex = 0;

  final OnboardingTooltipService _onboarding = OnboardingTooltipService();
  String? _dismissedBannerRoute;

  UpdateInfo? _updateInfo;
  bool _updateBannerDismissed = false;
  bool _checkUpdatesOnLaunch = true;

  bool _ytDlpVersionChecking = false;
  bool _ytDlpVersionCheckFailed = false;
  bool? _ytDlpIsUpToDate;
  String? _ytDlpCurrentVersion;
  String? _ytDlpLatestVersion;
  DateTime? _ytDlpLastChecked;

  TrayService? _trayService;

  StreamSubscription<void>? _openRequestSub;

  String _previewPreset = '25';
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  bool _isNarrowLayout(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  final Set<int> _visitedPages = {13};

  int _addRangeFrom = 1;
  int _addRangeTo = 1;

  @override
  void initState() {
    super.initState();
    _playlistTabController = TabController(length: 2, vsync: this);

    _onboarding.init().then((_) {
      if (mounted) setState(() {});
    });

    _initDesktopFeatures();

    // Show what changed after the app updated itself under the user.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowWhatsNew());
    });

    // Files and links opened with the app. Those it was started for are
    // already waiting; later ones announce themselves.
    _openRequestSub = OpenRequestService.instance.onArrived
        .listen((_) => unawaited(_handleOpenRequests(bringToFront: true)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleOpenRequests());
    });

    try {
      _selectedPageIndex = widget.controller.activeTabIndex;
    } catch (_) {}

    if (kDebugMode) {
      debugPrint(
          '[NAV] QuickLinks routeToIndex keys: ${QuickLinksService.routeToIndex.keys.join(', ')}');
    }

    if (!kPlayStoreBuild) {
      UpdateService.isCheckOnLaunchEnabled().then((v) {
        if (mounted) setState(() => _checkUpdatesOnLaunch = v);
      });

      _checkForUpdate();
    } else {
      _checkUpdatesOnLaunch = false;
    }

    if (!_isAndroid) {
      unawaited(_checkYtDlpUpdateStatus());
    }
  }

  Future<void> _checkYtDlpUpdateStatus() async {
    if (_isAndroid) return;
    if (!mounted) return;
    setState(() {
      _ytDlpVersionChecking = true;
      _ytDlpVersionCheckFailed = false;
    });

    try {
      final settings = widget.controller.settings;
      final currentVersion =
          await widget.controller.downloadService.ytDlp.getVersion(
        configuredPath: settings?.ytDlpPath,
      );

      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest',
        ),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = (data['tag_name'] ?? '').toString();
        final current = (currentVersion ?? 'unknown').trim();

        final upToDate = current.isNotEmpty &&
            current != 'unknown' &&
            (current == latestTag || current.compareTo(latestTag) >= 0);

        if (!mounted) return;
        setState(() {
          _ytDlpCurrentVersion = currentVersion;
          _ytDlpLatestVersion = latestTag;
          _ytDlpIsUpToDate = upToDate;
          _ytDlpLastChecked = DateTime.now();
          _ytDlpVersionCheckFailed = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _ytDlpCurrentVersion = currentVersion;
          _ytDlpIsUpToDate = null;
          _ytDlpVersionCheckFailed = true;
          _ytDlpLastChecked = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('Version check failed: $e');
      if (!mounted) return;
      setState(() {
        _ytDlpIsUpToDate = null;
        _ytDlpVersionCheckFailed = true;
        _ytDlpLastChecked = DateTime.now();
      });
    } finally {
      if (!mounted) return;
      setState(() => _ytDlpVersionChecking = false);
    }
  }

  Future<void> _checkForUpdate({bool force = false}) async {
    try {
      if (kPlayStoreBuild) return;
      if (!_checkUpdatesOnLaunch && !force) return;
      final info = await UpdateService.checkForUpdate();
      if (info == null) return;
      final shouldShow =
          await UpdateService.shouldShowBanner(info.latestVersion);
      if (mounted) {
        setState(() {
          _updateInfo = info;
          _updateBannerDismissed = !shouldShow;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: update check failed: $e');
    }
  }

  void _initDesktopFeatures() {
    if (kIsWeb) return;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;

    _trayService = TrayService(
      shouldMinimiseToTray: () => _minimizeToTrayOnClose,
    );

    _trayService!.onTrayQuit = () async {
      // This path calls exit(0) below, which can (and per the missing
      // session logs, apparently does) win the race against app.dart's
      // onWindowClose() - which also flushes the session log, but only
      // after up to ~5s of WebView2 process polling. Flush here too, so
      // whichever path wins the race, the log is already on disk.
      try {
        await SessionLogService.instance.flush('normal_exit');
      } catch (_) {}
      try {
        await BrowserScreen.browserKey.currentState
            ?.disposeAllWebViewControllers();
      } catch (_) {}
      try {
        await _trayService?.destroy();
      } catch (_) {}
      exit(0);
    };

    _trayService!.onTrayShow = () {};

    _trayService!.init().catchError((e) {
      debugPrint('HomeScreen: tray init failed: $e');
    });

    ShortcutService.ensureDesktopShortcut().catchError((e) {
      debugPrint('HomeScreen: desktop shortcut failed: $e');
    });
  }

  @override
  void dispose() {
    _openRequestSub?.cancel();
    _trayService?.destroy();
    _playlistTabController.dispose();
    _urlController.dispose();
    _downloadDirController.dispose();
    _downloadDirMp3Controller.dispose();
    _downloadDirM4aController.dispose();
    _downloadDirMp4Controller.dispose();
    _downloadDirTorrentsController.dispose();
    _workersController.dispose();
    _retryCountController.dispose();
    _retryBackoffController.dispose();
    _ffmpegPathController.dispose();
    _ytDlpPathController.dispose();
    _ytCookiesFileController.dispose();
    _rangeFromController.dispose();
    _rangeToController.dispose();
    super.dispose();
  }

  Widget _buildPageContent(int index, AppSettings? settings) {
    switch (index) {
      case 0:
        return _buildSearchTab(settings);
      case 1:
        return SearchScreen(
          key: const ValueKey('multi-search'),
          searchService: widget.controller.searchService,
          previewPlayer: widget.controller.previewPlayer,
          onDownload: (result, format) async {
            widget.controller.addSearchResultToQueue(result, format: format);
            unawaited(widget.controller.downloadAll());
          },
        );
      case 2:
        return BrowserScreen(
          key: BrowserScreen.browserKey,
          onAddToQueue: (result) {
            widget.controller.addSearchResultToQueue(result);
            widget.controller.downloadAll();
          },
          onDownloadPlaylist: (url) => _openPlaylistManager(url),
        );
      case 3:
        return _buildQueueTab();
      case 4:
        return _buildPlaylistsTab();
      case 5:
        return BulkImportScreen(
          key: const ValueKey('bulk-import'),
          importService: widget.controller.bulkImportService,
          onProcess: (queries, format) =>
              widget.controller.processBulkImport(queries, format: format),
        );
      case 6:
        return StatisticsScreen(
          key: const ValueKey('statistics'),
          statisticsService: widget.controller.statisticsService,
        );
      case 7:
        return _buildSettingsTab(settings);
      case 8:
        return const SupportScreen(
          key: ValueKey('support'),
        );
      case 9:
        return _buildConvertTab(settings);
      case 10:
        return _buildLogsTab();
      case 11:
        final tm = _resolveThemeMode(widget.controller.settings?.themeMode);
        return GuideScreen(
          key: const ValueKey('guide'),
          themeMode: tm,
          onThemeChanged: (mode) => widget.controller.setThemeMode(mode),
        );
      case 12:
        return const PlayerPage(key: ValueKey('player-player'));
      case 13:
        return QuickLinksPage(
          key: const ValueKey('quick-links-home'),
          onNavigate: (route) {
            if (route == 'rate.app') {
              unawaited(ReviewService.openStoreListing());
              return;
            }
            final idx = QuickLinksService.routeToIndex[route];
            if (idx != null) _navigateToPage(idx);
          },
          onDownload: (result, format, quality) async {
            widget.controller.addSearchResultToQueue(
              result,
              format: format,
              videoQuality: quality,
            );
            unawaited(widget.controller.downloadAll());
            _navigateToPage(3); // show queue
          },
          onPlaylistDetected: (url, format, quality) =>
              _openPlaylistManager(url, format: format, quality: quality),
          getYtDlpVersion: () async {
            final settings = widget.controller.settings;
            return await widget.controller.downloadService.ytDlp
                .getVersion(configuredPath: settings?.ytDlpPath);
          },
          downloadFolder: _isAndroid
              ? _androidDownloadUri
              : (widget.controller.settings?.downloadDir ?? ''),
          onPickDownloadFolder: () async {
            final settings = widget.controller.settings;
            if (settings != null) {
              await _pickDownloadFolder(settings);
            }
          },
        );
      case 14:
        return TorrentsScreen(
          key: const ValueKey('torrents'),
          onOpenSettingsTab: () => _navigateToPage(7),
        );
      default:
        return _buildSearchTab(settings);
    }
  }

  /// Loads [url] in the Playlist Manager and compares it with the download
  /// folder, so only the songs that are not there yet get downloaded.
  void _openPlaylistManager(String url,
      {String? format, String quality = 'best'}) {
    final s = widget.controller.settings;
    if (s != null && !_ensureDownloadFolder(s)) return;
    widget.controller.pendingPlaylistRequest.value = PendingPlaylistRequest(
      url: url,
      folder: s?.downloadDir ?? '',
      format: format ?? s?.defaultAudioFormat ?? 'mp3',
      quality: quality,
    );
    _playlistTabController.index = 0; // Playlist Manager, not Watched
    _navigateToPage(4); // Playlists tab
  }

  // -- Navigation helpers --------------------------------------------------

  bool get _canGoBack => _navHistoryIndex > 0;
  bool get _canGoForward => _navHistoryIndex < _navHistory.length - 1;

  static const int _homePageIndex = 13;

  /// A natural break for a full-screen ad: a conversion finished, or the user
  /// came back to Home from a section. Play build only; [AdService] also
  /// skips Android TV and keeps ads a few minutes apart. Never while music or
  /// a video plays, so an ad's sound does not cut in.
  void _maybeShowBreakAd() {
    if (!kPlayStoreBuild) return;
    if (context.read<PlayerState>().isPlaying) return;
    unawaited(AdService.instance.maybeShowInterstitialAtBreak());
  }

  void _navigateToPage(int index) {
    if (index < 0 || index > 14) return;
    if (!isTabVisibleInCurrentBuild(index)) return;
    if (index == _selectedPageIndex) return;
    if (_selectedPageIndex == 14 && index != 14) {
      unawaited(widget.controller.pullVaultSettingsIntoHost());
    }
    if (index == 14) {
      unawaited(widget.controller.pushHostSettingsToVault());
    }
    if (kDebugMode) {
      debugPrint('[NAV] _navigateToPage: $_selectedPageIndex -> $index');
    }
    setState(() {
      if (_navHistoryIndex < _navHistory.length - 1) {
        _navHistory.removeRange(_navHistoryIndex + 1, _navHistory.length);
      }
      _navHistory.add(index);
      _navHistoryIndex = _navHistory.length - 1;
      _selectedPageIndex = index;
      _visitedPages.add(index);
    });
    AdService.instance.registerInteraction();
    try {
      widget.controller.switchToTab(index);
    } catch (_) {}
    _lastLocalNavigation = DateTime.now();
    if (index == _homePageIndex) _maybeShowBreakAd();
  }

  void _goBack() {
    if (!_canGoBack) return;
    AdService.instance.registerInteraction();
    setState(() {
      _navHistoryIndex--;
      _selectedPageIndex = _navHistory[_navHistoryIndex];
      _visitedPages.add(_selectedPageIndex);
    });
    try {
      widget.controller.switchToTab(_selectedPageIndex);
    } catch (_) {}
    if (_selectedPageIndex == _homePageIndex) _maybeShowBreakAd();
  }

  void _goForward() {
    if (!_canGoForward) return;
    AdService.instance.registerInteraction();
    setState(() {
      _navHistoryIndex++;
      _selectedPageIndex = _navHistory[_navHistoryIndex];
      _visitedPages.add(_selectedPageIndex);
    });
    try {
      widget.controller.switchToTab(_selectedPageIndex);
    } catch (_) {}
  }

  /// Tab index of the browser, used to decide what the refresh button does.
  static const int _browserTabIndex = 2;

  Future<void> _maybeShowWhatsNew() async {
    final version = widget.controller.currentAppVersion;
    if (version == null || !mounted) return;
    if (widget.controller.needsOnboarding) return;
    await WhatsNewDialog.maybeShow(
      context,
      version,
      freshInstall: widget.controller.isFreshInstall,
    );
  }

  /// Opens a prefilled GitHub issue so reports arrive with a version,
  /// a platform and the tail of the log already attached.
  Future<void> _reportBug() async {
    final url = await BugReportService.buildIssueUrl();
    if (!mounted) return;
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        Snack.show(context, context.l10n.couldNotOpenBrowser,
            level: SnackLevel.error);
      }
    } catch (e) {
      if (mounted) {
        Snack.show(context, context.l10n.couldNotOpenBrowser2(e),
            level: SnackLevel.error);
      }
    }
  }

  Future<void> _refreshApp() async {
    // In the browser, refresh means "reload this page" - it is the same
    // button people use in every other browser (issue #7).
    if (_selectedPageIndex == _browserTabIndex && BrowserScreen.reloadPage()) {
      return;
    }
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await widget.controller.refreshAll();
      if (mounted) {
        Snack.show(context, context.l10n.appRefreshedSuccessfully,
            level: SnackLevel.info);
      }
    } catch (e) {
      if (mounted) {
        Snack.show(context, context.l10n.refreshFailed(e), level: SnackLevel.error);
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _navigateHome() => _navigateToPage(13);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        context.watch<FullModeAccess>();
        final settings = widget.controller.settings;
        if (settings != null && !_settingsInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _initSettings(settings);
          });
        }

        // Keep local index in sync with controller, but avoid feedback bounce.
        final ctrlIndex = widget.controller.activeTabIndex;
        final recentLocalNav = _lastLocalNavigation != null &&
            DateTime.now().difference(_lastLocalNavigation!).inMilliseconds <
                600;
        if (!recentLocalNav && ctrlIndex != _selectedPageIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedPageIndex = ctrlIndex;
              _visitedPages.add(ctrlIndex);
            });
          });
        }

        _visitedPages.add(_selectedPageIndex);

        final shell = BrowserShell(
          key: BrowserShell.shellKey,
          scaffoldKey: _shellScaffoldKey,
          currentIndex: _selectedPageIndex,
          queueWidget: _buildQueueTab(),
          onNavigate: (route) {
            if (kDebugMode) debugPrint('[NAV] requested route: "$route"');
            if (route == 'home') {
              _navigateHome();
              return;
            }

            const routeAliases = <String, String>{
              'player': 'player.tab',
              'search': 'search.tab',
              'browser': 'browser.tab',
              'downloads': 'torrents.tab',
              'settings': 'settings.tab',
              'files': 'bulkimport.tab',
            };

            final normalizedRoute = routeAliases[route.toLowerCase()] ?? route;

            var idx = QuickLinksService.routeToIndex[normalizedRoute];

            if (idx == null && !normalizedRoute.endsWith('.tab')) {
              idx = QuickLinksService.routeToIndex['$normalizedRoute.tab'];
            }

            if (idx == null) {
              final lower = normalizedRoute.toLowerCase();
              for (final entry in QuickLinksService.indexToTitle.entries) {
                if (entry.value.toLowerCase() == lower) {
                  idx = entry.key;
                  break;
                }
              }
            }

            if (idx != null) {
              if (kDebugMode) {
                debugPrint('[NAV] resolved "$normalizedRoute" -> $idx');
              }
              _navigateToPage(idx);
            } else {
              if (kDebugMode) {
                debugPrint(
                    '[NAV] WARNING: no index for route "$normalizedRoute"');
              }
            }
          },
          onBack: _canGoBack ? _goBack : null,
          onForward: _canGoForward ? _goForward : null,
          onRefresh: _refreshApp,
          isRefreshing: _isRefreshing,
          canGoBack: _canGoBack,
          canGoForward: _canGoForward,
          queueOnRight: _queueOnRight,
          queueCount: widget.controller.queue.length,
          onHome: _navigateHome,
          onOpenUrl: openBrowserWith,
          onUrlEditingStart: () => BrowserScreen.pauseCursor(),
          onUrlEditingEnd: () => BrowserScreen.resumeCursor(),
          child: _buildPageWithBanner(settings),
        );

        final popWrapped = PopScope(
          canPop: _selectedPageIndex == 13,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _selectedPageIndex != 13) {
              AdService.instance.registerInteraction();
              setState(() => _selectedPageIndex = 13);
              _maybeShowBreakAd();
            }
          },
          child: shell,
        );

        if (!kIsWeb &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
          return CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () {
                try {
                  context.read<PlayerState>().togglePlay();
                } catch (_) {}
              },
              const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () {
                try {
                  context.read<PlayerState>().next();
                } catch (_) {}
              },
              const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () {
                try {
                  context.read<PlayerState>().previous();
                } catch (_) {}
              },
              const SingleActivator(LogicalKeyboardKey.space, control: true):
                  () {
                try {
                  context.read<PlayerState>().togglePlay();
                } catch (_) {}
              },
            },
            child: popWrapped,
          );
        }

        return popWrapped;
      },
    );
  }

  Widget _buildPageWithBanner(AppSettings? settings) {
    final route = QuickLinksService.indexToRoute[_selectedPageIndex];
    final showBanner = route != null &&
        _onboarding.step < 4 &&
        !_onboarding.hasVisitedScreen(route) &&
        _dismissedBannerRoute != route;
    final description = route != null
        ? OnboardingTooltipService.screenDescription(context.l10n, route)
        : null;

    final stack = IndexedStack(
      index: _selectedPageIndex,
      children: List.generate(15, (i) {
        if (!_visitedPages.contains(i)) {
          return const SizedBox.shrink();
        }
        return _buildPageContent(i, settings);
      }),
    );

    if (!kPlayStoreBuild && _updateInfo != null && !_updateBannerDismissed) {
      return Column(
        children: [
          UpdateBanner(
            info: _updateInfo!,
            onDismiss: () async {
              await UpdateService.dismissBanner(_updateInfo!.latestVersion);
              if (mounted) setState(() => _updateBannerDismissed = true);
            },
            onDownload: () {
              String url = _updateInfo!.releaseUrl;
              if (!kIsWeb) {
                if (Platform.isWindows &&
                    _updateInfo!.windowsAssetUrl.isNotEmpty) {
                  url = _updateInfo!.windowsAssetUrl;
                } else if (Platform.isAndroid &&
                    _updateInfo!.androidAssetUrl.isNotEmpty) {
                  url = _updateInfo!.androidAssetUrl;
                } else if (Platform.isLinux &&
                    _updateInfo!.linuxAssetUrl.isNotEmpty) {
                  url = _updateInfo!.linuxAssetUrl;
                }
              }
              if (url.isNotEmpty) {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
          ),
          if (showBanner && description != null)
            OnboardingBanner(
              message: description,
              onDismiss: () {
                _onboarding.markScreenVisited(route);
                if (mounted) setState(() => _dismissedBannerRoute = route);
              },
            ),
          Expanded(child: stack),
        ],
      );
    }

    if (showBanner && description != null) {
      return Column(
        children: [
          OnboardingBanner(
            message: description,
            onDismiss: () {
              _onboarding.markScreenVisited(route);
              if (mounted) setState(() => _dismissedBannerRoute = route);
            },
          ),
          Expanded(child: stack),
        ],
      );
    }

    return stack;
  }

  Future<void> _initSettings(AppSettings settings) async {
    setState(() {
      if (_isAndroid) {
        _androidDownloadUri = settings.downloadDir.startsWith('content://')
            ? settings.downloadDir
            : '';
        _downloadDirController.text = _androidDownloadUri.isNotEmpty
            ? _formatAndroidFolderLabel(settings.downloadDir)
            : context.l10n.notSet;
      } else {
        _downloadDirController.text = settings.downloadDir;
      }
      _workersController.text = settings.maxWorkers.toString();
      _retryCountController.text = settings.retryCount.toString();
      _retryBackoffController.text = settings.retryBackoffSeconds.toString();
      _ffmpegPathController.text = settings.ffmpegPath ?? '';
      _ytDlpPathController.text = settings.ytDlpPath ?? '';
      _ytCookiesFileController.text = settings.youtubeCookiesFile ?? '';
      _expandPlaylist = settings.previewExpandPlaylist;
      _downloadFormat = settings.defaultAudioFormat;
      _videoQuality = settings.preferredVideoQuality;
      _audioBitrate = settings.preferredAudioBitrate;
      _useFormatSubfolders = settings.createFormatSubfolders;
      _downloadDirMp3Controller.text = settings.downloadDirMp3 ?? '';
      _downloadDirM4aController.text = settings.downloadDirM4a ?? '';
      _downloadDirMp4Controller.text = settings.downloadDirMp4 ?? '';
      _downloadDirTorrentsController.text = settings.downloadDirTorrents ?? '';
      _sponsorBlockEnabled = settings.sponsorBlockEnabled;
      _youtubeAuthEnabled = settings.youtubeAuthEnabled;
      _youtubeCookiesFromBrowser = settings.youtubeCookiesFromBrowser?.trim() ??
          _defaultCookiesFromBrowser();
      _minimizeToTrayOnClose = settings.minimizeToTrayOnClose;
      TrayService.shouldMinimiseToTrayOnClose = _minimizeToTrayOnClose;
      _settingsInitialized = true;
    });

    if (!_isAndroid) {
      unawaited(_checkYtDlpUpdateStatus());
    }

    // Only check SAF folder writability if we have a SAF URI.
    // Filesystem paths are assumed writable if they were selected via the picker.
    if (_isAndroid && _androidDownloadUri.isNotEmpty) {
      final writable = await FolderAccessService.ensureSafeFolderIsWritable(
        context,
        _androidDownloadUri,
      );
      if (!writable && mounted) {
        setState(() {
          _androidDownloadUri = '';
          _downloadDirController.text = context.l10n.notSet;
        });
      }
    }

    try {
      widget.controller.downloadService.onSafAccessDenied = () async {
        if (!mounted) return null;

        final choose = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(context.l10n.folderAccessLost),
            // overflow-fix: long dialog prompt can clip on small-screen devices.
            content: SingleChildScrollView(
              child: Text(
                context.l10n.appCanNoLongerAccess,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.l10n.useDownloads),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.l10n.pickFolder),
              ),
            ],
          ),
        );

        if (choose != true) return null;

        final chosen = await pickDirectoryPath(
          context,
          dialogTitle: context.l10n.selectDownloadFolder,
        );
        if (chosen == null || chosen.isEmpty) return null;

        final current = widget.controller.settings;
        if (current != null) {
          await widget.controller
              .saveSettings(current.copyWith(downloadDir: chosen));
        }

        if (!mounted) return chosen;
        setState(() {
          _androidDownloadUri = chosen.startsWith('content://') ? chosen : '';
          _downloadDirController.text = _androidDownloadUri.isNotEmpty
              ? _formatAndroidFolderLabel(chosen)
              : context.l10n.notSet;
        });
        Snack.show(context, context.l10n.downloadFolderUpdated, level: SnackLevel.info);
        return chosen;
      };
    } catch (_) {}
  }

  Future<void> openBrowserWith(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final lower = trimmed.toLowerCase();

    if (lower.startsWith('magnet:')) {
      unawaited(_openTorrentLink(trimmed));
      _navigateToPage(14);
      return;
    }

    if (lower.startsWith('ipfs://') || lower.startsWith('ipns://')) {
      final resolved = await IpfsService.resolveUrl(trimmed);
      if (!mounted) return;
      _navigateToPage(2);
      BrowserScreen.navigate(resolved);
      return;
    }

    _navigateToPage(2);
    BrowserScreen.navigate(trimmed);
  }

  /// Opens what the app was asked to open from outside: a magnet link or a
  /// .torrent in Torrents, a song or a video in the player. [bringToFront]
  /// is for a request sent while the app runs, possibly hidden in the tray.
  Future<void> _handleOpenRequests({bool bringToFront = false}) async {
    if (!mounted) return;
    if (bringToFront && _isDesktopPlatform) {
      unawaited(_bringWindowToFront());
    }
    final player = context.read<PlayerState>();
    for (final request in OpenRequestService.instance.takeAll()) {
      if (!mounted) return;
      switch (request.kind) {
        case OpenRequestKind.magnet:
          _navigateToPage(14);
          await _openTorrentLink(request.target);
        case OpenRequestKind.torrentFile:
          _navigateToPage(14);
          var path = request.target;
          if (path.startsWith('content://')) {
            // A .torrent from a file manager: read it through Android.
            String? copied;
            try {
              copied = await _androidSaf.copyToTemp(uri: path);
            } catch (e) {
              debugPrint('Could not read opened torrent $path: $e');
            }
            if (copied == null) {
              if (mounted) {
                Snack.show(context, context.l10n.unsupportedTorrentLink,
                    level: SnackLevel.warning);
              }
              continue;
            }
            path = copied;
          }
          await _openTorrentLink(path);
        case OpenRequestKind.media:
          _navigateToPage(12);
          await player.openExternalFile(request.target,
              name: request.name, isVideo: request.isVideo);
      }
    }
  }

  Future<void> _bringWindowToFront() async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('Could not bring the window forward: $e');
    }
  }

  Future<void> _openTorrentLink(String url) async {
    final lower = url.toLowerCase();
    try {
      if (lower.startsWith('magnet:')) {
        await TorrentService.instance.addTorrentFromMagnetLink(url);
        if (mounted) {
          Snack.show(context, context.l10n.magnetLinkAddedTorrents,
              level: SnackLevel.info);
        }
        return;
      }

      String localPath = url;
      if (lower.startsWith('file://')) {
        localPath = Uri.parse(url).toFilePath();
      }
      final localFile = File(localPath);
      if (await localFile.exists()) {
        await TorrentService.instance.addTorrentFromTorrentFile(localPath);
        if (mounted) {
          Snack.show(context, context.l10n.torrentFileAdded, level: SnackLevel.info);
        }
        return;
      }

      final uri = Uri.tryParse(url);
      if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        final fileName = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.last
            : 'downloaded.torrent';
        final tempFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}vts_${DateTime.now().millisecondsSinceEpoch}_$fileName',
        );
        await tempFile.writeAsBytes(response.bodyBytes, flush: true);
        await TorrentService.instance.addTorrentFromTorrentFile(tempFile.path);
        if (mounted) {
          Snack.show(context, context.l10n.torrentLinkAdded, level: SnackLevel.info);
        }
        return;
      }

      if (mounted) {
        Snack.show(context, context.l10n.unsupportedTorrentLink,
            level: SnackLevel.warning);
      }
    } on TorrentAlreadyExistsException catch (e) {
      if (mounted) {
        Snack.show(context, context.l10n.torrentAlreadyExists(e.torrentId),
            level: SnackLevel.info);
      }
    } catch (e) {
      if (mounted) {
        Snack.show(context, context.l10n.failedAddTorrent(e),
            level: SnackLevel.error);
      }
    }
  }

  String _defaultCookiesFromBrowser() {
    if (kIsWeb) return '';
    if (Platform.isWindows) return 'edge';
    if (Platform.isMacOS) return 'safari';
    if (Platform.isLinux) return 'firefox';
    return '';
  }

  List<String> _availableCookieBrowsers() {
    if (kIsWeb) return const <String>[];
    if (Platform.isWindows) {
      return const <String>['edge', 'chrome', 'firefox', 'brave'];
    }
    if (Platform.isMacOS) {
      return const <String>['safari', 'chrome', 'firefox', 'edge', 'brave'];
    }
    if (Platform.isLinux) {
      return const <String>['firefox', 'chrome', 'chromium', 'brave', 'edge'];
    }
    return const <String>[];
  }

  Future<void> _openYouTubeSignInExternal() async {
    final launched = await launchUrl(
      Uri.parse(
        'https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/',
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      Snack.show(context, context.l10n.couldNotOpenBrowserSign,
          level: SnackLevel.error);
      return;
    }
    if (mounted) {
      Snack.show(
        context,
        context.l10n.signSelectedBrowserThenSave,
        level: SnackLevel.info,
        duration: const Duration(seconds: 5),
      );
    }
  }

  String _formatAndroidFolderLabel(String uriString) {
    if (uriString.trim().isEmpty) return context.l10n.notSet;
    return friendlyFolderLabel(uriString);
  }

  bool get _hasAndroidFolder {
    if (_isAndroid) {
      return _androidDownloadUri.isNotEmpty;
    }
    final value = _downloadDirController.text.trim();
    return value.isNotEmpty && value != context.l10n.notSet;
  }

  Future<void> _pickAndroidFolder(AppSettings settings) async {
    final chosen = await pickDirectoryPath(
      context,
      dialogTitle: context.l10n.selectDownloadFolder,
    );
    if (chosen == null || chosen.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _androidDownloadUri = chosen;
      _downloadDirController.text = _formatAndroidFolderLabel(chosen);
    });
    await widget.controller
        .saveSettings(settings.copyWith(downloadDir: chosen));
    if (mounted) {
      Snack.show(context, context.l10n.downloadFolderUpdated, level: SnackLevel.info);
    }
  }

  Future<void> _pickDownloadFolder(AppSettings settings) async {
    if (_isAndroid) {
      await _pickAndroidFolder(settings);
      return;
    }

    final result = await pickDirectoryPath(
      context,
      dialogTitle: context.l10n.selectDownloadFolder,
    );
    if (result == null || !mounted) return;

    setState(() {
      _downloadDirController.text = result;
    });

    await widget.controller
        .saveSettings(settings.copyWith(downloadDir: result));
    if (mounted) {
      Snack.show(context, context.l10n.downloadFolderUpdated, level: SnackLevel.info);
    }
  }

  Future<void> _pickFormatDownloadFolder(
      AppSettings settings, String format) async {
    final selected = await pickDirectoryPath(
      context,
      dialogTitle: context.l10n.selectDownloadFolder,
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() {
      if (format == 'mp3') {
        _downloadDirMp3Controller.text = selected;
      } else if (format == 'm4a') {
        _downloadDirM4aController.text = selected;
      } else if (format == 'mp4') {
        _downloadDirMp4Controller.text = selected;
      } else if (format == 'torrent') {
        _downloadDirTorrentsController.text = selected;
      }
    });

    await widget.controller.saveSettings(
      settings.copyWith(
        downloadDirMp3: _downloadDirMp3Controller.text.trim().isEmpty
            ? null
            : _downloadDirMp3Controller.text.trim(),
        downloadDirM4a: _downloadDirM4aController.text.trim().isEmpty
            ? null
            : _downloadDirM4aController.text.trim(),
        downloadDirMp4: _downloadDirMp4Controller.text.trim().isEmpty
            ? null
            : _downloadDirMp4Controller.text.trim(),
        downloadDirTorrents: _downloadDirTorrentsController.text.trim().isEmpty
            ? null
            : _downloadDirTorrentsController.text.trim(),
      ),
    );
    if (mounted) {
      Snack.show(context, context.l10n.formatFolderUpdated, level: SnackLevel.info);
    }
  }

  Future<void> _openAndroidFolder(AppSettings settings) async {
    final currentFolder = _androidDownloadUri;
    if (currentFolder.isEmpty || currentFolder == context.l10n.notSet) return;

    final ok = await _androidSaf.openTree(currentFolder);
    if (!ok && mounted) {
      Snack.show(context, context.l10n.couldNotOpenSelectedFolder,
          level: SnackLevel.error);
    }
  }

  Future<void> _clearAndroidFolder(AppSettings settings) async {
    setState(() {
      _androidDownloadUri = '';
      _downloadDirController.text = context.l10n.notSet;
    });
    await widget.controller.saveSettings(settings.copyWith(downloadDir: ''));
  }

  // -- Search tab ---------------------------------------------------------

  Widget _buildSearchTab(AppSettings? settings) {
    final isNarrow = _isNarrowLayout(context);
    final youtubeEnabled = isYouTubeConversionEnabledInCurrentBuild;

    // Keep the top search row pinned while the rest of the UI scrolls.
    final searchHeader = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: context.l10n.youtubeUrl,
                border: const OutlineInputBorder(),
                hintText: context.l10n.enterPasteYoutubeUrl,
                prefixIcon: const Icon(Icons.link),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: youtubeEnabled
                            ? () {
                                setState(() => _urlController.clear());
                              }
                            : null,
                        tooltip: context.l10n.clearUrl,
                      )
                    : null,
              ),
              onChanged: (value) => setState(() {}),
              enabled: youtubeEnabled,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.content_paste),
            onPressed: youtubeEnabled
                ? () async {
                    final clipboardData = await Clipboard.getData('text/plain');
                    if (!mounted) return;
                    if (clipboardData?.text != null) {
                      setState(
                          () => _urlController.text = clipboardData!.text!);
                    }
                  }
                : null,
            tooltip: context.l10n.pasteFromClipboard,
          ),
        ],
      ),
    );

    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _SearchHeaderDelegate(
            minExtent: 80,
            maxExtent: 80,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 2,
              child: searchHeader,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                if (!youtubeEnabled)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.block,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.l10n.youtubeConversionDisabledBuild,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!youtubeEnabled) const SizedBox(height: 12),
                // Download options section
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.settings),
                            const SizedBox(width: 8),
                            Text(context.l10n.downloadOptions,
                                style: Theme.of(context).textTheme.titleMedium),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (isNarrow)
                          Column(
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey('fmt-narrow-$_downloadFormat'),
                                initialValue: _downloadFormat,
                                decoration: InputDecoration(
                                  labelText: context.l10n.format2,
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.audio_file),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                      value: 'mp3', child: Text('MP3')),
                                  const DropdownMenuItem(
                                      value: 'm4a', child: Text('M4A')),
                                  DropdownMenuItem(
                                      value: 'mp4', child: Text(context.l10n.mp4Video)),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _downloadFormat = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey('vq-narrow-$_videoQuality'),
                                initialValue: _videoQuality,
                                decoration: InputDecoration(
                                  labelText: context.l10n.videoQuality,
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.high_quality),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                      value: '360p', child: Text('360p')),
                                  const DropdownMenuItem(
                                      value: '480p', child: Text('480p')),
                                  DropdownMenuItem(
                                      value: '720p', child: Text(context.l10n.n720pHd)),
                                  DropdownMenuItem(
                                      value: '1080p',
                                      child: Text(context.l10n.n1080pFullHd)),
                                  const DropdownMenuItem(
                                      value: '1440p',
                                      child: Text('1440p (2K)')),
                                  const DropdownMenuItem(
                                      value: '2160p',
                                      child: Text('2160p (4K)')),
                                  const DropdownMenuItem(
                                      value: '4320p',
                                      child: Text('4320p (8K)')),
                                  DropdownMenuItem(
                                      value: 'best',
                                      child: Text(context.l10n.bestAvailable)),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _videoQuality = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                key: ValueKey('abr-narrow-$_audioBitrate'),
                                initialValue: _audioBitrate,
                                decoration: InputDecoration(
                                  labelText: context.l10n.audioBitrate,
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.equalizer),
                                ),
                                items: [
                                  DropdownMenuItem(
                                      value: 128, child: Text(context.l10n.n128Kbps)),
                                  DropdownMenuItem(
                                      value: 192, child: Text(context.l10n.n192Kbps)),
                                  DropdownMenuItem(
                                      value: 256, child: Text(context.l10n.n256Kbps)),
                                  DropdownMenuItem(
                                      value: 320, child: Text(context.l10n.n320Kbps)),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => _audioBitrate = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _expandPlaylist,
                                onChanged: (value) {
                                  setState(
                                      () => _expandPlaylist = value ?? false);
                                },
                                title: Text(context.l10n.expandPlaylist),
                                subtitle: Text(context.l10n.showAllVideos),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      key:
                                          ValueKey('fmt-wide-$_downloadFormat'),
                                      initialValue: _downloadFormat,
                                      decoration: InputDecoration(
                                        labelText: context.l10n.format2,
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.audio_file),
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                            value: 'mp3', child: Text('MP3')),
                                        const DropdownMenuItem(
                                            value: 'm4a', child: Text('M4A')),
                                        DropdownMenuItem(
                                            value: 'mp4',
                                            child: Text(context.l10n.mp4Video)),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(
                                              () => _downloadFormat = value);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      key: ValueKey('vq-wide-$_videoQuality'),
                                      initialValue: _videoQuality,
                                      decoration: InputDecoration(
                                        labelText: context.l10n.videoQuality,
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.high_quality),
                                      ),
                                      items: [
                                        const DropdownMenuItem(
                                            value: '360p', child: Text('360p')),
                                        const DropdownMenuItem(
                                            value: '480p', child: Text('480p')),
                                        DropdownMenuItem(
                                            value: '720p',
                                            child: Text(context.l10n.n720pHd)),
                                        DropdownMenuItem(
                                            value: '1080p',
                                            child: Text(context.l10n.n1080pFullHd)),
                                        DropdownMenuItem(
                                            value: 'best',
                                            child: Text(context.l10n.bestAvailable)),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() => _videoQuality = value);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      key: ValueKey('abr-wide-$_audioBitrate'),
                                      initialValue: _audioBitrate,
                                      decoration: InputDecoration(
                                        labelText: context.l10n.audioBitrate,
                                        border: const OutlineInputBorder(),
                                        prefixIcon: const Icon(Icons.equalizer),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                            value: 128,
                                            child: Text(context.l10n.n128Kbps)),
                                        DropdownMenuItem(
                                            value: 192,
                                            child: Text(context.l10n.n192Kbps)),
                                        DropdownMenuItem(
                                            value: 256,
                                            child: Text(context.l10n.n256Kbps)),
                                        DropdownMenuItem(
                                            value: 320,
                                            child: Text(context.l10n.n320Kbps)),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() => _audioBitrate = value);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _expandPlaylist,
                                onChanged: (value) {
                                  setState(
                                      () => _expandPlaylist = value ?? false);
                                },
                                title: Text(context.l10n.expandPlaylist),
                                subtitle: Text(context.l10n.showAllVideos),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (_expandPlaylist)
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.playlist_play),
                              const SizedBox(width: 8),
                              Text(context.l10n.playlistOptions,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('preset-$_previewPreset'),
                                  initialValue: _previewPreset,
                                  decoration: InputDecoration(
                                    labelText: context.l10n.previewAmount,
                                    border: const OutlineInputBorder(),
                                    prefixIcon:
                                        const Icon(Icons.format_list_numbered),
                                    isDense: true,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                        value: '10', child: Text(context.l10n.first10)),
                                    DropdownMenuItem(
                                        value: '25', child: Text(context.l10n.first25)),
                                    DropdownMenuItem(
                                        value: '50', child: Text(context.l10n.first50)),
                                    DropdownMenuItem(
                                        value: '100', child: Text(context.l10n.first100)),
                                    DropdownMenuItem(
                                        value: 'all', child: Text(context.l10n.playerAll)),
                                    DropdownMenuItem(
                                        value: 'custom',
                                        child: Text(context.l10n.customRange)),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _previewPreset = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (_previewPreset == 'custom') ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _rangeFromController,
                                    decoration: InputDecoration(
                                      labelText: context.l10n.from,
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.first_page),
                                      hintText: '1',
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('to',
                                      style: TextStyle(fontSize: 16)),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _rangeToController,
                                    decoration: InputDecoration(
                                      labelText: context.l10n.to,
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.last_page),
                                      hintText: '50',
                                      isDense: true,
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.videoNumbers1BasedE,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 18, color: context.warning),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.l10n.youtubeMixPlaylistsIdsStarting,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: context.warning),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                if (isNarrow)
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.search),
                          label: Text(context.l10n.searchPreview),
                          onPressed: settings == null ||
                                  _urlController.text.trim().isEmpty ||
                                  !youtubeEnabled
                              ? null
                              : _onSearch,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download),
                          label: Text(context.l10n.actionDownload),
                          onPressed: settings == null ||
                                  _urlController.text.trim().isEmpty ||
                                  !youtubeEnabled
                              ? null
                              : () => _downloadUrl(settings),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.search),
                          label: Text(context.l10n.searchPreview),
                          onPressed: settings == null ||
                                  _urlController.text.trim().isEmpty ||
                                  !youtubeEnabled
                              ? null
                              : _onSearch,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download),
                          label: Text(context.l10n.actionDownload),
                          onPressed: settings == null ||
                                  _urlController.text.trim().isEmpty ||
                                  !youtubeEnabled
                              ? null
                              : () => _downloadUrl(settings),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                if (widget.controller.previewLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(context.l10n.loadingPreview),
                        ],
                      ),
                    ),
                  ),
                if (!widget.controller.previewLoading) _buildPreviewList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  bool _ensureDownloadFolder(AppSettings settings) {
    if (_isAndroid) {
      if (_hasAndroidFolder) return true;
      Snack.show(
        context,
        context.l10n.androidNeedsDownloadFolderSet,
        level: SnackLevel.warning,
        actionLabel: context.l10n.goSettings,
        onAction: () => _navigateToPage(7),
        duration: const Duration(seconds: 5),
      );
      _navigateToPage(7);
      return false;
    }

    final dir = settings.downloadDir.trim();
    if (dir.isNotEmpty) return true;
    Snack.show(
      context,
      context.l10n.pleaseSelectDownloadFolderSettings,
      level: SnackLevel.warning,
      actionLabel: context.l10n.goSettings,
      onAction: () => _navigateToPage(7),
      duration: const Duration(seconds: 4),
    );
    _navigateToPage(7);
    return false;
  }

  void _downloadUrl(AppSettings settings) {
    if (!isYouTubeConversionEnabledInCurrentBuild) {
      Snack.show(
        context,
        context.l10n.youtubeConversionDisabledBuild,
        level: SnackLevel.warning,
      );
      return;
    }
    if (!_ensureDownloadFolder(settings)) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final item = widget.controller.previewItems.isNotEmpty
        ? widget.controller.previewItems.cast<PreviewItem?>().firstWhere(
              (p) => p!.url == url,
              orElse: () => null,
            )
        : null;
    if (item != null) {
      widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
    } else {
      widget.controller.addToQueue(
        PreviewItem(
          id: url,
          title: url,
          url: url,
          uploader: '',
          duration: null,
          thumbnailUrl: null,
        ),
        _downloadFormat.toLowerCase(),
      );
    }
    widget.controller.downloadAll();
  }

  void _onSearch() {
    if (!isYouTubeConversionEnabledInCurrentBuild) {
      Snack.show(
        context,
        context.l10n.youtubeConversionDisabledBuild,
        level: SnackLevel.warning,
      );
      return;
    }
    int startIndex = 0;
    int? limit;

    if (_expandPlaylist) {
      switch (_previewPreset) {
        case '10':
          limit = 10;
        case '25':
          limit = 25;
        case '50':
          limit = 50;
        case '100':
          limit = 100;
        case 'all':
          limit = 999999;
        case 'custom':
          var from = int.tryParse(_rangeFromController.text.trim()) ?? 1;
          var to = int.tryParse(_rangeToController.text.trim()) ?? 50;
          if (from > to) {
            final tmp = from;
            from = to;
            to = tmp;
          }
          startIndex = (from - 1).clamp(0, 999999);
          limit = (to - from + 1).clamp(1, 999999);
      }
    }

    widget.controller.preview(
      _urlController.text.trim(),
      _expandPlaylist,
      startIndex: startIndex,
      limit: limit,
    );
  }

  // -- Preview list -------------------------------------------------------

  Widget _buildPreviewList() {
    final isNarrow = _isNarrowLayout(context);
    final items = widget.controller.previewItems;
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.info_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                context.l10n.noPreviewResultsYet,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.enterYoutubeUrlAboveClick,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    _addRangeFrom = _addRangeFrom.clamp(1, items.length);
    _addRangeTo = _addRangeTo.clamp(_addRangeFrom, items.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isNarrow)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.video_library,
                      color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.previewResults(items.length),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all),
                    label: Text(context.l10n.addAll),
                    onPressed: () {
                      for (final item in items) {
                        widget.controller
                            .addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      Snack.show(
                          context, context.l10n.addedItemsQueue(items.length),
                          level: SnackLevel.info);
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(context.l10n.downloadAll),
                    onPressed: () {
                      final s = widget.controller.settings;
                      if (s != null && !_ensureDownloadFolder(s)) return;
                      for (final item in items) {
                        widget.controller
                            .addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      widget.controller.downloadAll();
                    },
                  ),
                ],
              ),
            ],
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.video_library,
                      color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.previewResults(items.length),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all),
                    label: Text(context.l10n.addAll),
                    onPressed: () {
                      for (final item in items) {
                        widget.controller
                            .addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      Snack.show(
                          context, context.l10n.addedItemsQueue(items.length),
                          level: SnackLevel.info);
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(context.l10n.downloadAll),
                    onPressed: () {
                      final s = widget.controller.settings;
                      if (s != null && !_ensureDownloadFolder(s)) return;
                      for (final item in items) {
                        widget.controller
                            .addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      widget.controller.downloadAll();
                    },
                  ),
                ],
              ),
            ],
          ),
        if (items.length > 1) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.addRangeQueue,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(context.l10n.from2),
                      SizedBox(
                        width: 70,
                        child: DropdownButton<int>(
                          value: _addRangeFrom.clamp(1, items.length),
                          isDense: true,
                          isExpanded: true,
                          dropdownColor:
                              Theme.of(context).colorScheme.surfaceContainer,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface),
                          items: List.generate(items.length, (i) {
                            return DropdownMenuItem(
                                value: i + 1, child: Text('${i + 1}'));
                          }),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _addRangeFrom = v;
                              if (_addRangeTo < v) _addRangeTo = v;
                            });
                          },
                        ),
                      ),
                      const Text('to'),
                      SizedBox(
                        width: 70,
                        child: DropdownButton<int>(
                          value: _addRangeTo.clamp(_addRangeFrom, items.length),
                          isDense: true,
                          isExpanded: true,
                          dropdownColor:
                              Theme.of(context).colorScheme.surfaceContainer,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface),
                          items: List.generate(
                            items.length - _addRangeFrom + 1,
                            (i) {
                              final v = _addRangeFrom + i;
                              return DropdownMenuItem(
                                  value: v, child: Text('$v'));
                            },
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _addRangeTo = v);
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: Text(context.l10n.add2(_addRangeTo - _addRangeFrom + 1)),
                        onPressed: () {
                          final subset =
                              items.sublist(_addRangeFrom - 1, _addRangeTo);
                          for (final item in subset) {
                            widget.controller.addToQueue(
                                item, _downloadFormat.toLowerCase());
                          }
                          Snack.show(
                              context, context.l10n.addedItemsQueue2(subset.length),
                              level: SnackLevel.info);
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download, size: 18),
                        label:
                            Text(context.l10n.download(_addRangeTo - _addRangeFrom + 1)),
                        onPressed: () {
                          final s = widget.controller.settings;
                          if (s != null && !_ensureDownloadFolder(s)) return;
                          final subset =
                              items.sublist(_addRangeFrom - 1, _addRangeTo);
                          for (final item in subset) {
                            widget.controller.addToQueue(
                                item, _downloadFormat.toLowerCase());
                          }
                          widget.controller.downloadAll();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        ...items.asMap().entries.map(
          (entry) {
            final index = entry.key;
            final item = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                children: [
                  ListTile(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        item.thumbnailUrl != null &&
                                item.thumbnailUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.thumbnailUrl!,
                                  width: 80,
                                  height: 60,
                                  // Height-only decode hint — a paired
                                  // cacheWidth/cacheHeight pre-distorts the
                                  // decoded bitmap to the box's aspect (the
                                  // codec does not preserve the source's own
                                  // aspect), the same thumbnail-stretch bug
                                  // fixed in the player hero/mini-player art.
                                  cacheHeight: 120,
                                  filterQuality: FilterQuality.low,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _thumbnailPlaceholder(),
                                ),
                              )
                            : _thumbnailPlaceholder(),
                      ],
                    ),
                    title: Text(item.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.uploader,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (item.duration != null)
                          Text(
                            _formatDuration(item.duration!),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: isNarrow
                        ? null
                        : Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: () {
                                  widget.controller.addToQueue(
                                      item, _downloadFormat.toLowerCase());
                                  Snack.show(context, context.l10n.addedQueue,
                                      level: SnackLevel.info,
                                      duration: const Duration(seconds: 1));
                                },
                                tooltip: context.l10n.addQueue,
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.download, size: 18),
                                label: Text(context.l10n.actionDownload),
                                onPressed: () {
                                  final s = widget.controller.settings;
                                  if (s != null && !_ensureDownloadFolder(s)) {
                                    return;
                                  }
                                  widget.controller.addToQueue(
                                      item, _downloadFormat.toLowerCase());
                                  widget.controller.downloadAll();
                                },
                              ),
                            ],
                          ),
                  ),
                  if (isNarrow)
                    Padding(
                      padding: const EdgeInsets.only(
                          left: 16, right: 16, bottom: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: Text(context.l10n.addQueue),
                            onPressed: () {
                              widget.controller.addToQueue(
                                  item, _downloadFormat.toLowerCase());
                              Snack.show(context, context.l10n.addedQueue,
                                  level: SnackLevel.info,
                                  duration: const Duration(seconds: 1));
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.download, size: 18),
                            label: Text(context.l10n.actionDownload),
                            onPressed: () {
                              final s = widget.controller.settings;
                              if (s != null && !_ensureDownloadFolder(s)) {
                                return;
                              }
                              widget.controller.addToQueue(
                                  item, _downloadFormat.toLowerCase());
                              widget.controller.downloadAll();
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _thumbnailPlaceholder() {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _downloadFormat == 'mp4' ? Icons.video_file : Icons.audio_file,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  // -- Queue tab ----------------------------------------------------------

  Widget _buildQueueTab() {
    final queueContent = kPlayStoreBuild
        ? _buildMediaPlayerQueueTab()
        : DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Material(
                  child: TabBar(
                    tabs: [
                      Tab(text: context.l10n.searchQueue),
                      Tab(text: context.l10n.mediaPlayer),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildDownloadQueueTab(),
                      _buildMediaPlayerQueueTab(),
                    ],
                  ),
                ),
              ],
            ),
          );

    return SafeArea(top: true, bottom: true, child: queueContent);
  }

  Widget _buildDownloadQueueTab() {
    final items = widget.controller.queue;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              context.l10n.noItemsQueue,
              style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              kPlayStoreBuild
                  ? context.l10n.addItemsFromPlayerTab
                  : context.l10n.addItemsFromSearchTab,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final completedCount =
        items.where((i) => i.status == DownloadStatus.completed).length;
    final inProgressCount =
        items.where((i) => i.status == DownloadStatus.downloading).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 400;
        final safeBottom = MediaQuery.of(context).padding.bottom;
        return Column(
          children: [
            _buildQueueHeader(
                items, inProgressCount, completedCount, isCompact),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? 8 : 16,
                  isCompact ? 8 : 16,
                  isCompact ? 8 : 16,
                  (isCompact ? 12 : 20) + safeBottom,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _buildQueueItemCard(item, isCompact);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMediaPlayerQueueTab() {
    final playerState = context.watch<PlayerState>();
    final upNext = playerState.queueSnapshot;
    final previously = playerState.playHistorySnapshot.reversed
        .where((index) => index != playerState.currentIndex)
        .toList();

    final showUpNext = _playQueueViewIndex == 0;
    final selected = showUpNext ? upNext : previously;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          color: cs.primary.withValues(alpha: 0.06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                showUpNext ? context.l10n.upNext : context.l10n.previously,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      selected: showUpNext,
                      label: Text(context.l10n.upNext),
                      onSelected: (_) =>
                          setState(() => _playQueueViewIndex = 0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      selected: !showUpNext,
                      label: Text(context.l10n.previously),
                      onSelected: (_) =>
                          setState(() => _playQueueViewIndex = 1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: selected.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        showUpNext ? Icons.queue_music : Icons.history,
                        size: 46,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        showUpNext
                            ? context.l10n.noSongsUpNext
                            : context.l10n.noPreviouslyPlayedSongsYet,
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (showUpNext) ...[
                        const SizedBox(height: 6),
                        Text(
                          context.l10n.addItemsFromPlayerTab,
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    12 + MediaQuery.of(context).padding.bottom,
                  ),
                  itemCount: selected.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final mediaIndex = selected[i];
                    if (mediaIndex < 0 ||
                        mediaIndex >= playerState.library.length) {
                      return const SizedBox.shrink();
                    }
                    final media = playerState.library[mediaIndex];
                    final title =
                        (media.title == null || media.title!.trim().isEmpty)
                            ? media.path.split(RegExp(r'[\\/]')).last
                            : media.title!;
                    return RepaintBoundary(
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(
                            media.type == MediaType.video
                                ? Icons.videocam_outlined
                                : Icons.music_note,
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            showUpNext ? context.l10n.queued : context.l10n.previouslyPlayed,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.play_arrow),
                          onTap: () {
                            playerState.select(mediaIndex);
                            _navigateToPage(12);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQueueHeader(List<QueueItem> items, int inProgressCount,
      int completedCount, bool isCompact) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 16),
      color: cs.primary.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tabQueue,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 14 : 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.totalActiveDone(items.length, inProgressCount, completedCount),
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              DropdownButton<String>(
                value: _downloadFormat,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: TextStyle(fontSize: 12, color: cs.onSurface),
                items: const [
                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                  DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                  DropdownMenuItem(value: 'mp4', child: Text('MP4')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _downloadFormat = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: Text(isCompact ? context.l10n.playerAll : context.l10n.downloadAll,
                        style: const TextStyle(fontSize: 12)),
                    onPressed: items.isEmpty
                        ? null
                        : () {
                            final s = widget.controller.settings;
                            if (s != null && !_ensureDownloadFolder(s)) return;
                            widget.controller.downloadAll();
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: Text(isCompact ? context.l10n.actionClear : context.l10n.clearQueue,
                        style: const TextStyle(fontSize: 12)),
                    onPressed: items.isEmpty
                        ? null
                        : () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(context.l10n.clearQueue),
                                // overflow-fix: keep confirmation text scroll-safe.
                                content: SingleChildScrollView(
                                  child:
                                      Text(context.l10n.removeAllItemsFromQueue),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(context.l10n.actionCancel),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      final snapshot =
                                          List<QueueItem>.from(items);
                                      for (final item in snapshot) {
                                        widget.controller.removeFromQueue(item);
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: Text(context.l10n.actionClear),
                                  ),
                                ],
                              ),
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueueItemCard(QueueItem item, bool isCompact) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(item.status);
    final statusIcon = _getStatusIcon(item.status);

    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: isCompact ? 12 : 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.status.name.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  Text('${item.progress}%',
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  SizedBox(
                    height: 24,
                    child: DropdownButton<String>(
                      value: item.format,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(fontSize: 11, color: cs.onSurface),
                      items: const [
                        DropdownMenuItem(
                            value: 'mp3',
                            child: Text('MP3', style: TextStyle(fontSize: 11))),
                        DropdownMenuItem(
                            value: 'm4a',
                            child: Text('M4A', style: TextStyle(fontSize: 11))),
                        DropdownMenuItem(
                            value: 'mp4',
                            child: Text('MP4', style: TextStyle(fontSize: 11))),
                      ],
                      onChanged: item.status == DownloadStatus.downloading ||
                              item.status == DownloadStatus.converting ||
                              item.status == DownloadStatus.completed
                          ? null
                          : (value) {
                              if (value != null) {
                                widget.controller
                                    .changeQueueItemFormat(item, value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              if (item.progress > 0 && item.progress < 100) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: item.progress / 100,
                    minHeight: 4,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
                if (item.speed != null || item.eta != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        if (item.speed != null)
                          Text(context.l10n.speed(item.speed!),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        if (item.eta != null) ...[
                          const SizedBox(width: 12),
                          Text(context.l10n.eta(item.eta!),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  if (item.status == DownloadStatus.queued ||
                      item.status == DownloadStatus.failed ||
                      item.status == DownloadStatus.cancelled)
                    _queueAction(Icons.download_rounded, context.l10n.actionDownload,
                        Theme.of(context).colorScheme.primary, () {
                      final s = widget.controller.settings;
                      if (s != null && !_ensureDownloadFolder(s)) return;
                      widget.controller.downloadSingle(item);
                    }),
                  if (item.status == DownloadStatus.downloading ||
                      item.status == DownloadStatus.converting)
                    _queueAction(Icons.stop_rounded, context.l10n.actionCancel, context.warning,
                        () => widget.controller.cancelDownload(item)),
                  if (item.status == DownloadStatus.cancelled ||
                      item.status == DownloadStatus.failed)
                    _queueAction(
                        Icons.play_arrow_rounded, context.l10n.actionResume, context.success,
                        () {
                      final s = widget.controller.settings;
                      if (s != null && !_ensureDownloadFolder(s)) return;
                      widget.controller.resumeDownload(item);
                    }),
                  if (item.status == DownloadStatus.completed &&
                      item.outputPath != null &&
                      !kIsWeb)
                    _queueAction(
                        Icons.folder_open_rounded,
                        context.l10n.folder,
                        Theme.of(context).colorScheme.primary,
                        () => _showInFolder(item.outputPath!)),
                  if (item.status == DownloadStatus.completed &&
                      item.outputPath != null &&
                      !kIsWeb &&
                      Platform.isAndroid)
                    _queueAction(
                        Icons.share_rounded,
                        context.l10n.actionShare,
                        Theme.of(context).colorScheme.primary,
                        () => _shareFile(item.outputPath!, item.title)),
                  if (item.status != DownloadStatus.downloading &&
                      item.status != DownloadStatus.converting)
                    _queueAction(
                        Icons.delete_outline_rounded,
                        context.l10n.actionRemove,
                        context.danger,
                        () => widget.controller.removeFromQueue(item)),
                ],
              ),
              if (item.error != null &&
                  item.status == DownloadStatus.failed) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.danger.withAlpha((0.08 * 255).round()),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.error!,
                    style: TextStyle(color: context.danger, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _queueAction(
      IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        icon: Icon(icon, size: 16, color: color),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Color _getStatusColor(DownloadStatus status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case DownloadStatus.completed:
        return context.success;
      case DownloadStatus.downloading:
        return cs.primary;
      case DownloadStatus.converting:
        return cs.secondary;
      case DownloadStatus.cancelled:
        return context.warning;
      case DownloadStatus.failed:
        return context.danger;
      case DownloadStatus.queued:
        return cs.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return Icons.check_circle;
      case DownloadStatus.downloading:
        return Icons.downloading;
      case DownloadStatus.converting:
        return Icons.sync;
      case DownloadStatus.cancelled:
        return Icons.cancel;
      case DownloadStatus.failed:
        return Icons.error;
      case DownloadStatus.queued:
        return Icons.hourglass_empty;
    }
  }

  // -- Playlists tab ------------------------------------------------------

  Widget _buildPlaylistsTab() {
    return Column(
      children: [
        TabBar(
          controller: _playlistTabController,
          tabs: [
            Tab(text: context.l10n.playlistManager),
            Tab(text: context.l10n.watchedPlaylists),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _playlistTabController,
            children: [
              PlaylistScreen(
                playlistService: widget.controller.playlistService,
                pendingRequest: widget.controller.pendingPlaylistRequest,
                onDownloadMissing: (tracks, format, folder) {
                  for (final t in tracks) {
                    widget.controller.addSearchResultToQueue(t,
                        format: format, outputFolder: folder);
                  }
                  widget.controller.downloadAll();
                },
              ),
              WatchedPlaylistsScreen(
                watchedService: widget.controller.watchedPlaylistService,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -- Settings tab -------------------------------------------------------

  /// Language picker, shared by the simplified and the full Settings tab.
  ///
  /// The app shipped 18 translations with no way to choose one: it followed the
  /// device language and nothing else. See issue #7.
  Widget _buildLanguageTile(AppSettings settings) {
    final current = appLanguageFor(settings.language);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(context.l10n.settingsLanguage),
      subtitle: Text(
        current.code == 'system'
            ? context.l10n.automaticDeviceLanguage
            : '${current.nativeName} - ${current.englishName}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _pickLanguage(settings),
    );
  }

  Future<void> _pickLanguage(AppSettings settings) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.l10n.settingsLanguage),
        children: [
          for (final language in kAppLanguages)
            ListTile(
              title: Text(language.nativeName),
              subtitle: Text(language.englishName),
              trailing: language.code == settings.language
                  ? Icon(
                      Icons.check,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(dialogContext, language.code),
            ),
        ],
      ),
    );
    if (chosen == null || chosen == settings.language) return;
    await widget.controller.saveSettings(settings.copyWith(language: chosen));
  }

  Widget _buildSimplifiedSettingsTab(AppSettings settings) {
    // Simplified settings for Play Store build: only torrent path and theme
    final isNarrow = _isNarrowLayout(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(context.l10n.saveSettings),
              onPressed: () => _saveAllSettings(settings),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            child: ListTile(
              leading:
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 32),
              title: Text(
                context.l10n.enjoyingConvertSpireReborn,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle:
                  Text(context.l10n.leaveReviewHelpsMoreThan),
              trailing: ElevatedButton(
                onPressed: () {
                  unawaited(ReviewService.openStoreListing());
                },
                child: Text(context.l10n.rate),
              ),
            ),
          ),

          // Torrent Download Path (main setting)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined),
                      const SizedBox(width: 8),
                      Text(context.l10n.torrentStorage,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_isAndroid)
                    Column(
                      children: [
                        TextField(
                          controller: _downloadDirTorrentsController,
                          decoration: InputDecoration(
                            labelText: context.l10n.torrentFolder,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.folder),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.folder_open),
                              onPressed: () => _pickFormatDownloadFolder(
                                  settings, 'torrent'),
                            ),
                          ),
                          readOnly: true,
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        if (isNarrow)
                          Column(
                            children: [
                              TextField(
                                controller: _downloadDirTorrentsController,
                                decoration: InputDecoration(
                                  labelText: context.l10n.torrentFolder,
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.folder),
                                ),
                                readOnly: true,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.folder_open),
                                  label: Text(context.l10n.browse),
                                  onPressed: () async {
                                    final result = await pickDirectoryPath(
                                      context,
                                      dialogTitle: context.l10n.selectTorrentFolder,
                                    );
                                    if (result != null && mounted) {
                                      setState(() =>
                                          _downloadDirTorrentsController.text =
                                              result);
                                      await widget.controller.saveSettings(
                                          settings.copyWith(
                                              downloadDirTorrents: result));
                                    }
                                  },
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _downloadDirTorrentsController,
                                  decoration: InputDecoration(
                                    labelText: context.l10n.torrentFolder,
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.folder),
                                  ),
                                  readOnly: true,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.folder_open),
                                label: Text(context.l10n.browse),
                                onPressed: () async {
                                  final result = await pickDirectoryPath(
                                    context,
                                    dialogTitle: context.l10n.selectTorrentFolder,
                                  );
                                  if (result != null && mounted) {
                                    setState(() =>
                                        _downloadDirTorrentsController.text =
                                            result);
                                    await widget.controller.saveSettings(
                                        settings.copyWith(
                                            downloadDirTorrents: result));
                                  }
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Torrents: ports, limits, seeding, peer discovery, proxy
          const TorrentSettingsCard(),
          const SizedBox(height: 16),

          // Theme Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined),
                      const SizedBox(width: 8),
                      Text(context.l10n.appearance,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(context.l10n.appTheme),
                    subtitle: Text(
                      '${settings.themeMode[0].toUpperCase()}${settings.themeMode.substring(1)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      initialValue: settings.themeMode,
                      onSelected: (String mode) async {
                        await widget.controller.saveSettings(
                          settings.copyWith(themeMode: mode),
                        );
                        unawaited(widget.controller.setThemeMode(
                          (_resolveThemeMode(mode)),
                        ));
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem<String>(
                          value: 'system',
                          child: Text(context.l10n.system),
                        ),
                        PopupMenuItem<String>(
                          value: 'light',
                          child: Text(context.l10n.light),
                        ),
                        PopupMenuItem<String>(
                          value: 'dark',
                          child: Text(context.l10n.dark),
                        ),
                      ],
                    ),
                  ),
                  _buildLanguageTile(settings),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(context.l10n.reportBug),
                    subtitle: Text(
                        context.l10n.opensGithubVersionRecentLog),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => unawaited(_reportBug()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Info Card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.basicSettingsOnly,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.versionOptimizedTorrentVaultFunctionalit,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(AppSettings? settings) {
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // For Play Store build, show only torrent path and theme settings
    if (kPlayStoreBuild) {
      return _buildSimplifiedSettingsTab(settings);
    }

    final isNarrow = _isNarrowLayout(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(context.l10n.saveSettings),
              onPressed: () => _saveAllSettings(settings),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3),
            child: ListTile(
              leading:
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 32),
              title: Text(
                context.l10n.enjoyingConvertSpireReborn,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle:
                  Text(context.l10n.leaveReviewHelpsMoreThan),
              trailing: ElevatedButton(
                onPressed: () {
                  unawaited(ReviewService.openStoreListing());
                },
                child: Text(context.l10n.rate),
              ),
            ),
          ),

          // Close-to-tray behavior (desktop only)
          if (_isDesktopPlatform)
            SwitchListTile(
              title: Text(context.l10n.minimizeTrayClose),
              subtitle: Text(
                context.l10n.keepAppRunningBackgroundWhen,
              ),
              value: _minimizeToTrayOnClose,
              onChanged: (v) => setState(() => _minimizeToTrayOnClose = v),
              secondary: const Icon(Icons.minimize),
            ),

          // Support the project (donations)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.favorite,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.l10n.supportProject,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.helpKeepAppOpenSource,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _openBuyMeCoffee,
                          child: Text(context.l10n.buyMeCoffee),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final uri = Uri.parse(
                                'https://github.com/sponsors/Lukas-Bohez');
                            if (!await launchUrl(uri,
                                mode: LaunchMode.externalApplication)) {
                              Snack.show(context,
                                  context.l10n.couldNotOpenGithubSponsors,
                                  level: SnackLevel.error);
                            }
                          },
                          child: Text(context.l10n.githubSponsors),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Download Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined),
                      const SizedBox(width: 8),
                      Text(context.l10n.downloadSettings,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (_isAndroid) ...[
                    TextField(
                      controller: _downloadDirController,
                      decoration: InputDecoration(
                        labelText: context.l10n.downloadFolder,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder),
                        helperText:
                            context.l10n.pickFolderUsingAppFile(getDefaultDownloadFolderName()),
                        helperMaxLines: 3,
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(_hasAndroidFolder
                              ? context.l10n.changeFolder
                              : context.l10n.chooseFolder),
                          onPressed: () => _pickAndroidFolder(settings),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.folder),
                          label: Text(context.l10n.openFolder),
                          onPressed: _hasAndroidFolder
                              ? () => _openAndroidFolder(settings)
                              : null,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.clear),
                          label: Text(context.l10n.actionClear),
                          onPressed: _hasAndroidFolder
                              ? () => _clearAndroidFolder(settings)
                              : null,
                        ),
                      ],
                    ),
                    if (!_hasAndroidFolder)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          context.l10n.noFolderSelectedDownloadsWill(getDefaultDownloadFolderName()),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.warning),
                        ),
                      ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: Text(context.l10n.usePerFormatSubFolders),
                      subtitle: Text(
                          context.l10n.whenDisabledSelectedOutputFolder),
                      value: _useFormatSubfolders,
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _useFormatSubfolders = value);
                        await widget.controller.saveSettings(
                            settings.copyWith(createFormatSubfolders: value));
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _downloadDirMp3Controller,
                      decoration: InputDecoration(
                        labelText: context.l10n.mp3FolderOptional,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'mp3'),
                        ),
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _downloadDirM4aController,
                      decoration: InputDecoration(
                        labelText: context.l10n.m4aFolderOptional,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'm4a'),
                        ),
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _downloadDirMp4Controller,
                      decoration: InputDecoration(
                        labelText: context.l10n.mp4FolderOptional,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'mp4'),
                        ),
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _downloadDirTorrentsController,
                      decoration: InputDecoration(
                        labelText: context.l10n.torrentFolderOptional,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'torrent'),
                        ),
                      ),
                      readOnly: true,
                    ),
                  ] else ...[
                    if (isNarrow)
                      Column(
                        children: [
                          TextField(
                            controller: _downloadDirController,
                            decoration: InputDecoration(
                              labelText: context.l10n.downloadFolder,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.folder),
                            ),
                            readOnly: true,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: Text(context.l10n.browse),
                              onPressed: () async {
                                final result = await pickDirectoryPath(
                                  context,
                                  dialogTitle: context.l10n.selectDownloadFolder,
                                );
                                if (result != null && mounted) {
                                  setState(() =>
                                      _downloadDirController.text = result);
                                  await widget.controller.saveSettings(
                                      settings.copyWith(downloadDir: result));
                                }
                              },
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _downloadDirController,
                              decoration: InputDecoration(
                                labelText: context.l10n.downloadFolder,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.folder),
                              ),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.folder_open),
                            label: Text(context.l10n.browse),
                            onPressed: () async {
                              final result = await pickDirectoryPath(
                                context,
                                dialogTitle: context.l10n.selectDownloadFolder,
                              );
                              if (result != null && mounted) {
                                setState(
                                    () => _downloadDirController.text = result);
                                await widget.controller.saveSettings(
                                    settings.copyWith(downloadDir: result));
                              }
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: Text(context.l10n.usePerFormatSubFolders),
                      subtitle: Text(
                          context.l10n.whenDisabledSelectedOutputFolder),
                      value: _useFormatSubfolders,
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => _useFormatSubfolders = value);
                        await widget.controller.saveSettings(
                            settings.copyWith(createFormatSubfolders: value));
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _downloadDirMp3Controller,
                            decoration: InputDecoration(
                              labelText: context.l10n.mp3FolderOptional,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.folder),
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.l10n.browse),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'mp3'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _downloadDirM4aController,
                            decoration: InputDecoration(
                              labelText: context.l10n.m4aFolderOptional,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.folder),
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.l10n.browse),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'm4a'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _downloadDirMp4Controller,
                            decoration: InputDecoration(
                              labelText: context.l10n.mp4FolderOptional,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.folder),
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.l10n.browse),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'mp4'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _downloadDirTorrentsController,
                            decoration: InputDecoration(
                              labelText: context.l10n.torrentFolderOptional,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.folder_special_outlined),
                              helperText:
                                  context.l10n.whenSetVaultTorrentsUse,
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.l10n.browse),
                          onPressed: () =>
                              _pickFormatDownloadFolder(settings, 'torrent'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _workersController,
                    decoration: InputDecoration(
                      labelText: context.l10n.parallelWorkers110,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.settings_ethernet),
                      hintText: context.l10n.numberConcurrentDownloads,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: settings.showNotifications,
                    onChanged: (value) {
                      widget.controller.saveSettings(
                          settings.copyWith(showNotifications: value));
                    },
                    title: Text(context.l10n.showNotifications),
                    subtitle: Text(
                        context.l10n.displayNotificationsWhenDownloadsComplet),
                    secondary: const Icon(Icons.notifications),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quality Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.high_quality_outlined),
                      const SizedBox(width: 8),
                      Text(context.l10n.qualitySettings,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (isNarrow) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('settings-vq-$_videoQuality'),
                      initialValue: _videoQuality,
                      decoration: InputDecoration(
                        labelText: context.l10n.videoQuality,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.videocam),
                        helperText:
                            context.l10n.highResolutions1080p4k8k,
                        helperMaxLines: 2,
                      ),
                      items: [
                        const DropdownMenuItem(value: '360p', child: Text('360p')),
                        const DropdownMenuItem(value: '480p', child: Text('480p')),
                        DropdownMenuItem(
                            value: '720p', child: Text(context.l10n.n720pHd)),
                        DropdownMenuItem(
                            value: '1080p', child: Text(context.l10n.n1080pFullHd)),
                        DropdownMenuItem(
                            value: 'best', child: Text(context.l10n.bestAvailable)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _videoQuality = value);
                        widget.controller.saveSettings(
                            settings.copyWith(preferredVideoQuality: value));
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('settings-abr-$_audioBitrate'),
                      initialValue: _audioBitrate,
                      decoration: InputDecoration(
                        labelText: context.l10n.audioBitrate,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.equalizer),
                        helperText:
                            context.l10n.higherBitrateBetterQualityLarger,
                        helperMaxLines: 2,
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 128, child: Text(context.l10n.n128KbpsCompact)),
                        DropdownMenuItem(
                            value: 192, child: Text(context.l10n.n192KbpsStandard)),
                        DropdownMenuItem(
                            value: 256, child: Text(context.l10n.n256KbpsHigh)),
                        DropdownMenuItem(
                            value: 320, child: Text(context.l10n.n320KbpsMaximum)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _audioBitrate = value);
                        widget.controller.saveSettings(
                            settings.copyWith(preferredAudioBitrate: value));
                      },
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('settings-vq-$_videoQuality'),
                            initialValue: _videoQuality,
                            decoration: InputDecoration(
                              labelText: context.l10n.videoQuality,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.videocam),
                              helperText:
                                  context.l10n.highResolutions1080p4k8k2,
                              helperMaxLines: 2,
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: '360p', child: Text('360p')),
                              const DropdownMenuItem(
                                  value: '480p', child: Text('480p')),
                              DropdownMenuItem(
                                  value: '720p', child: Text(context.l10n.n720pHd)),
                              DropdownMenuItem(
                                  value: '1080p',
                                  child: Text(context.l10n.n1080pFullHd)),
                              const DropdownMenuItem(
                                  value: '1440p', child: Text('1440p (2K)')),
                              const DropdownMenuItem(
                                  value: '2160p', child: Text('2160p (4K)')),
                              const DropdownMenuItem(
                                  value: '4320p', child: Text('4320p (8K)')),
                              DropdownMenuItem(
                                  value: 'best', child: Text(context.l10n.bestAvailable)),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _videoQuality = value);
                              widget.controller.saveSettings(settings.copyWith(
                                  preferredVideoQuality: value));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('settings-abr-$_audioBitrate'),
                            initialValue: _audioBitrate,
                            decoration: InputDecoration(
                              labelText: context.l10n.audioBitrate,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.equalizer),
                              helperText: context.l10n.higherBetterQuality,
                              helperMaxLines: 2,
                            ),
                            items: [
                              DropdownMenuItem(
                                  value: 128,
                                  child: Text(context.l10n.n128KbpsCompact)),
                              DropdownMenuItem(
                                  value: 192,
                                  child: Text(context.l10n.n192KbpsStandard)),
                              DropdownMenuItem(
                                  value: 256, child: Text(context.l10n.n256KbpsHigh)),
                              DropdownMenuItem(
                                  value: 320,
                                  child: Text(context.l10n.n320KbpsMaximum)),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _audioBitrate = value);
                              widget.controller.saveSettings(settings.copyWith(
                                  preferredAudioBitrate: value));
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // FFmpeg & yt-dlp (desktop only)
          if (!_isAndroid) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.code,
                            color: _ffmpegPathController.text.isNotEmpty
                                ? context.success
                                : context.warning),
                        const SizedBox(width: 8),
                        Text(context.l10n.ffmpeg,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (_ffmpegPathController.text.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle,
                              color: context.success, size: 18),
                        ],
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ffmpegPathController,
                            decoration: InputDecoration(
                              labelText: context.l10n.ffmpegPath,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.terminal),
                              hintText: _ffmpegPathController.text.isEmpty
                                  ? context.l10n.autoInstalledFirstUse
                                  : null,
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.l10n.browse),
                          onPressed: () async {
                            final selectedPath = await pickSingleFilePath(
                              context,
                              dialogTitle: context.l10n.selectFfmpegExecutable,
                            );
                            if (selectedPath != null && mounted) {
                              setState(() =>
                                  _ffmpegPathController.text = selectedPath);
                              final s = widget.controller.settings;
                              if (s != null) {
                                unawaited(widget.controller.saveSettings(
                                    s.copyWith(ffmpegPath: selectedPath)));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    if (_ffmpegPathController.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          context.l10n.willInstalledAutomaticallyWhenNeeded,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.warning),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.download_for_offline,
                            color: _ytDlpPathController.text.isNotEmpty
                                ? context.success
                                : context.warning),
                        const SizedBox(width: 8),
                        Text('yt-dlp',
                            style: Theme.of(context).textTheme.titleLarge),
                        if (_ytDlpPathController.text.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle,
                              color: context.success, size: 18),
                        ],
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final versionText =
                            (_ytDlpCurrentVersion ?? 'unknown').trim();
                        Color dotColor = Colors.grey;
                        String statusText =
                            context.l10n.ytDlpCouldNotCheck(versionText);

                        if (_ytDlpVersionChecking) {
                          dotColor = Theme.of(context).colorScheme.primary;
                          statusText =
                              context.l10n.ytDlpCheckingUpdates(versionText);
                        } else if (!_ytDlpVersionCheckFailed &&
                            _ytDlpIsUpToDate == true) {
                          dotColor = Colors.green;
                          statusText = context.l10n.ytDlpUpDate(versionText);
                        } else if (!_ytDlpVersionCheckFailed &&
                            _ytDlpIsUpToDate == false) {
                          dotColor = Colors.orange;
                          statusText = context.l10n.ytDlpUpdateAvailable(
                              versionText,
                              _ytDlpLatestVersion ?? context.l10n.unknown);
                        }

                        final checkedText = _ytDlpLastChecked == null
                            ? null
                            : context.l10n.lastChecked(_ytDlpLastChecked!.toLocal());

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: dotColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(statusText)),
                                ],
                              ),
                              if (checkedText != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  checkedText,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ytDlpPathController,
                            decoration: InputDecoration(
                              labelText: context.l10n.ytDlpPath,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.terminal),
                              hintText: _ytDlpPathController.text.isEmpty
                                  ? context.l10n.autoDownloadedFirstUse
                                  : null,
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: Text(context.l10n.browse),
                          onPressed: () async {
                            final selectedPath = await pickSingleFilePath(
                              context,
                              dialogTitle: context.l10n.selectYtDlpExecutable,
                            );
                            if (selectedPath != null && mounted) {
                              setState(() =>
                                  _ytDlpPathController.text = selectedPath);
                              final s = widget.controller.settings;
                              if (s != null) {
                                unawaited(widget.controller.saveSettings(
                                    s.copyWith(ytDlpPath: selectedPath)));
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        if (_ytDlpIsUpToDate == false)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.update),
                            label: Text(context.l10n.update),
                            onPressed: () async {
                              final s = widget.controller.settings;
                              if (s == null) return;
                              final current = s.ytDlpPath;
                              Snack.show(context, context.l10n.updatingYtDlp,
                                  level: SnackLevel.info);
                              try {
                                final updated = await widget
                                    .controller.downloadService.ytDlp
                                    .update(
                                  configuredPath: current,
                                  onProgress: (pct, msg) {
                                    if (pct % 25 == 0 || pct == 100) {
                                      Snack.show(
                                          context, context.l10n.ytDlp(msg, pct),
                                          level: SnackLevel.info);
                                    }
                                  },
                                );
                                if (mounted) {
                                  setState(() {
                                    _ytDlpPathController.text = updated;
                                  });
                                }
                                await widget.controller.saveSettings(
                                    s.copyWith(ytDlpPath: updated));
                                await _checkYtDlpUpdateStatus();
                                Snack.show(
                                    context, context.l10n.ytDlpUpdatedSuccessfully,
                                    level: SnackLevel.success);
                              } catch (e) {
                                Snack.show(context,
                                    context.l10n.failedUpdateYtDlp(e.toString()),
                                    level: SnackLevel.error);
                              }
                            },
                          ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.check),
                          onPressed: _ytDlpVersionChecking
                              ? null
                              : () => _checkYtDlpUpdateStatus(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _sponsorBlockEnabled,
                      onChanged: (value) async {
                        setState(() => _sponsorBlockEnabled = value);
                        final s = widget.controller.settings;
                        if (s != null) {
                          await widget.controller.saveSettings(
                              s.copyWith(sponsorBlockEnabled: value));
                        }
                      },
                      title: Text(context.l10n.useSponsorblock),
                      subtitle: Text(
                          context.l10n.automaticallyRemoveSponsoredIntroOutro),
                      secondary: const Icon(Icons.remove_red_eye),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _youtubeAuthEnabled,
                      onChanged: (value) =>
                          setState(() => _youtubeAuthEnabled = value),
                      title: Text(context.l10n.useSignedYoutubeSession),
                      subtitle: Text(
                        context.l10n.useBrowserCookiesAgeRestricted,
                      ),
                      secondary: const Icon(Icons.verified_user_outlined),
                    ),
                    if (_youtubeAuthEnabled) ...[
                      const SizedBox(height: 8),
                      if (_availableCookieBrowsers().isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                              'settings-cookies-browser-$_youtubeCookiesFromBrowser'),
                          initialValue: _availableCookieBrowsers()
                                  .contains(_youtubeCookiesFromBrowser)
                              ? _youtubeCookiesFromBrowser
                              : _defaultCookiesFromBrowser(),
                          decoration: InputDecoration(
                            labelText: context.l10n.cookieSourceBrowser,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.web),
                            helperText:
                                context.l10n.selectBrowserWhereSignedYoutube,
                          ),
                          items: _availableCookieBrowsers()
                              .map(
                                (browser) => DropdownMenuItem<String>(
                                  value: browser,
                                  child: Text(browser),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _youtubeCookiesFromBrowser = value);
                          },
                        )
                      else
                        Text(
                          context.l10n.browserCookieExtractionNotAvailable,
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ytCookiesFileController,
                              decoration: InputDecoration(
                                labelText: context.l10n.cookiesFileOptional,
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.cookie_outlined),
                                helperText:
                                    context.l10n.optionalExportedCookiesTxtUsed,
                              ),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.folder_open),
                            label: Text(context.l10n.browse),
                            onPressed: () async {
                              final selectedPath = await pickSingleFilePath(
                                context,
                                dialogTitle: context.l10n.selectCookiesTxt,
                                allowedExtensions: const <String>['txt'],
                              );
                              if (selectedPath == null || !mounted) {
                                return;
                              }
                              setState(() {
                                _ytCookiesFileController.text = selectedPath;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.login),
                            label: Text(context.l10n.signYoutube),
                            onPressed: _openYouTubeSignInExternal,
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.clear),
                            label: Text(context.l10n.clearCookiesFile),
                            onPressed: () {
                              setState(() => _ytCookiesFileController.clear());
                            },
                          ),
                        ],
                      ),
                    ],
                    if (_ytDlpPathController.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          context.l10n.willDownloadedAutomaticallyFirstLaunch,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.warning),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Retry Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.refresh),
                      const SizedBox(width: 8),
                      Text(context.l10n.retrySettings,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: settings.autoRetryInstall,
                    onChanged: (value) {
                      widget.controller.saveSettings(
                          settings.copyWith(autoRetryInstall: value));
                    },
                    title: Text(context.l10n.autoRetryInstalls),
                    subtitle:
                        Text(context.l10n.automaticallyRetryFailedDownloads),
                    secondary: const Icon(Icons.replay),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retryCountController,
                    decoration: InputDecoration(
                      labelText: context.l10n.retryCount010,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.repeat),
                      hintText: context.l10n.numberRetryAttempts,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retryBackoffController,
                    decoration: InputDecoration(
                      labelText: context.l10n.retryBackoffSeconds060,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.timelapse),
                      hintText: context.l10n.waitTimeBetweenRetries,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Torrents: ports, limits, seeding, peer discovery, proxy
          const TorrentSettingsCard(),
          const SizedBox(height: 24),

          // Appearance
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined),
                      const SizedBox(width: 8),
                      Text(context.l10n.appearance,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                          value: 'system',
                          label: Text(context.l10n.system),
                          icon: const Icon(Icons.brightness_auto)),
                      ButtonSegment(
                          value: 'light',
                          label: Text(context.l10n.light),
                          icon: const Icon(Icons.light_mode)),
                      ButtonSegment(
                          value: 'dark',
                          label: Text(context.l10n.dark),
                          icon: const Icon(Icons.dark_mode)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (value) {
                      widget.controller.saveSettings(
                          settings.copyWith(themeMode: value.first));
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildLanguageTile(settings),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(context.l10n.reportBug),
                    subtitle: Text(
                        context.l10n.opensGithubVersionRecentLog),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => unawaited(_reportBug()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline),
                      const SizedBox(width: 8),
                      Text(context.l10n.about,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    getAppTitle(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.redBullBasementSpireaiProject,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.crossPlatformMediaToolkitMulti,
                  ),
                  const SizedBox(height: 8),
                  Text(
                      context.l10n.copyrightC2026OrokaConner),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.coffee),
                        label: Text(context.l10n.buyMeCoffee2),
                        onPressed: _openBuyMeCoffee,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.public),
                        label: Text(context.l10n.visitQuizthespireCom),
                        onPressed: _openWebsite,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.code),
                        label: Text(context.l10n.github),
                        onPressed: () async {
                          final launched = await launchUrl(
                            Uri.parse(
                                'https://github.com/Lukas-Bohez/ConvertTheSpireFlutter'),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!launched && mounted) {
                            Snack.show(
                                context, context.l10n.couldNotOpenGithubLink,
                                level: SnackLevel.error);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Browser Shell Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.view_sidebar_outlined),
                      const SizedBox(width: 8),
                      Text(context.l10n.browserShell,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _queueOnRight,
                    onChanged: (value) => setState(() => _queueOnRight = value),
                    title: Text(context.l10n.queueSidebarRight),
                    subtitle: Text(_queueOnRight
                        ? context.l10n.queuePanelRightSide
                        : context.l10n.queuePanelLeftSide),
                    secondary: Icon(
                        _queueOnRight ? Icons.border_right : Icons.border_left),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: Text(context.l10n.goHomePage),
                    subtitle: Text(context.l10n.navigateQuickLinksHome),
                    onTap: () => _navigateToPage(13),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: Text(context.l10n.resetQuickLinks),
                    subtitle: Text(context.l10n.restoreDefaultQuickLinks),
                    onTap: () async {
                      AdService.instance.registerInteraction();
                      await QuickLinksService.resetToDefaults();
                      if (mounted) {
                        Snack.show(context, context.l10n.quickLinksResetDefaults,
                            level: SnackLevel.info);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.school),
                    title: Text(context.l10n.replayTutorialTips),
                    subtitle: Text(context.l10n.showScreenDescriptionsAgain),
                    onTap: () async {
                      AdService.instance.registerInteraction();
                      await _onboarding.reset();
                      setState(() => _dismissedBannerRoute = null);
                      if (mounted) {
                        Snack.show(context,
                            context.l10n.tutorialTipsWillShowAgain,
                            level: SnackLevel.info);
                      }
                    },
                  ),
                  if (!kPlayStoreBuild) ...[
                    // Update check toggle
                    SwitchListTile(
                      value: _checkUpdatesOnLaunch,
                      onChanged: (value) async {
                        await UpdateService.setCheckOnLaunch(value);
                        if (mounted) {
                          setState(() => _checkUpdatesOnLaunch = value);
                        }
                      },
                      title: Text(context.l10n.checkUpdatesLaunch),
                      secondary: const Icon(Icons.system_update_alt),
                    ),
                    ListTile(
                      leading: const Icon(Icons.refresh),
                      title: Text(context.l10n.checkUpdatesNow),
                      onTap: () => _checkForUpdate(force: true),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(context.l10n.saveSettings),
              onPressed: () => _saveAllSettings(settings),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openBuyMeCoffee() async {
    final launched =
        await launchUrl(_buyMeCoffeeUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      Snack.show(context, context.l10n.couldNotOpenBuyMe,
          level: SnackLevel.error);
    }
  }

  Future<void> _saveAllSettings(AppSettings settings) async {
    final ffmpegText = _ffmpegPathController.text.trim();
    final ytDlpText = _ytDlpPathController.text.trim();
    final next = settings.copyWith(
      downloadDir:
          _isAndroid ? _androidDownloadUri : _downloadDirController.text.trim(),
      maxWorkers:
          (int.tryParse(_workersController.text.trim()) ?? settings.maxWorkers)
              .clamp(1, 10),
      retryCount: (int.tryParse(_retryCountController.text.trim()) ??
              settings.retryCount)
          .clamp(0, 10),
      retryBackoffSeconds: (int.tryParse(_retryBackoffController.text.trim()) ??
              settings.retryBackoffSeconds)
          .clamp(0, 60),
      preferredVideoQuality: _videoQuality,
      preferredAudioBitrate: _audioBitrate,
      defaultAudioFormat: _downloadFormat,
      previewExpandPlaylist: _expandPlaylist,
      minimizeToTrayOnClose:
          _isDesktopPlatform ? _minimizeToTrayOnClose : false,
      downloadDirMp3: _downloadDirMp3Controller.text.trim().isEmpty
          ? null
          : _downloadDirMp3Controller.text.trim(),
      downloadDirM4a: _downloadDirM4aController.text.trim().isEmpty
          ? null
          : _downloadDirM4aController.text.trim(),
      downloadDirMp4: _downloadDirMp4Controller.text.trim().isEmpty
          ? null
          : _downloadDirMp4Controller.text.trim(),
      downloadDirTorrents: _downloadDirTorrentsController.text.trim().isEmpty
          ? null
          : _downloadDirTorrentsController.text.trim(),
      createFormatSubfolders: _useFormatSubfolders,
      ffmpegPath: ffmpegText.isEmpty ? null : ffmpegText,
      ytDlpPath: ytDlpText.isEmpty ? null : ytDlpText,
      youtubeAuthEnabled: _youtubeAuthEnabled,
      youtubeCookiesFromBrowser: _youtubeCookiesFromBrowser.trim().isEmpty
          ? null
          : _youtubeCookiesFromBrowser.trim(),
      youtubeCookiesFile: _ytCookiesFileController.text.trim().isEmpty
          ? null
          : _ytCookiesFileController.text.trim(),
    );
    await widget.controller.saveSettings(next);
    TrayService.shouldMinimiseToTrayOnClose = next.minimizeToTrayOnClose;
    if (!mounted) return;
    Snack.show(context, context.l10n.settingsSaved,
        level: SnackLevel.success, duration: const Duration(seconds: 2));
  }

  Future<void> _openWebsite() async {
    final launched =
        await launchUrl(_websiteUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      Snack.show(context, context.l10n.couldNotOpenWebsite,
          level: SnackLevel.error);
    }
  }

  Future<void> _showInFolder(String filePath) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        if (filePath.startsWith('content://')) {
          final ok = await _androidSaf.openTree(filePath);
          if (!ok && mounted) {
            Snack.show(context, context.l10n.couldNotOpenSelectedFolder,
                level: SnackLevel.error);
          }
          return;
        }
        try {
          final s = widget.controller.settings;
          final tree = s?.downloadDir;
          if (tree != null && tree.startsWith('content://')) {
            final ok = await _androidSaf.openTree(tree);
            if (!ok && mounted) {
              Snack.show(context, context.l10n.couldNotOpenSelectedFolder,
                  level: SnackLevel.error);
            }
            return;
          }
        } catch (_) {}
      }

      final file = File(filePath);
      final dir = file.parent.path;
      if (Platform.isWindows) {
        unawaited(
          Process.start(
            'explorer.exe',
            ['/select,', filePath],
            mode: ProcessStartMode.detached,
          ),
        );
      } else if (Platform.isMacOS) {
        unawaited(
          Process.start(
            'open',
            ['-R', filePath],
            mode: ProcessStartMode.detached,
          ),
        );
      } else if (Platform.isLinux) {
        unawaited(
          Process.start(
            'xdg-open',
            [dir],
            mode: ProcessStartMode.detached,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Snack.show(context, context.l10n.couldNotOpenFolder(e),
            level: SnackLevel.error);
      }
    }
  }

  Future<void> _shareFile(String filePath, String title) async {
    try {
      var pathToShare = filePath;
      if (!kIsWeb && Platform.isAndroid && filePath.startsWith('content://')) {
        final temp = await _androidSaf.copyToTemp(uri: filePath);
        if (temp == null || temp.isEmpty) {
          if (mounted) {
            Snack.show(context, context.l10n.couldNotPrepareFileSharing,
                level: SnackLevel.error);
          }
          return;
        }
        pathToShare = temp;
      }

      await SharePlus.instance.share(
        ShareParams(files: [XFile(pathToShare)], title: title),
      );
    } catch (e) {
      if (mounted) {
        Snack.show(context, context.l10n.couldNotShareFile(e),
            level: SnackLevel.error);
      }
    }
  }

  // -- Convert tab --------------------------------------------------------

  Widget _buildConvertTab(AppSettings? settings) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.transform),
                      const SizedBox(width: 8),
                      Text(context.l10n.fileConverter,
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: Text(context.l10n.selectFileConvert),
                    onPressed: kIsWeb
                        ? null
                        : () async {
                            AdService.instance.registerInteraction();
                            final result =
                                await FilePicker.platform.pickFiles();
                            if (result == null || result.files.isEmpty) return;
                            final path = result.files.single.path;
                            if (path == null || !mounted) return;
                            setState(() => _convertFile = File(path));
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_convertFile != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withAlpha((0.1 * 255).round()),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withAlpha((0.3 * 255).round())),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.l10n.selectedFile,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  _convertFile!.path
                                      .split(Platform.pathSeparator)
                                      .last,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _convertFile = null),
                            tooltip: context.l10n.clearSelection,
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withAlpha((0.1 * 255).round()),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withAlpha((0.3 * 255).round())),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.file_present,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              context.l10n.noFileSelected,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey('convert-$_convertTarget'),
                    initialValue: _convertTarget,
                    decoration: InputDecoration(
                      labelText: context.l10n.convertFormat,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.transform),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'mp3', child: Text(context.l10n.mp3Audio)),
                      DropdownMenuItem(
                          value: 'm4a', child: Text(context.l10n.m4aAudio)),
                      DropdownMenuItem(
                          value: 'wav', child: Text(context.l10n.wavAudio)),
                      DropdownMenuItem(
                          value: 'flac', child: Text(context.l10n.flacAudio)),
                      DropdownMenuItem(
                          value: 'ogg', child: Text(context.l10n.oggAudio)),
                      DropdownMenuItem(
                          value: 'aac', child: Text(context.l10n.aacAudio)),
                      DropdownMenuItem(
                          value: 'wma', child: Text(context.l10n.wmaAudio)),
                      DropdownMenuItem(
                          value: 'mp4', child: Text(context.l10n.mp4Video)),
                      DropdownMenuItem(
                          value: 'webm', child: Text(context.l10n.webmVideo)),
                      DropdownMenuItem(
                          value: 'mkv', child: Text(context.l10n.mkvVideo)),
                      DropdownMenuItem(
                          value: 'avi', child: Text(context.l10n.aviVideo)),
                      DropdownMenuItem(
                          value: 'mov', child: Text(context.l10n.movVideo)),
                      DropdownMenuItem(
                          value: 'wmv', child: Text(context.l10n.wmvVideo)),
                      DropdownMenuItem(
                          value: 'png', child: Text(context.l10n.pngImage)),
                      DropdownMenuItem(
                          value: 'jpg', child: Text(context.l10n.jpgImage)),
                      DropdownMenuItem(
                          value: 'bmp', child: Text(context.l10n.bmpImage)),
                      DropdownMenuItem(
                          value: 'gif', child: Text(context.l10n.gifImage)),
                      DropdownMenuItem(
                          value: 'tiff', child: Text(context.l10n.tiffImage)),
                      DropdownMenuItem(
                          value: 'webp', child: Text(context.l10n.webpImage)),
                      DropdownMenuItem(
                          value: 'pdf', child: Text(context.l10n.pdfDocument)),
                      DropdownMenuItem(value: 'txt', child: Text(context.l10n.txtText)),
                      DropdownMenuItem(
                          value: 'epub', child: Text(context.l10n.epubEBook)),
                      DropdownMenuItem(
                          value: 'zip', child: Text(context.l10n.zipArchive)),
                      DropdownMenuItem(
                          value: 'cbz', child: Text(context.l10n.cbzComicArchive)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _convertTarget = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      // Converting a video takes a while; without this the
                      // button looked like it had done nothing.
                      icon: _converting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_alt),
                      label: Text(_converting ? context.l10n.converting2 : context.l10n.convertFile),
                      onPressed: (_convertFile == null ||
                              settings == null ||
                              _converting)
                          ? null
                          : () async {
                              AdService.instance.registerInteraction();
                              setState(() => _converting = true);
                              final error = await widget.controller
                                  .convert(_convertFile!, _convertTarget);
                              if (!mounted) return;
                              setState(() => _converting = false);
                              if (error != null) {
                                Snack.show(context, context.l10n.conversionFailed(error),
                                    level: SnackLevel.error);
                              } else {
                                _maybeShowBreakAd();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.controller.convertResults.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: context.success),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.convertedFiles(widget.controller.convertResults.length),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...widget.controller.convertResults.map(
                      (result) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                              child: Icon(Icons.file_present)),
                          title: Text(result.name),
                          subtitle: Text(result.message),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: Text(context.l10n.actionSave),
                            onPressed: () async {
                              final saved = await widget.controller
                                  .saveConvertedResult(result);
                              if (!context.mounted || saved.cancelled) return;
                              final savedTo = saved.location;
                              Snack.show(
                                context,
                                savedTo == null
                                    ? context.l10n.couldNotSaveLogsTab(result.name)
                                    : context.l10n.saved(result.name, savedTo),
                                level: savedTo == null
                                    ? SnackLevel.error
                                    : SnackLevel.success,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -- Logs tab -----------------------------------------------------------

  Widget _buildLogsTab() {
    if (_selectedPageIndex != 10) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<List<String>>(
      valueListenable: widget.controller.logs.logs,
      builder: (context, logs, _) {
        final isNarrow = _isNarrowLayout(context);
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.list_alt),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.l10n.applicationLogs(logs.length),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: Text(context.l10n.clearLogs),
                          onPressed: logs.isEmpty
                              ? null
                              : () {
                                  AdService.instance.registerInteraction();
                                  widget.controller.logs.logs.value = [];
                                },
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.list_alt),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.applicationLogs(logs.length),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: Text(context.l10n.clearLogs),
                          onPressed: logs.isEmpty
                              ? null
                              : () {
                                  widget.controller.logs.logs.value = [];
                                },
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(context.l10n.noLogsYet,
                              style: TextStyle(
                                  fontSize: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text(context.l10n.activityWillLoggedHere,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final isError = log.toLowerCase().contains('error') ||
                            log.toLowerCase().contains('failed');
                        final isWarning = log.toLowerCase().contains('warning');
                        final isSuccess =
                            log.toLowerCase().contains('success') ||
                                log.toLowerCase().contains('completed');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          color: isError
                              ? context.danger.withAlpha((0.1 * 255).round())
                              : isWarning
                                  ? context.warning
                                      .withAlpha((0.1 * 255).round())
                                  : isSuccess
                                      ? context.success
                                          .withAlpha((0.1 * 255).round())
                                      : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  isError
                                      ? Icons.error
                                      : isWarning
                                          ? Icons.warning
                                          : isSuccess
                                              ? Icons.check_circle
                                              : Icons.info,
                                  size: 16,
                                  color: isError
                                      ? context.danger
                                      : isWarning
                                          ? context.warning
                                          : isSuccess
                                              ? context.success
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: isError ? context.danger : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
