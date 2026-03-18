import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import '../utils/snack.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

import '../models/app_settings.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../services/android_saf.dart';
import '../services/shortcut_service.dart';
import '../services/tray_service.dart';
import '../state/app_controller.dart';
import 'bulk_import_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';
import 'guide_screen.dart';
import 'statistics_screen.dart';
import 'watched_playlists_screen.dart';
import 'browser_screen.dart';
import 'support_screen.dart';
// Fix: use the correctly-cased class name exported from player.dart.
import 'player.dart' show PlayerPage, PlayerState;
import '../widgets/browser_shell.dart';
import '../widgets/onboarding_tooltip_service.dart';
import '../widgets/quick_links_page.dart';
import '../widgets/quick_links_service.dart';
import '../services/update_service.dart';
import '../widgets/update_banner.dart';

class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// Sliver delegate used to keep the search bar pinned at the top.
class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minExtent;
  final double maxExtent;
  final Widget child;

  _SearchHeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.child,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
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
  final TextEditingController _workersController = TextEditingController();
  final TextEditingController _retryCountController = TextEditingController();
  final TextEditingController _retryBackoffController = TextEditingController();
  final TextEditingController _ffmpegPathController = TextEditingController();
  final TextEditingController _ytDlpPathController = TextEditingController();
  final TextEditingController _rangeFromController = TextEditingController();
  final TextEditingController _rangeToController = TextEditingController();
  final AndroidSaf _androidSaf = AndroidSaf();

  bool _expandPlaylist = false;
  String _downloadFormat = 'mp3';
  String _videoQuality = '1080p';
  int _audioBitrate = 320;
  bool _settingsInitialized = false;
  bool _minimizeToTrayOnClose = false;
  bool _sponsorBlockEnabled = false;

  // Fix: separate TabController for playlists tab; disposed exactly once.
  late final TabController _playlistTabController;

  File? _convertFile;
  String _convertTarget = 'mp4';
  String _androidDownloadUri = '';
  int _selectedPageIndex = 13;
  DateTime? _lastLocalNavigation;

  final GlobalKey<ScaffoldState> _shellScaffoldKey = GlobalKey<ScaffoldState>();
  final List<int> _navHistory = [13];
  int _navHistoryIndex = 0;
  bool _queueOnRight = true;

  final OnboardingTooltipService _onboarding = OnboardingTooltipService();
  String? _dismissedBannerRoute;

  UpdateInfo? _updateInfo;
  bool _updateBannerDismissed = false;
  bool _checkUpdatesOnLaunch = true;


  TrayService? _trayService;

  String _previewPreset = '25';
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool _isNarrowLayout(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  final Set<int> _visitedPages = {13};

  int _addRangeFrom = 1;
  int _addRangeTo = 1;

  @override
  void initState() {
    super.initState();
    // Fix: initialise _playlistTabController in initState to avoid
    // "used before init" issues when the widget tree is first built.
    _playlistTabController = TabController(length: 2, vsync: this);

    _onboarding.init().then((_) {
      if (mounted) setState(() {});
    });


    _initDesktopFeatures();

    try {
      _selectedPageIndex = widget.controller.activeTabIndex;
    } catch (_) {}

    if (kDebugMode) {
      debugPrint('[NAV] QuickLinks routeToIndex keys: ' +
          QuickLinksService.routeToIndex.keys.join(', '));
    }

    UpdateService.isCheckOnLaunchEnabled().then((v) {
      if (mounted) setState(() => _checkUpdatesOnLaunch = v);
    });

    _checkForUpdate();
  }

  Future<void> _checkForUpdate({bool force = false}) async {
    try {
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

    _trayService = TrayService(shouldMinimiseToTray: () => true);

    _trayService!.onTrayQuit = () async {
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
    _trayService?.destroy();
    // Fix: each controller is disposed exactly once here.
    _playlistTabController.dispose();
    _urlController.dispose();
    _downloadDirController.dispose();
    _workersController.dispose();
    _retryCountController.dispose();
    _retryBackoffController.dispose();
    _ffmpegPathController.dispose();
    _ytDlpPathController.dispose();
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
          onDownload: (result, format) =>
              widget.controller.addSearchResultToQueue(result, format: format),
        );
      case 2:
        return BrowserScreen(
          key: BrowserScreen.browserKey,
          onAddToQueue: widget.controller.addSearchResultToQueue,
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
      // Fix: case 12 now uses PlayerPage (correctly-cased class name).
      case 12:
        return const PlayerPage(key: ValueKey('player-player'));
      case 13:
        return QuickLinksPage(
          key: const ValueKey('quick-links-home'),
          onNavigate: (route) {
            final idx = QuickLinksService.routeToIndex[route];
            if (idx != null) _navigateToPage(idx);
          },
          onDownload: (result, format, quality) async {
            widget.controller.addSearchResultToQueue(
              result,
              format: format,
              videoQuality: quality,
            );
            _navigateToPage(3); // show queue
          },
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
      default:
        return _buildSearchTab(settings);
    }
  }

  // ── Navigation helpers ──────────────────────────────────────────────────

  bool get _canGoBack => _navHistoryIndex > 0;
  bool get _canGoForward => _navHistoryIndex < _navHistory.length - 1;

  void _navigateToPage(int index) {
    if (index < 0 || index > 13) return;
    if (index == _selectedPageIndex) return;
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
    try {
      widget.controller.switchToTab(index);
    } catch (_) {}
    _lastLocalNavigation = DateTime.now();
  }

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _navHistoryIndex--;
      _selectedPageIndex = _navHistory[_navHistoryIndex];
      _visitedPages.add(_selectedPageIndex);
    });
    try {
      widget.controller.switchToTab(_selectedPageIndex);
    } catch (_) {}
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      _navHistoryIndex++;
      _selectedPageIndex = _navHistory[_navHistoryIndex];
      _visitedPages.add(_selectedPageIndex);
    });
    try {
      widget.controller.switchToTab(_selectedPageIndex);
    } catch (_) {}
  }

  void _navigateHome() => _navigateToPage(13);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
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
          scaffoldKey: _shellScaffoldKey,
          currentIndex: _selectedPageIndex,
          queueWidget: _buildQueueTab(),
          onNavigate: (route) {
            if (kDebugMode) debugPrint('[NAV] requested route: "$route"');
            if (route == 'home') {
              _navigateHome();
              return;
            }

            var idx = QuickLinksService.routeToIndex[route];

            if (idx == null && !route.endsWith('.tab')) {
              idx = QuickLinksService.routeToIndex['$route.tab'];
            }

            if (idx == null) {
              final lower = route.toLowerCase();
              for (final entry in QuickLinksService.indexToTitle.entries) {
                if (entry.value.toLowerCase() == lower) {
                  idx = entry.key;
                  break;
                }
              }
            }

            if (idx != null) {
              if (kDebugMode) debugPrint('[NAV] resolved "$route" -> $idx');
              _navigateToPage(idx);
            } else {
              if (kDebugMode) {
                debugPrint('[NAV] WARNING: no index for route "$route"');
              }
            }
          },
          onBack: _canGoBack ? _goBack : null,
          onForward: _canGoForward ? _goForward : null,
          onRefresh: () => setState(() {}),
          canGoBack: _canGoBack,
          canGoForward: _canGoForward,
          queueOnRight: _queueOnRight,
          queueCount: widget.controller.queue.length,
          onHome: _navigateHome,
          onOpenUrl: openBrowserWith,
          child: _buildPageWithBanner(settings),
        );

        final popWrapped = PopScope(
          canPop: _selectedPageIndex == 13,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _selectedPageIndex != 13) {
              setState(() => _selectedPageIndex = 13);
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
            child: Focus(
              autofocus: true,
              child: popWrapped,
            ),
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
        ? OnboardingTooltipService.screenDescriptions[route]
        : null;

    final stack = IndexedStack(
      index: _selectedPageIndex,
      children: List.generate(14, (i) {
        if (!_visitedPages.contains(i)) {
          return const SizedBox.shrink();
        }
        return _buildPageContent(i, settings);
      }),
    );

    if (_updateInfo != null && !_updateBannerDismissed) {
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

  void _initSettings(AppSettings settings) {
    setState(() {
      if (_isAndroid) {
        _androidDownloadUri = settings.downloadDir;
        _downloadDirController.text =
            _formatAndroidFolderLabel(settings.downloadDir);
      } else {
        _downloadDirController.text = settings.downloadDir;
      }
      _workersController.text = settings.maxWorkers.toString();
      _retryCountController.text = settings.retryCount.toString();
      _retryBackoffController.text = settings.retryBackoffSeconds.toString();
      _ffmpegPathController.text = settings.ffmpegPath ?? '';
      _ytDlpPathController.text = settings.ytDlpPath ?? '';
      _expandPlaylist = settings.previewExpandPlaylist;
      _downloadFormat = settings.defaultAudioFormat;
      _videoQuality = settings.preferredVideoQuality;
      _audioBitrate = settings.preferredAudioBitrate;
      _sponsorBlockEnabled = settings.sponsorBlockEnabled;
      _minimizeToTrayOnClose = settings.minimizeToTrayOnClose;
      TrayService.shouldMinimiseToTrayOnClose = _minimizeToTrayOnClose;
      _settingsInitialized = true;
    });

    try {
      widget.controller.downloadService.onSafAccessDenied = () async {
        if (!mounted) return null;

        final choose = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Folder access lost'),
            content: const Text(
              'The app can no longer access your selected download folder. '
              'Would you like to pick it again? Choosing "No" will use Downloads instead.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Use Downloads'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Pick folder'),
              ),
            ],
          ),
        );

        if (choose != true) return null;

        final uri = await _androidSaf.pickTree();
        if (uri == null || uri.isEmpty) return null;

        final current = widget.controller.settings;
        if (current != null) {
          await widget.controller
              .saveSettings(current.copyWith(downloadDir: uri));
        }

        if (!mounted) return uri;
        setState(() {
          _androidDownloadUri = uri;
          _downloadDirController.text = _formatAndroidFolderLabel(uri);
        });
        Snack.show(context, 'Download folder updated', level: SnackLevel.info);
        return uri;
      };
    } catch (_) {}
  }

  void openBrowserWith(String url) {
    _navigateToPage(2);
    BrowserScreen.navigate(url);
  }

  String _formatAndroidFolderLabel(String uriString) {
    if (uriString.trim().isEmpty) return 'Not set';
    if (!uriString.startsWith('content://')) return uriString;
    final decoded = Uri.decodeComponent(uriString);
    final treeIndex = decoded.indexOf('tree/');
    if (treeIndex >= 0) {
      final treePart = decoded.substring(treeIndex + 5);
      return treePart.replaceAll(':', '/');
    }
    return uriString;
  }

  bool get _hasAndroidFolder => _androidDownloadUri.startsWith('content://');

  Future<void> _pickAndroidFolder(AppSettings settings) async {
    final uri = await _androidSaf.pickTree();
    if (uri == null || uri.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _androidDownloadUri = uri;
      _downloadDirController.text = _formatAndroidFolderLabel(uri);
    });
    await widget.controller.saveSettings(settings.copyWith(downloadDir: uri));
    if (mounted) {
      Snack.show(context, 'Download folder updated', level: SnackLevel.info);
    }
  }

  Future<void> _pickDownloadFolder(AppSettings settings) async {
    if (_isAndroid) {
      await _pickAndroidFolder(settings);
      return;
    }

    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null || !mounted) return;

    setState(() {
      _downloadDirController.text = result;
    });

    await widget.controller.saveSettings(settings.copyWith(downloadDir: result));
    if (mounted) {
      Snack.show(context, 'Download folder updated', level: SnackLevel.info);
    }
  }

  Future<void> _openAndroidFolder() async {
    if (!_hasAndroidFolder) return;
    final ok = await _androidSaf.openTree(_androidDownloadUri);
    if (!ok && mounted) {
      Snack.show(context, 'Could not open the selected folder.',
          level: SnackLevel.error);
    }
  }

  Future<void> _clearAndroidFolder(AppSettings settings) async {
    setState(() {
      _androidDownloadUri = '';
      _downloadDirController.text = 'Not set';
    });
    await widget.controller.saveSettings(settings.copyWith(downloadDir: ''));
  }

  // ── Search tab ─────────────────────────────────────────────────────────

  Widget _buildSearchTab(AppSettings? settings) {
    final isNarrow = _isNarrowLayout(context);

    // Keep the top search row pinned while the rest of the UI scrolls.
    final searchHeader = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'YouTube URL',
                border: const OutlineInputBorder(),
                hintText: 'Enter or paste a YouTube URL',
                prefixIcon: const Icon(Icons.link),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _urlController.clear());
                        },
                        tooltip: 'Clear URL',
                      )
                    : null,
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final clipboardData = await Clipboard.getData('text/plain');
              if (!mounted) return;
              if (clipboardData?.text != null) {
                setState(() => _urlController.text = clipboardData!.text!);
              }
            },
            tooltip: 'Paste from clipboard',
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
                            Text('Download Options',
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
                                decoration: const InputDecoration(
                                  labelText: 'Format',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.audio_file),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                                  DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                                  DropdownMenuItem(
                                      value: 'mp4', child: Text('MP4 (Video)')),
                                ],
                                onChanged: (value) {
                                  if (value != null)
                                    setState(() => _downloadFormat = value);
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                key: ValueKey('vq-narrow-$_videoQuality'),
                                initialValue: _videoQuality,
                                decoration: const InputDecoration(
                                  labelText: 'Video Quality',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.high_quality),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: '360p', child: Text('360p')),
                                  DropdownMenuItem(
                                      value: '480p', child: Text('480p')),
                                  DropdownMenuItem(
                                      value: '720p', child: Text('720p (HD)')),
                                  DropdownMenuItem(
                                      value: '1080p', child: Text('1080p (Full HD)')),
                                  DropdownMenuItem(
                                      value: '1440p', child: Text('1440p (2K)')),
                                  DropdownMenuItem(
                                      value: '2160p', child: Text('2160p (4K)')),
                                  DropdownMenuItem(
                                      value: '4320p', child: Text('4320p (8K)')),
                                  DropdownMenuItem(
                                      value: 'best', child: Text('Best Available')),
                                ],
                                onChanged: (value) {
                                  if (value != null)
                                    setState(() => _videoQuality = value);
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                key: ValueKey('abr-narrow-$_audioBitrate'),
                                initialValue: _audioBitrate,
                                decoration: const InputDecoration(
                                  labelText: 'Audio Bitrate',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.equalizer),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 128, child: Text('128 kbps')),
                                  DropdownMenuItem(
                                      value: 192, child: Text('192 kbps')),
                                  DropdownMenuItem(
                                      value: 256, child: Text('256 kbps')),
                                  DropdownMenuItem(
                                      value: 320, child: Text('320 kbps')),
                                ],
                                onChanged: (value) {
                                  if (value != null)
                                    setState(() => _audioBitrate = value);
                                },
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _expandPlaylist,
                                onChanged: (value) {
                                  setState(() => _expandPlaylist = value ?? false);
                                },
                                title: const Text('Expand playlist'),
                                subtitle: const Text('Show all videos'),
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
                                      key: ValueKey('fmt-wide-$_downloadFormat'),
                                      initialValue: _downloadFormat,
                                      decoration: const InputDecoration(
                                        labelText: 'Format',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.audio_file),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'mp3', child: Text('MP3')),
                                        DropdownMenuItem(
                                            value: 'm4a', child: Text('M4A')),
                                        DropdownMenuItem(
                                            value: 'mp4', child: Text('MP4 (Video)')),
                                      ],
                                      onChanged: (value) {
                                        if (value != null)
                                          setState(() => _downloadFormat = value);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      key: ValueKey('vq-wide-$_videoQuality'),
                                      initialValue: _videoQuality,
                                      decoration: const InputDecoration(
                                        labelText: 'Video Quality',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.high_quality),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: '360p', child: Text('360p')),
                                        DropdownMenuItem(
                                            value: '480p', child: Text('480p')),
                                        DropdownMenuItem(
                                            value: '720p', child: Text('720p (HD)')),
                                        DropdownMenuItem(
                                            value: '1080p',
                                            child: Text('1080p (Full HD)')),
                                        DropdownMenuItem(
                                            value: 'best',
                                            child: Text('Best Available')),
                                      ],
                                      onChanged: (value) {
                                        if (value != null)
                                          setState(() => _videoQuality = value);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      key: ValueKey('abr-wide-$_audioBitrate'),
                                      initialValue: _audioBitrate,
                                      decoration: const InputDecoration(
                                        labelText: 'Audio Bitrate',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.equalizer),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 128, child: Text('128 kbps')),
                                        DropdownMenuItem(
                                            value: 192, child: Text('192 kbps')),
                                        DropdownMenuItem(
                                            value: 256, child: Text('256 kbps')),
                                        DropdownMenuItem(
                                            value: 320, child: Text('320 kbps')),
                                      ],
                                      onChanged: (value) {
                                        if (value != null)
                                          setState(() => _audioBitrate = value);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                value: _expandPlaylist,
                                onChanged: (value) {
                                  setState(() => _expandPlaylist = value ?? false);
                                },
                                title: const Text('Expand playlist'),
                                subtitle: const Text('Show all videos'),
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
                              Text('Playlist Options',
                                  style: Theme.of(context).textTheme.titleMedium),
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
                                  decoration: const InputDecoration(
                                    labelText: 'Preview amount',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.format_list_numbered),
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '10', child: Text('First 10')),
                                    DropdownMenuItem(
                                        value: '25', child: Text('First 25')),
                                    DropdownMenuItem(
                                        value: '50', child: Text('First 50')),
                                    DropdownMenuItem(
                                        value: '100', child: Text('First 100')),
                                    DropdownMenuItem(
                                        value: 'all', child: Text('All')),
                                    DropdownMenuItem(
                                        value: 'custom',
                                        child: Text('Custom range...')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null)
                                      setState(() => _previewPreset = value);
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
                                    decoration: const InputDecoration(
                                      labelText: 'From #',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.first_page),
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
                                  child: Text('to', style: TextStyle(fontSize: 16)),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _rangeToController,
                                    decoration: const InputDecoration(
                                      labelText: 'To #',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.last_page),
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
                              'Video numbers are 1-based (e.g. 1 to 25 = first 25 videos)',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                                  'YouTube Mix playlists (IDs starting with RD) cannot be expanded.',
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
                          label: const Text('Search / Preview'),
                          onPressed:
                              settings == null || _urlController.text.trim().isEmpty
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
                          label: const Text('Download'),
                          onPressed:
                              settings == null || _urlController.text.trim().isEmpty
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
                          label: const Text('Search / Preview'),
                          onPressed:
                              settings == null || _urlController.text.trim().isEmpty
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
                          label: const Text('Download'),
                          onPressed:
                              settings == null || _urlController.text.trim().isEmpty
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
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading preview...'),
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
        'Android needs a download folder set to work properly. Tap "Set folder" below.',
        level: SnackLevel.warning,
        actionLabel: 'Go to Settings',
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
      'Please select a download folder in Settings first.',
      level: SnackLevel.warning,
      actionLabel: 'Go to Settings',
      onAction: () => _navigateToPage(7),
      duration: const Duration(seconds: 4),
    );
    _navigateToPage(7);
    return false;
  }

  void _downloadUrl(AppSettings settings) {
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

  // ── Preview list ───────────────────────────────────────────────────────

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
                'No preview results yet.',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a YouTube URL above and click Search',
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
                      'Preview Results (${items.length})',
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
                    label: const Text('Add All'),
                    onPressed: () {
                      for (final item in items) {
                        widget.controller
                            .addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      Snack.show(
                          context, 'Added ${items.length} items to queue',
                          level: SnackLevel.info);
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download All'),
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
                    'Preview Results (${items.length})',
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
                    label: const Text('Add All'),
                    onPressed: () {
                      for (final item in items) {
                        widget.controller
                            .addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      Snack.show(
                          context, 'Added ${items.length} items to queue',
                          level: SnackLevel.info);
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download All'),
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
                    'Add range to queue',
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
                      const Text('From '),
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
                        label: Text('Add ${_addRangeTo - _addRangeFrom + 1}'),
                        onPressed: () {
                          final subset =
                              items.sublist(_addRangeFrom - 1, _addRangeTo);
                          for (final item in subset) {
                            widget.controller.addToQueue(
                                item, _downloadFormat.toLowerCase());
                          }
                          Snack.show(
                              context, 'Added ${subset.length} items to queue',
                              level: SnackLevel.info);
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download, size: 18),
                        label:
                            Text('Download ${_addRangeTo - _addRangeFrom + 1}'),
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
                                  Snack.show(context, 'Added to queue',
                                      level: SnackLevel.info,
                                      duration: const Duration(seconds: 1));
                                },
                                tooltip: 'Add to queue',
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('Download'),
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
                            label: const Text('Add to queue'),
                            onPressed: () {
                              widget.controller.addToQueue(
                                  item, _downloadFormat.toLowerCase());
                              Snack.show(context, 'Added to queue',
                                  level: SnackLevel.info,
                                  duration: const Duration(seconds: 1));
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Download'),
                            onPressed: () {
                              final s = widget.controller.settings;
                              if (s != null && !_ensureDownloadFolder(s))
                                return;
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

  // ── Queue tab ──────────────────────────────────────────────────────────

  Widget _buildQueueTab() {
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
              'No items in queue',
              style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Add items from the Search tab',
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
        return Column(
          children: [
            _buildQueueHeader(
                items, inProgressCount, completedCount, isCompact),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.all(isCompact ? 8 : 16),
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
                      'Queue',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 14 : 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${items.length} total \u2022 $inProgressCount active \u2022 $completedCount done',
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
                    label: Text(isCompact ? 'All' : 'Download All',
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
                    label: Text(isCompact ? 'Clear' : 'Clear Queue',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: items.isEmpty
                        ? null
                        : () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Clear Queue'),
                                content: const Text(
                                    'Remove all items from the queue?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
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
                                    child: const Text('Clear'),
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

    return Card(
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
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
                        Text('Speed: ${item.speed}',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      if (item.eta != null) ...[
                        const SizedBox(width: 12),
                        Text('ETA: ${item.eta}',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
                  _queueAction(Icons.download_rounded, 'Download',
                      Theme.of(context).colorScheme.primary, () {
                    final s = widget.controller.settings;
                    if (s != null && !_ensureDownloadFolder(s)) return;
                    widget.controller.downloadSingle(item);
                  }),
                if (item.status == DownloadStatus.downloading ||
                    item.status == DownloadStatus.converting)
                  _queueAction(Icons.stop_rounded, 'Cancel', context.warning,
                      () => widget.controller.cancelDownload(item)),
                if (item.status == DownloadStatus.cancelled ||
                    item.status == DownloadStatus.failed)
                  _queueAction(
                      Icons.play_arrow_rounded, 'Resume', context.success, () {
                    final s = widget.controller.settings;
                    if (s != null && !_ensureDownloadFolder(s)) return;
                    widget.controller.resumeDownload(item);
                  }),
                if (item.status == DownloadStatus.completed &&
                    item.outputPath != null &&
                    !kIsWeb)
                  _queueAction(
                      Icons.folder_open_rounded,
                      'Folder',
                      Theme.of(context).colorScheme.primary,
                      () => _showInFolder(item.outputPath!)),
                if (item.status == DownloadStatus.completed &&
                    item.outputPath != null &&
                    !kIsWeb &&
                    Platform.isAndroid)
                  _queueAction(
                      Icons.share_rounded,
                      'Share',
                      Theme.of(context).colorScheme.primary,
                      () => _shareFile(item.outputPath!, item.title)),
                if (item.status != DownloadStatus.downloading &&
                    item.status != DownloadStatus.converting)
                  _queueAction(
                      Icons.delete_outline_rounded,
                      'Remove',
                      context.danger,
                      () => widget.controller.removeFromQueue(item)),
              ],
            ),
            if (item.error != null && item.status == DownloadStatus.failed) ...[
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

  // ── Playlists tab ──────────────────────────────────────────────────────

  Widget _buildPlaylistsTab() {
    return Column(
      children: [
        TabBar(
          controller: _playlistTabController,
          tabs: const [
            Tab(text: 'Playlist Manager'),
            Tab(text: 'Watched Playlists'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _playlistTabController,
            children: [
              PlaylistScreen(
                playlistService: widget.controller.playlistService,
                onDownloadMissing: (tracks, format) {
                  for (final t in tracks) {
                    widget.controller.addSearchResultToQueue(t, format: format);
                  }
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

  // ── Settings tab ───────────────────────────────────────────────────────

  Widget _buildSettingsTab(AppSettings? settings) {
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
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
              label: const Text('Save Settings'),
              onPressed: () => _saveAllSettings(settings),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),

          // Close-to-tray behavior
          SwitchListTile(
            title: const Text('Minimize to tray on close'),
            subtitle: const Text(
              'Keep the app running in the background when you close the window.',
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
                          color:
                              Theme.of(context).colorScheme.primaryContainer,
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
                            Text('Support the Project',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              'Help keep this app open-source and ad-free by donating.',
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
                          child: const Text('Buy Me a Coffee'),
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
                                  'Could not open GitHub Sponsors link.',
                                  level: SnackLevel.error);
                            }
                          },
                          child: const Text('GitHub Sponsors'),
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
                      Text('Download Settings',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (_isAndroid) ...[
                    TextField(
                      controller: _downloadDirController,
                      decoration: const InputDecoration(
                        labelText: 'Download folder',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.folder),
                        helperText:
                            'Pick a folder using the system file picker. If not set, files go to Downloads/ConvertTheSpireReborn.',
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
                              ? 'Change folder'
                              : 'Choose folder'),
                          onPressed: () => _pickAndroidFolder(settings),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.folder),
                          label: const Text('Open folder'),
                          onPressed:
                              _hasAndroidFolder ? _openAndroidFolder : null,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
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
                          'No folder selected. Downloads will be saved to Downloads/ConvertTheSpireReborn.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: context.warning),
                        ),
                      ),
                  ] else ...[
                    if (isNarrow)
                      Column(
                        children: [
                          TextField(
                            controller: _downloadDirController,
                            decoration: const InputDecoration(
                              labelText: 'Download folder',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.folder),
                            ),
                            readOnly: true,
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Browse'),
                              onPressed: () async {
                                final result = await FilePicker.platform
                                    .getDirectoryPath();
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
                              decoration: const InputDecoration(
                                labelText: 'Download folder',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.folder),
                              ),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Browse'),
                            onPressed: () async {
                              final result =
                                  await FilePicker.platform.getDirectoryPath();
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
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _workersController,
                    decoration: const InputDecoration(
                      labelText: 'Parallel workers (1-10)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.settings_ethernet),
                      hintText: 'Number of concurrent downloads',
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
                    title: const Text('Show notifications'),
                    subtitle: const Text(
                        'Display notifications when downloads complete'),
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
                      Text('Quality Settings',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (isNarrow) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('settings-vq-$_videoQuality'),
                      initialValue: _videoQuality,
                      decoration: const InputDecoration(
                        labelText: 'Video Quality',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.videocam),
                        helperText:
                            'High resolutions (1080p+/4K/8K) download separate video + audio and merge using FFmpeg (requires yt-dlp).',
                        helperMaxLines: 2,
                      ),
                      items: const [
                        DropdownMenuItem(value: '360p', child: Text('360p')),
                        DropdownMenuItem(value: '480p', child: Text('480p')),
                        DropdownMenuItem(
                            value: '720p', child: Text('720p (HD)')),
                        DropdownMenuItem(
                            value: '1080p', child: Text('1080p (Full HD)')),
                        DropdownMenuItem(
                            value: 'best', child: Text('Best Available')),
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
                      decoration: const InputDecoration(
                        labelText: 'Audio Bitrate',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.equalizer),
                        helperText:
                            'Higher bitrate = better quality, larger file size',
                        helperMaxLines: 2,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 128, child: Text('128 kbps (Compact)')),
                        DropdownMenuItem(
                            value: 192, child: Text('192 kbps (Standard)')),
                        DropdownMenuItem(
                            value: 256, child: Text('256 kbps (High)')),
                        DropdownMenuItem(
                            value: 320, child: Text('320 kbps (Maximum)')),
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
                            decoration: const InputDecoration(
                              labelText: 'Video Quality',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.videocam),
                              helperText: 'High resolutions (1080p+/4K/8K) merge separate video + audio streams (requires yt-dlp + FFmpeg)',
                              helperMaxLines: 2,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: '360p', child: Text('360p')),
                              DropdownMenuItem(
                                  value: '480p', child: Text('480p')),
                              DropdownMenuItem(
                                  value: '720p', child: Text('720p (HD)')),
                              DropdownMenuItem(
                                  value: '1080p',
                                  child: Text('1080p (Full HD)')),
                              DropdownMenuItem(
                                  value: '1440p', child: Text('1440p (2K)')),
                              DropdownMenuItem(
                                  value: '2160p', child: Text('2160p (4K)')),
                              DropdownMenuItem(
                                  value: '4320p', child: Text('4320p (8K)')),
                              DropdownMenuItem(
                                  value: 'best', child: Text('Best Available')),
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
                            decoration: const InputDecoration(
                              labelText: 'Audio Bitrate',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.equalizer),
                              helperText: 'Higher = better quality',
                              helperMaxLines: 2,
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 128,
                                  child: Text('128 kbps (Compact)')),
                              DropdownMenuItem(
                                  value: 192,
                                  child: Text('192 kbps (Standard)')),
                              DropdownMenuItem(
                                  value: 256, child: Text('256 kbps (High)')),
                              DropdownMenuItem(
                                  value: 320,
                                  child: Text('320 kbps (Maximum)')),
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
                        Text('FFmpeg',
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
                              labelText: 'FFmpeg path',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.terminal),
                              hintText: _ffmpegPathController.text.isEmpty
                                  ? 'Auto-installed on first use'
                                  : null,
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Browse'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.any,
                              dialogTitle: 'Select FFmpeg executable',
                            );
                            if (result != null &&
                                result.files.single.path != null &&
                                mounted) {
                              setState(() => _ffmpegPathController.text =
                                  result.files.single.path!);
                              final s = widget.controller.settings;
                              if (s != null) {
                                widget.controller.saveSettings(s.copyWith(
                                    ffmpegPath: result.files.single.path!));
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
                          'Will be installed automatically when needed.',
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ytDlpPathController,
                            decoration: InputDecoration(
                              labelText: 'yt-dlp path',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.terminal),
                              hintText: _ytDlpPathController.text.isEmpty
                                  ? 'Auto-downloaded on first use'
                                  : null,
                            ),
                            readOnly: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Browse'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.any,
                              dialogTitle: 'Select yt-dlp executable',
                            );
                            if (result != null &&
                                result.files.single.path != null &&
                                mounted) {
                              setState(() => _ytDlpPathController.text =
                                  result.files.single.path!);
                              final s = widget.controller.settings;
                              if (s != null) {
                                widget.controller.saveSettings(s.copyWith(
                                    ytDlpPath: result.files.single.path!));
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.update),
                          label: const Text('Update'),
                          onPressed: () async {
                            final s = widget.controller.settings;
                            if (s == null) return;
                            final current = s.ytDlpPath;
                            Snack.show(context, 'Updating yt-dlp...',
                                level: SnackLevel.info);
                            try {
                              final updated =
                                  await widget.controller.downloadService.ytDlp
                                      .update(
                                configuredPath: current,
                                onProgress: (pct, msg) {
                                  if (pct % 25 == 0 || pct == 100) {
                                    Snack.show(context,
                                        'yt-dlp: $msg ($pct%)',
                                        level: SnackLevel.info);
                                  }
                                },
                              );
                              if (mounted) {
                                setState(() {
                                  _ytDlpPathController.text = updated;
                                });
                              }
                              await widget.controller
                                  .saveSettings(s.copyWith(ytDlpPath: updated));
                              Snack.show(context, 'yt-dlp updated successfully',
                                  level: SnackLevel.success);
                            } catch (e) {
                              Snack.show(context,
                                  'Failed to update yt-dlp: ${e.toString()}',
                                  level: SnackLevel.error);
                            }
                          },
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
                          await widget.controller
                              .saveSettings(s.copyWith(sponsorBlockEnabled: value));
                        }
                      },
                      title: const Text('Use SponsorBlock'),
                      subtitle: const Text(
                          'Automatically remove sponsored/intro/outro segments when downloading videos.'),
                      secondary: const Icon(Icons.remove_red_eye),
                    ),
                    if (_ytDlpPathController.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Will be downloaded automatically on first launch.',
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
                      Text('Retry Settings',
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
                    title: const Text('Auto-retry installs'),
                    subtitle:
                        const Text('Automatically retry failed downloads'),
                    secondary: const Icon(Icons.replay),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retryCountController,
                    decoration: const InputDecoration(
                      labelText: 'Retry count (0-10)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repeat),
                      hintText: 'Number of retry attempts',
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
                    decoration: const InputDecoration(
                      labelText: 'Retry backoff seconds (0-60)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timelapse),
                      hintText: 'Wait time between retries',
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
                      Text('Appearance',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'system',
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(
                          value: 'light',
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode)),
                      ButtonSegment(
                          value: 'dark',
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (value) {
                      widget.controller.saveSettings(
                          settings.copyWith(themeMode: value.first));
                    },
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
                      Text('About',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Convert the Spire Reborn',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'A Red Bull Basement / SpireAI project',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cross-platform media toolkit with multi-site downloads, '
                    'format conversion, and DLNA casting — built with Flutter.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Copyright (c) 2026 Oroka Conner. Licensed under GPLv3.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.coffee),
                        label: const Text('Buy me a coffee'),
                        onPressed: _openBuyMeCoffee,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.public),
                        label: const Text('Visit quizthespire.com'),
                        onPressed: _openWebsite,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.code),
                        label: const Text('GitHub'),
                        onPressed: () async {
                          final launched = await launchUrl(
                            Uri.parse(
                                'https://github.com/Lukas-Bohez/ConvertTheSpireFlutter'),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!launched && mounted) {
                            Snack.show(
                                context, 'Could not open the GitHub link.',
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
                      Text('Browser Shell',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _queueOnRight,
                    onChanged: (value) => setState(() => _queueOnRight = value),
                    title: const Text('Queue sidebar on right'),
                    subtitle: Text(_queueOnRight
                        ? 'Queue panel on the right side'
                        : 'Queue panel on the left side'),
                    secondary: Icon(
                        _queueOnRight ? Icons.border_right : Icons.border_left),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: const Text('Go to Home page'),
                    subtitle: const Text('Navigate to quick links home'),
                    onTap: () => _navigateToPage(13),
                  ),
                  ListTile(
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('Reset quick links'),
                    subtitle: const Text('Restore default quick links'),
                    onTap: () async {
                      await QuickLinksService.resetToDefaults();
                      if (mounted) {
                        Snack.show(context, 'Quick links reset to defaults',
                            level: SnackLevel.info);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.school),
                    title: const Text('Replay tutorial tips'),
                    subtitle: const Text('Show screen descriptions again'),
                    onTap: () async {
                      await _onboarding.reset();
                      setState(() => _dismissedBannerRoute = null);
                      if (mounted) {
                        Snack.show(context,
                            'Tutorial tips will show again on each screen',
                            level: SnackLevel.info);
                      }
                    },
                  ),
                  // Update check toggle
                  SwitchListTile(
                    value: _checkUpdatesOnLaunch,
                    onChanged: (value) async {
                      await UpdateService.setCheckOnLaunch(value);
                      if (mounted)
                        setState(() => _checkUpdatesOnLaunch = value);
                    },
                    title: const Text('Check for updates on launch'),
                    secondary: const Icon(Icons.system_update_alt),
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('Check for updates now'),
                    onTap: () => _checkForUpdate(force: true),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
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
      Snack.show(context, 'Could not open the Buy Me a Coffee link.',
          level: SnackLevel.error);
    }
  }

  /// Toggle mining support.
  /// Fix: removed the inverted Android check — mining is simply skipped on Android.

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
      minimizeToTrayOnClose: _minimizeToTrayOnClose,
      ffmpegPath: ffmpegText.isEmpty ? null : ffmpegText,
      ytDlpPath: ytDlpText.isEmpty ? null : ytDlpText,
    );
    await widget.controller.saveSettings(next);
    TrayService.shouldMinimiseToTrayOnClose = next.minimizeToTrayOnClose;
    if (!mounted) return;
    Snack.show(context, 'Settings saved',
        level: SnackLevel.success, duration: const Duration(seconds: 2));
  }

  Future<void> _openWebsite() async {
    final launched =
        await launchUrl(_websiteUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      Snack.show(context, 'Could not open the website.',
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
            Snack.show(context, 'Could not open the selected folder.',
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
              Snack.show(context, 'Could not open the selected folder.',
                  level: SnackLevel.error);
            }
            return;
          }
        } catch (_) {}
      }

      final file = File(filePath);
      final dir = file.parent.path;
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
      }
    } catch (e) {
      if (mounted) {
        Snack.show(context, 'Could not open folder: $e',
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
            Snack.show(context, 'Could not prepare file for sharing.',
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
        Snack.show(context, 'Could not share file: $e',
            level: SnackLevel.error);
      }
    }
  }

  // ── Convert tab ────────────────────────────────────────────────────────

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
                      Text('File Converter',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Select file to convert'),
                    onPressed: kIsWeb
                        ? null
                        : () async {
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
                                const Text('Selected file:',
                                    style: TextStyle(
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
                            tooltip: 'Clear selection',
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
                              'No file selected',
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
                    decoration: const InputDecoration(
                      labelText: 'Convert to format',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.transform),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'mp3', child: Text('MP3 (Audio)')),
                      DropdownMenuItem(
                          value: 'm4a', child: Text('M4A (Audio)')),
                      DropdownMenuItem(
                          value: 'wav', child: Text('WAV (Audio)')),
                      DropdownMenuItem(
                          value: 'flac', child: Text('FLAC (Audio)')),
                      DropdownMenuItem(
                          value: 'ogg', child: Text('OGG (Audio)')),
                      DropdownMenuItem(
                          value: 'aac', child: Text('AAC (Audio)')),
                      DropdownMenuItem(
                          value: 'wma', child: Text('WMA (Audio)')),
                      DropdownMenuItem(
                          value: 'mp4', child: Text('MP4 (Video)')),
                      DropdownMenuItem(
                          value: 'webm', child: Text('WebM (Video)')),
                      DropdownMenuItem(
                          value: 'mkv', child: Text('MKV (Video)')),
                      DropdownMenuItem(
                          value: 'avi', child: Text('AVI (Video)')),
                      DropdownMenuItem(
                          value: 'mov', child: Text('MOV (Video)')),
                      DropdownMenuItem(
                          value: 'wmv', child: Text('WMV (Video)')),
                      DropdownMenuItem(
                          value: 'png', child: Text('PNG (Image)')),
                      DropdownMenuItem(
                          value: 'jpg', child: Text('JPG (Image)')),
                      DropdownMenuItem(
                          value: 'bmp', child: Text('BMP (Image)')),
                      DropdownMenuItem(
                          value: 'gif', child: Text('GIF (Image)')),
                      DropdownMenuItem(
                          value: 'tiff', child: Text('TIFF (Image)')),
                      DropdownMenuItem(
                          value: 'webp', child: Text('WebP (Image)')),
                      DropdownMenuItem(
                          value: 'pdf', child: Text('PDF (Document)')),
                      DropdownMenuItem(value: 'txt', child: Text('TXT (Text)')),
                      DropdownMenuItem(
                          value: 'epub', child: Text('EPUB (E-book)')),
                      DropdownMenuItem(
                          value: 'zip', child: Text('ZIP (Archive)')),
                      DropdownMenuItem(
                          value: 'cbz', child: Text('CBZ (Comic Archive)')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _convertTarget = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.sync_alt),
                      label: const Text('Convert File'),
                      onPressed: (_convertFile == null || settings == null)
                          ? null
                          : () => widget.controller
                              .convert(_convertFile!, _convertTarget),
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
                          'Converted Files (${widget.controller.convertResults.length})',
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
                            label: const Text('Save'),
                            onPressed: () =>
                                widget.controller.saveConvertedResult(result),
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

  // ── Logs tab ───────────────────────────────────────────────────────────

  Widget _buildLogsTab() {
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
                                'Application Logs (${logs.length})',
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
                          label: const Text('Clear Logs'),
                          onPressed: logs.isEmpty
                              ? null
                              : () {
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
                              'Application Logs (${logs.length})',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear Logs'),
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
                          Text('No logs yet',
                              style: TextStyle(
                                  fontSize: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text('Activity will be logged here',
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
