import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

import '../models/app_settings.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../services/android_saf.dart';
import '../services/computation_service.dart';
import '../services/coordinator_service.dart';
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
import 'player.dart';
import '../widgets/browser_shell.dart';
import '../widgets/onboarding_tooltip_service.dart';
import '../widgets/quick_links_page.dart';
import '../widgets/quick_links_service.dart';


class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static final Uri _buyMeCoffeeUri = Uri.parse('https://buymeacoffee.com/orokaconner');

  ThemeMode _resolveThemeMode(String? mode) {
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
  bool _supportEnabled = false;
  PlayerState? _playerState;
  late final TabController _playlistTabController;
  File? _convertFile;
  String _convertTarget = 'mp4';
  String _androidDownloadUri = '';
  int _selectedPageIndex = 13;

  final GlobalKey<ScaffoldState> _shellScaffoldKey = GlobalKey<ScaffoldState>();
  final List<int> _navHistory = [13];
  int _navHistoryIndex = 0;
  bool _queueOnRight = true;

  /// Progressive onboarding tooltip system.
  final OnboardingTooltipService _onboarding = OnboardingTooltipService();
  String? _dismissedBannerRoute;

  /// Mining services — owned here so they survive tab switches.
  late final ComputationService _computeService;
  late final CoordinatorService _coordinatorService;

  /// System-tray close-to-tray logic (desktop only).
  TrayService? _trayService;

  /// Playlist preview amount: '10', '25', '50', '100', 'all', 'custom'
  String _previewPreset = '25';
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool _isNarrowLayout(BuildContext context) => MediaQuery.of(context).size.width < 600;

  /// Pages that have been visited at least once in the narrow (mobile) layout.
  /// Used by IndexedStack to lazily build pages while keeping them alive.
  final Set<int> _visitedPages = {13};

  // Range selector for adding subset of preview results to queue
  int _addRangeFrom = 1;
  int _addRangeTo = 1;

  @override
  void initState() {
    super.initState();
    _playlistTabController = TabController(length: 2, vsync: this);

    // Progressive onboarding — await then refresh UI with loaded state.
    _onboarding.init().then((_) {
      if (mounted) setState(() {});
    });

    // Mining services — survive tab switches.
    _computeService = ComputationService(maxConcurrent: 2);
    _coordinatorService = CoordinatorService(compute: _computeService);
    _coordinatorService.nativeMiner.loadSavedSettings();

    // Desktop: system-tray & shortcut.
    _initDesktopFeatures();

    // Restore last selected tab if present.
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getInt('last_tab');
      if (saved != null && mounted) {
        setState(() {
          _selectedPageIndex = saved;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playerState ??= context.read<PlayerState>();
  }

  /// True when the app has active downloads or conversions.
  bool get _hasActiveWork {
    return widget.controller.queue.any((q) =>
        q.status == DownloadStatus.downloading ||
        q.status == DownloadStatus.converting ||
        q.status == DownloadStatus.queued);
  }

  Future<void> _initDesktopFeatures() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) return;

    // System tray.
    _trayService = TrayService(
      shouldMinimiseToTray: () =>
          _supportEnabled ||
          _hasActiveWork ||
          (_playerState?.isActuallyPlaying ?? false),
    );
    _trayService!.onTrayShow = () {
      // no-op — window_manager.show() is handled by TrayService itself.
    };
    _trayService!.onTrayQuit = () async {
      // Stop mining before quitting.
      _coordinatorService.dispose();
      try {
        await _trayService?.destroy();
      } catch (_) {}
      exit(0);
    };
    try {
      await _trayService!.init();
    } catch (e) {
      debugPrint('HomeScreen: tray init failed: $e');
    }

    // Desktop shortcut.
    try {
      await ShortcutService.ensureDesktopShortcut();
    } catch (e) {
      debugPrint('HomeScreen: desktop shortcut failed: $e');
    }
  }

  @override
  void dispose() {
    _coordinatorService.dispose();
    _trayService?.destroy();
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
        return SupportScreen(
          key: const ValueKey('support'),
          enabled: _supportEnabled,
          onEnabledChanged: (v) => _setSupportEnabled(v),
          compute: _computeService,
          coordinator: _coordinatorService,
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
        return const playerPlayerPage(key: ValueKey('player-player'));
      case 13:
        return QuickLinksPage(
          key: const ValueKey('quick-links-home'),
          onNavigate: (route) {
            final idx = QuickLinksService.routeToIndex[route];
            if (idx != null) _navigateToPage(idx);
          },
          onSearch: (query) {
            _urlController.text = query;
            _navigateToPage(0);
            _onSearch();
          },
        );
      default:
        return _buildSearchTab(settings);
    }
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION HELPERS
  // ---------------------------------------------------------------------------

  bool get _canGoBack => _navHistoryIndex > 0;
  bool get _canGoForward => _navHistoryIndex < _navHistory.length - 1;

  void _navigateToPage(int index) {
    if (index < 0 || index > 13) return;
    if (index == _selectedPageIndex) return;
    setState(() {
      // Truncate forward history when navigating to a new page.
      if (_navHistoryIndex < _navHistory.length - 1) {
        _navHistory.removeRange(_navHistoryIndex + 1, _navHistory.length);
      }
      _navHistory.add(index);
      _navHistoryIndex = _navHistory.length - 1;
      _selectedPageIndex = index;
      _visitedPages.add(index);
    });
    // Persist last selected tab
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('last_tab', index));
  }

  /// Alias used by tappable top-bar UI items to navigate to a tab index.
  /// (Removed unused alias to satisfy analyzer.)

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _navHistoryIndex--;
      _selectedPageIndex = _navHistory[_navHistoryIndex];
      _visitedPages.add(_selectedPageIndex);
    });
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      _navHistoryIndex++;
      _selectedPageIndex = _navHistory[_navHistoryIndex];
      _visitedPages.add(_selectedPageIndex);
    });
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

        _visitedPages.add(_selectedPageIndex);

        final shell = BrowserShell(
          scaffoldKey: _shellScaffoldKey,
          currentIndex: _selectedPageIndex,
          queueWidget: _buildQueueTab(),
          onNavigate: (route) {
            if (route == 'home') {
              _navigateHome();
              return;
            }
            final idx = QuickLinksService.routeToIndex[route];
            if (idx != null) _navigateToPage(idx);
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

        // Wrap in CallbackShortcuts for desktop media key support
        // Also wrap shell in a PopScope so Android back navigates to home instead of exiting.
        final popWrapped = PopScope(
          canPop: _selectedPageIndex == 13,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _selectedPageIndex != 13) {
              setState(() => _selectedPageIndex = 13);
            }
          },
          child: shell,
        );

        if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
              const SingleActivator(LogicalKeyboardKey.space, control: true): () {
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
    final description =
        route != null ? OnboardingTooltipService.screenDescriptions[route] : null;

    final stack = IndexedStack(
      index: _selectedPageIndex,
      children: List.generate(14, (i) {
        if (!_visitedPages.contains(i)) {
          return const SizedBox.shrink();
        }
        return _buildPageContent(i, settings);
      }),
    );

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
        _downloadDirController.text = _formatAndroidFolderLabel(settings.downloadDir);
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
      _settingsInitialized = true;
    });
  }

  /// Open a web URL in the **in-app browser**.
  void openBrowserWith(String url) {
    _navigateToPage(2); // Switch to the browser tab
    BrowserScreen.navigate(url); // Load URL in the in-app WebView
  }

  String _formatAndroidFolderLabel(String uriString) {
    if (uriString.trim().isEmpty) {
      return 'Not set';
    }
    if (!uriString.startsWith('content://')) {
      return uriString;
    }
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
    if (uri == null || uri.isEmpty) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _androidDownloadUri = uri;
      _downloadDirController.text = _formatAndroidFolderLabel(uri);
    });
    await widget.controller.saveSettings(settings.copyWith(downloadDir: uri));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download folder updated')),
      );
    }
  }

  Future<void> _openAndroidFolder() async {
    if (!_hasAndroidFolder) return;
    final ok = await _androidSaf.openTree(_androidDownloadUri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the selected folder.')),
      );
    }
  }

  Future<void> _clearAndroidFolder(AppSettings settings) async {
    setState(() {
      _androidDownloadUri = '';
      _downloadDirController.text = 'Not set';
    });
    await widget.controller.saveSettings(settings.copyWith(downloadDir: ''));
  }

  // ---------------------------------------------------------------------------
  // SEARCH TAB
  // ---------------------------------------------------------------------------

  Widget _buildSearchTab(AppSettings? settings) {
    final isNarrow = _isNarrowLayout(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          // URL input
          Row(
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
                              setState(() {
                                _urlController.clear();
                              });
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
                  if (clipboardData != null && clipboardData.text != null) {
                    setState(() {
                      _urlController.text = clipboardData.text!;
                    });
                  }
                },
                tooltip: 'Paste from clipboard',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Download Options card
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
                      Text('Download Options', style: Theme.of(context).textTheme.titleMedium),
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
                            DropdownMenuItem(value: 'mp4', child: Text('MP4 (Video)')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _downloadFormat = value;
                            });
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
                            DropdownMenuItem(value: '360p', child: Text('360p')),
                            DropdownMenuItem(value: '480p', child: Text('480p')),
                            DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
                            DropdownMenuItem(value: '1080p', child: Text('1080p (Full HD)')),
                            DropdownMenuItem(value: 'best', child: Text('Best Available')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _videoQuality = value;
                            });
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
                            DropdownMenuItem(value: 128, child: Text('128 kbps')),
                            DropdownMenuItem(value: 192, child: Text('192 kbps')),
                            DropdownMenuItem(value: 256, child: Text('256 kbps')),
                            DropdownMenuItem(value: 320, child: Text('320 kbps')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _audioBitrate = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: _expandPlaylist,
                          onChanged: (value) {
                            setState(() {
                              _expandPlaylist = value ?? false;
                            });
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
                                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                                  DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                                  DropdownMenuItem(value: 'mp4', child: Text('MP4 (Video)')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _downloadFormat = value;
                                  });
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
                                  DropdownMenuItem(value: '360p', child: Text('360p')),
                                  DropdownMenuItem(value: '480p', child: Text('480p')),
                                  DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
                                  DropdownMenuItem(value: '1080p', child: Text('1080p (Full HD)')),
                                  DropdownMenuItem(value: 'best', child: Text('Best Available')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _videoQuality = value;
                                  });
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
                                  DropdownMenuItem(value: 128, child: Text('128 kbps')),
                                  DropdownMenuItem(value: 192, child: Text('192 kbps')),
                                  DropdownMenuItem(value: 256, child: Text('256 kbps')),
                                  DropdownMenuItem(value: 320, child: Text('320 kbps')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _audioBitrate = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: _expandPlaylist,
                          onChanged: (value) {
                            setState(() {
                              _expandPlaylist = value ?? false;
                            });
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

          // Playlist Range card (only visible when expand playlist is checked)
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
                        Text('Playlist Options', style: Theme.of(context).textTheme.titleMedium),
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
                              DropdownMenuItem(value: '10', child: Text('First 10')),
                              DropdownMenuItem(value: '25', child: Text('First 25')),
                              DropdownMenuItem(value: '50', child: Text('First 50')),
                              DropdownMenuItem(value: '100', child: Text('First 100')),
                              DropdownMenuItem(value: 'all', child: Text('All')),
                              DropdownMenuItem(value: 'custom', child: Text('Custom range...')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _previewPreset = value;
                              });
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
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Video numbers are 1-based (e.g. 1 to 25 = first 25 videos)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: context.warning),
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

          // Search / Download buttons
          if (isNarrow)
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text('Search / Preview'),
                    onPressed: settings == null || _urlController.text.trim().isEmpty
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
                    onPressed: settings == null || _urlController.text.trim().isEmpty
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
                    onPressed: settings == null || _urlController.text.trim().isEmpty
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
                    onPressed: settings == null || _urlController.text.trim().isEmpty
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
          if (!widget.controller.previewLoading)
            _buildPreviewList(),
        ],
      ),
    );
  }

  /// Returns true if a download folder is configured (or Android, where the
  /// default fallback works), otherwise shows a snackbar and navigates to Settings.
  bool _ensureDownloadFolder(AppSettings settings) {
    // On Android, downloads always go to a default folder even without user
    // selection, so no redirect is needed.
    if (_isAndroid) return true;
    final dir = settings.downloadDir.trim();
    if (dir.isNotEmpty) return true;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
        content: const Row(
          children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('Please select a download folder in Settings first.')),
          ],
        ),
            backgroundColor: context.warning.withValues(alpha: 0.95),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        action: SnackBarAction(
          label: 'Go to Settings',
              textColor: Colors.white,
          onPressed: () => _navigateToPage(7),
        ),
      ),
    );
    // Navigate to settings
    _navigateToPage(7);
    return false;
  }

  /// Queue a URL for download and start downloading.
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
          break;
        case '25':
          limit = 25;
          break;
        case '50':
          limit = 50;
          break;
        case '100':
          limit = 100;
          break;
        case 'all':
          limit = 999999;
          break;
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
          break;
      }
    }

    widget.controller.preview(
      _urlController.text.trim(),
      _expandPlaylist,
      startIndex: startIndex,
      limit: limit,
    );
  }

  // ---------------------------------------------------------------------------
  // PREVIEW LIST
  // ---------------------------------------------------------------------------

  Widget _buildPreviewList() {
    final isNarrow = _isNarrowLayout(context);
    final items = widget.controller.previewItems;
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'No preview results yet.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter a YouTube URL above and click Search',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Ensure range sliders stay in bounds.  Mutate eagerly so that
    // the dropdown widgets below use valid values on *this* frame.
    _addRangeFrom = _addRangeFrom.clamp(1, items.length);
    _addRangeTo = _addRangeTo.clamp(_addRangeFrom, items.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        if (isNarrow)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.video_library, color: Theme.of(context).primaryColor),
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
                        widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added ${items.length} items to queue')),
                      );
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download All'),
                    onPressed: () {
                      final s = widget.controller.settings;
                      if (s != null && !_ensureDownloadFolder(s)) return;
                      for (final item in items) {
                        widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
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
                  Icon(Icons.video_library, color: Theme.of(context).primaryColor),
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
                        widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Added ${items.length} items to queue')),
                      );
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
                        widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                      }
                      widget.controller.downloadAll();
                    },
                  ),
                ],
              ),
            ],
          ),

        // Range selector for adding a subset to queue
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
                          dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          items: List.generate(items.length, (i) {
                            return DropdownMenuItem(value: i + 1, child: Text('${i + 1}'));
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
                          dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          items: List.generate(
                            items.length - _addRangeFrom + 1,
                            (i) {
                              final v = _addRangeFrom + i;
                              return DropdownMenuItem(value: v, child: Text('$v'));
                            },
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _addRangeTo = v;
                            });
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: Text('Add ${_addRangeTo - _addRangeFrom + 1}'),
                        onPressed: () {
                          final subset = items.sublist(_addRangeFrom - 1, _addRangeTo);
                          for (final item in subset) {
                            widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added ${subset.length} items to queue')),
                          );
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download, size: 18),
                        label: Text('Download ${_addRangeTo - _addRangeFrom + 1}'),
                        onPressed: () {
                          final s = widget.controller.settings;
                          if (s != null && !_ensureDownloadFolder(s)) return;
                          final subset = items.sublist(_addRangeFrom - 1, _addRangeTo);
                          for (final item in subset) {
                            widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
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
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.thumbnailUrl!,
                                  width: 80,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _thumbnailPlaceholder();
                                  },
                                ),
                              )
                            : _thumbnailPlaceholder(),
                      ],
                    ),
                    title: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.uploader, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (item.duration != null)
                          Text(
                            _formatDuration(item.duration!),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
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
                                  widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Added to queue')),
                                  );
                                },
                                tooltip: 'Add to queue',
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('Download'),
                                onPressed: () {
                                  final s = widget.controller.settings;
                                  if (s != null && !_ensureDownloadFolder(s)) return;
                                  widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                                  widget.controller.downloadAll();
                                },
                              ),
                            ],
                          ),
                  ),
                  if (isNarrow)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.playlist_add, size: 18),
                            label: const Text('Add to queue'),
                            onPressed: () {
                              widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Added to queue')),
                              );
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Download'),
                            onPressed: () {
                              final s = widget.controller.settings;
                              if (s != null && !_ensureDownloadFolder(s)) return;
                              widget.controller.addToQueue(item, _downloadFormat.toLowerCase());
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

  // ---------------------------------------------------------------------------
  // QUEUE TAB
  // ---------------------------------------------------------------------------

  Widget _buildQueueTab() {
    final items = widget.controller.queue;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No items in queue',
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Add items from the Search tab',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final completedCount = items.where((i) => i.status == DownloadStatus.completed).length;
    final inProgressCount = items.where((i) => i.status == DownloadStatus.downloading).length;

    // Use LayoutBuilder so the queue adapts to its actual available width
    // (e.g. 300px sidebar) instead of the full screen width.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 400;
        return Column(
          children: [
            _buildQueueHeader(items, inProgressCount, completedCount, isCompact),
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

  Widget _buildQueueHeader(List<QueueItem> items, int inProgressCount, int completedCount, bool isCompact) {
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
                  if (value == null) return;
                  setState(() => _downloadFormat = value);
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
                    onPressed: items.isEmpty ? null : () {
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
                                content: const Text('Remove all items from the queue?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      final snapshot = List<QueueItem>.from(items);
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
            // Title row with status icon
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
            // Status + progress row — use Wrap to avoid overflow in narrow panels
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                // Format dropdown
                SizedBox(
                  height: 24,
                  child: DropdownButton<String>(
                    value: item.format,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: 11, color: cs.onSurface),
                    items: const [
                      DropdownMenuItem(value: 'mp3', child: Text('MP3', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: 'm4a', child: Text('M4A', style: TextStyle(fontSize: 11))),
                      DropdownMenuItem(value: 'mp4', child: Text('MP4', style: TextStyle(fontSize: 11))),
                    ],
                    onChanged: item.status == DownloadStatus.downloading ||
                                item.status == DownloadStatus.converting ||
                                item.status == DownloadStatus.completed
                        ? null
                        : (value) {
                            if (value == null) return;
                            widget.controller.changeQueueItemFormat(item, value);
                          },
                  ),
                ),
              ],
            ),
            // Progress bar
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
            ],
            // Action buttons row — use Wrap so icons flow instead of overflowing
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 0,
              runSpacing: 0,
              children: [
                if (item.status == DownloadStatus.queued ||
                    item.status == DownloadStatus.failed ||
                    item.status == DownloadStatus.cancelled)
                  _queueAction(Icons.download_rounded, 'Download', Colors.blue, () {
                    final s = widget.controller.settings;
                    if (s != null && !_ensureDownloadFolder(s)) return;
                    widget.controller.downloadSingle(item);
                  }),
                if (item.status == DownloadStatus.downloading ||
                    item.status == DownloadStatus.converting)
                  _queueAction(Icons.stop_rounded, 'Cancel', Colors.orange,
                      () => widget.controller.cancelDownload(item)),
                if (item.status == DownloadStatus.cancelled ||
                    item.status == DownloadStatus.failed)
                  _queueAction(Icons.play_arrow_rounded, 'Resume', Colors.green, () {
                    final s = widget.controller.settings;
                    if (s != null && !_ensureDownloadFolder(s)) return;
                    widget.controller.resumeDownload(item);
                  }),
                if (item.status == DownloadStatus.completed &&
                    item.outputPath != null &&
                    !kIsWeb && !Platform.isAndroid)
                  _queueAction(Icons.folder_open_rounded, 'Folder', Colors.blue,
                      () => _showInFolder(item.outputPath!)),
                if (item.status == DownloadStatus.completed &&
                    item.outputPath != null &&
                    !kIsWeb && Platform.isAndroid)
                  _queueAction(Icons.share_rounded, 'Share', Colors.blue,
                      () => _shareFile(item.outputPath!, item.title)),
                if (item.status != DownloadStatus.downloading &&
                    item.status != DownloadStatus.converting)
                  _queueAction(Icons.delete_outline_rounded, 'Remove', Colors.red,
                      () => widget.controller.removeFromQueue(item)),
              ],
            ),
            // Error message
            if (item.error != null && item.status == DownloadStatus.failed) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 11),
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

  Widget _queueAction(IconData icon, String tooltip, Color color, VoidCallback onPressed) {
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
    switch (status) {
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.converting:
        return Colors.indigo;
      case DownloadStatus.cancelled:
        return Colors.orange;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.queued:
        return Colors.grey;
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

  // ---------------------------------------------------------------------------
  // PLAYLISTS TAB (combines playlist manager + watched playlists)
  // ---------------------------------------------------------------------------

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

  Widget _buildSettingsTab(AppSettings? settings) {
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isNarrow = _isNarrowLayout(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          // â”€â”€ Save Settings (top) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

          // â”€â”€ Support the Project â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          // Mining support – hidden entirely on Android.
          if (!_isAndroid) ...[
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
            ),
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
                        child: Icon(Icons.toll_rounded,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Support the Project',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    )),
                            const SizedBox(height: 4),
                            Text(
                              'Mine QUBIC tokens with idle CPU cycles â€” '
                              'supports the developer, runs in sandboxed isolates.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Mining toggle – never shown on Android
                  SwitchListTile(
                      value: _supportEnabled,
                      onChanged: (value) {
                        _setSupportEnabled(value);
                      },
                      title: const Text('Enable Support'),
                      subtitle: Text(
                        _supportEnabled
                            ? 'Mining QUBIC tokens'
                            : 'Tap to start mining',
                      ),
                      secondary: Icon(
                        _supportEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: _supportEnabled ? Colors.green : null,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Learn more'),
                      onPressed: () => _navigateToPage(8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ], // end if (!_isAndroid) mining card

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
                      Text('Download Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (_isAndroid) ...[
                    // Android: SAF folder picker
                    TextField(
                      controller: _downloadDirController,
                      decoration: InputDecoration(
                        labelText: 'Download folder',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.folder),
                        helperText: 'Pick a folder using the system file picker. If not set, files go to Downloads/ConvertTheSpireReborn.',
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
                          label: Text(_hasAndroidFolder ? 'Change folder' : 'Choose folder'),
                          onPressed: () => _pickAndroidFolder(settings),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.folder),
                          label: const Text('Open folder'),
                          onPressed: _hasAndroidFolder ? _openAndroidFolder : null,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.clear),
                          label: const Text('Clear'),
                          onPressed: _hasAndroidFolder ? () => _clearAndroidFolder(settings) : null,
                        ),
                      ],
                    ),
                    if (!_hasAndroidFolder)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'No folder selected. Downloads will be saved to Downloads/ConvertTheSpireReborn.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                      ),
                  ] else ...[
                    // Desktop: Browse button with FilePicker
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
                                final result = await FilePicker.platform.getDirectoryPath();
                                if (result != null && mounted) {
                                  setState(() {
                                    _downloadDirController.text = result;
                                  });
                                  await widget.controller.saveSettings(settings.copyWith(downloadDir: result));
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
                              final result = await FilePicker.platform.getDirectoryPath();
                              if (result != null && mounted) {
                                setState(() {
                                  _downloadDirController.text = result;
                                });
                                await widget.controller.saveSettings(settings.copyWith(downloadDir: result));
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
                      widget.controller.saveSettings(settings.copyWith(showNotifications: value));
                    },
                    title: const Text('Show notifications'),
                    subtitle: const Text('Display notifications when downloads complete'),
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
                      Text('Quality Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (isNarrow) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey('settings-vq-$_videoQuality'),
                      value: _videoQuality,
                      decoration: const InputDecoration(
                        labelText: 'Video Quality',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.videocam),
                        helperText: '1080p+ downloads separate video & audio and merges them (requires FFmpeg)',
                        helperMaxLines: 2,
                      ),
                      items: const [
                        DropdownMenuItem(value: '360p', child: Text('360p')),
                        DropdownMenuItem(value: '480p', child: Text('480p')),
                        DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
                        DropdownMenuItem(value: '1080p', child: Text('1080p (Full HD)')),
                        DropdownMenuItem(value: 'best', child: Text('Best Available')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() { _videoQuality = value; });
                        widget.controller.saveSettings(settings.copyWith(preferredVideoQuality: value));
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('settings-abr-$_audioBitrate'),
                      value: _audioBitrate,
                      decoration: const InputDecoration(
                        labelText: 'Audio Bitrate',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.equalizer),
                        helperText: 'Higher bitrate = better quality, larger file size',
                        helperMaxLines: 2,
                      ),
                      items: const [
                        DropdownMenuItem(value: 128, child: Text('128 kbps (Compact)')),
                        DropdownMenuItem(value: 192, child: Text('192 kbps (Standard)')),
                        DropdownMenuItem(value: 256, child: Text('256 kbps (High)')),
                        DropdownMenuItem(value: 320, child: Text('320 kbps (Maximum)')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() { _audioBitrate = value; });
                        widget.controller.saveSettings(settings.copyWith(preferredAudioBitrate: value));
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
                              helperText: '1080p+ merges separate streams',
                              helperMaxLines: 2,
                            ),
                            items: const [
                              DropdownMenuItem(value: '360p', child: Text('360p')),
                              DropdownMenuItem(value: '480p', child: Text('480p')),
                              DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
                              DropdownMenuItem(value: '1080p', child: Text('1080p (Full HD)')),
                              DropdownMenuItem(value: 'best', child: Text('Best Available')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() { _videoQuality = value; });
                              widget.controller.saveSettings(settings.copyWith(preferredVideoQuality: value));
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
                              DropdownMenuItem(value: 128, child: Text('128 kbps (Compact)')),
                              DropdownMenuItem(value: 192, child: Text('192 kbps (Standard)')),
                              DropdownMenuItem(value: 256, child: Text('256 kbps (High)')),
                              DropdownMenuItem(value: 320, child: Text('320 kbps (Maximum)')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() { _audioBitrate = value; });
                              widget.controller.saveSettings(settings.copyWith(preferredAudioBitrate: value));
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
          
          // FFmpeg Settings
          if (!_isAndroid) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.code,
                          color: _ffmpegPathController.text.isNotEmpty
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text('FFmpeg', style: Theme.of(context).textTheme.titleLarge),
                        if (_ffmpegPathController.text.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
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
                                  ? 'Auto-installed on first use, or browse to set manually'
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
                            if (result != null && result.files.single.path != null && mounted) {
                              setState(() {
                                _ffmpegPathController.text = result.files.single.path!;
                              });
                              final s = widget.controller.settings;
                              if (s != null) {
                                widget.controller.saveSettings(s.copyWith(ffmpegPath: result.files.single.path!));
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
                          'Will be installed automatically when needed. Use Browse to set a custom path.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // yt-dlp Settings
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.download_for_offline,
                          color: _ytDlpPathController.text.isNotEmpty
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text('yt-dlp', style: Theme.of(context).textTheme.titleLarge),
                        if (_ytDlpPathController.text.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
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
                                  ? 'Auto-downloaded on first use, or browse to set manually'
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
                            if (result != null && result.files.single.path != null && mounted) {
                              setState(() {
                                _ytDlpPathController.text = result.files.single.path!;
                              });
                              final s = widget.controller.settings;
                              if (s != null) {
                                widget.controller.saveSettings(s.copyWith(ytDlpPath: result.files.single.path!));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    if (_ytDlpPathController.text.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Will be downloaded automatically on first launch. Required for HD video downloads.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
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
                      Text('Retry Settings', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: settings.autoRetryInstall,
                    onChanged: (value) {
                      widget.controller.saveSettings(settings.copyWith(autoRetryInstall: value));
                    },
                    title: const Text('Auto-retry installs'),
                    subtitle: const Text('Automatically retry failed downloads'),
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
                      Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'system', label: Text('System'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (value) {
                      widget.controller.saveSettings(settings.copyWith(themeMode: value.first));
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
                      Text('About', style: Theme.of(context).textTheme.titleLarge),
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
                    'format conversion, DLNA casting, and QUBIC mining '
                    'support â€” built with Flutter.',
                  ),
                  const SizedBox(height: 8),
                  const Text('Copyright (c) 2026 Oroka Conner. Licensed under GPLv3.'),
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
                            Uri.parse('https://github.com/Lukas-Bohez/ConvertTheSpireFlutter'),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!launched && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not open the GitHub link.')),
                            );
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
                      Text('Browser Shell', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _queueOnRight,
                    onChanged: (value) {
                      setState(() => _queueOnRight = value);
                    },
                    title: const Text('Queue sidebar on right'),
                    subtitle: Text(_queueOnRight ? 'Queue panel on the right side' : 'Queue panel on the left side'),
                    secondary: Icon(_queueOnRight ? Icons.border_right : Icons.border_left),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Quick links reset to defaults')),
                        );
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tutorial tips will show again on each screen')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Save Button (bottom)
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
    final launched = await launchUrl(_buyMeCoffeeUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Buy Me a Coffee link.')),
      );
    }
  }

  /// Toggle support mining on/off and update the coordinator services.
  void _setSupportEnabled(bool value) {
    setState(() => _supportEnabled = value);
    // Ensure SupportScreen is built in the IndexedStack so its UI callbacks
    // (onStateChanged) are connected to the services — prevents errors if the
    // user never manually navigated to the Support page.
    if (value) _visitedPages.add(8);
    final isAndroid = !kIsWeb && Platform.isAndroid;
    if (isAndroid) return;
    _coordinatorService.setEnabled(value);
    _computeService.setEnabled(value);
  }

  Future<void> _saveAllSettings(AppSettings settings) async {
    final ffmpegText = _ffmpegPathController.text.trim();
    final ytDlpText = _ytDlpPathController.text.trim();
    final next = settings.copyWith(
      downloadDir: _isAndroid ? _androidDownloadUri : _downloadDirController.text.trim(),
      maxWorkers: (int.tryParse(_workersController.text.trim()) ?? settings.maxWorkers).clamp(1, 10),
      retryCount: (int.tryParse(_retryCountController.text.trim()) ?? settings.retryCount).clamp(0, 10),
      retryBackoffSeconds: (int.tryParse(_retryBackoffController.text.trim()) ?? settings.retryBackoffSeconds).clamp(0, 60),
      preferredVideoQuality: _videoQuality,
      preferredAudioBitrate: _audioBitrate,
      defaultAudioFormat: _downloadFormat,
      previewExpandPlaylist: _expandPlaylist,
      ffmpegPath: ffmpegText.isEmpty ? null : ffmpegText,
      ytDlpPath: ytDlpText.isEmpty ? null : ytDlpText,
    );
    await widget.controller.saveSettings(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Settings saved'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _openWebsite() async {
    final launched = await launchUrl(_websiteUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the website.')),
      );
    }
  }

  Future<void> _showInFolder(String filePath) async {
    if (kIsWeb) return;
    try {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open folder: $e')),
        );
      }
    }
  }

  Future<void> _shareFile(String filePath, String title) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(filePath)], title: title),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share file: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // CONVERT TAB
  // ---------------------------------------------------------------------------

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
                      Text('File Converter', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('Select file to convert'),
                    onPressed: kIsWeb ? null : () async {
                      final result = await FilePicker.platform.pickFiles();
                      if (result == null || result.files.isEmpty) {
                        return;
                      }
                      final path = result.files.single.path;
                      if (path == null) return;
                      if (!mounted) return;
                      setState(() {
                        _convertFile = File(path);
                      });
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
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Selected file:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _convertFile!.path.split(Platform.pathSeparator).last,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _convertFile!.path,
                                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _convertFile = null;
                              });
                            },
                            tooltip: 'Clear selection',
                          ),
                        ],
                      ),
                    ),
                  if (_convertFile == null)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.file_present, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              'No file selected',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      // â”€â”€ Audio â”€â”€
                      DropdownMenuItem(value: 'mp3', child: Text('MP3 (Audio)')),
                      DropdownMenuItem(value: 'm4a', child: Text('M4A (Audio)')),
                      DropdownMenuItem(value: 'wav', child: Text('WAV (Audio)')),
                      DropdownMenuItem(value: 'flac', child: Text('FLAC (Audio)')),
                      DropdownMenuItem(value: 'ogg', child: Text('OGG (Audio)')),
                      DropdownMenuItem(value: 'aac', child: Text('AAC (Audio)')),
                      DropdownMenuItem(value: 'wma', child: Text('WMA (Audio)')),
                      // â”€â”€ Video â”€â”€
                      DropdownMenuItem(value: 'mp4', child: Text('MP4 (Video)')),
                      DropdownMenuItem(value: 'webm', child: Text('WebM (Video)')),
                      DropdownMenuItem(value: 'mkv', child: Text('MKV (Video)')),
                      DropdownMenuItem(value: 'avi', child: Text('AVI (Video)')),
                      DropdownMenuItem(value: 'mov', child: Text('MOV (Video)')),
                      DropdownMenuItem(value: 'wmv', child: Text('WMV (Video)')),
                      // â”€â”€ Image â”€â”€
                      DropdownMenuItem(value: 'png', child: Text('PNG (Image)')),
                      DropdownMenuItem(value: 'jpg', child: Text('JPG (Image)')),
                      DropdownMenuItem(value: 'bmp', child: Text('BMP (Image)')),
                      DropdownMenuItem(value: 'gif', child: Text('GIF (Image)')),
                      DropdownMenuItem(value: 'tiff', child: Text('TIFF (Image)')),
                      DropdownMenuItem(value: 'webp', child: Text('WebP (Image)')),
                      // â”€â”€ Document â”€â”€
                      DropdownMenuItem(value: 'pdf', child: Text('PDF (Document)')),
                      DropdownMenuItem(value: 'txt', child: Text('TXT (Text)')),
                      DropdownMenuItem(value: 'epub', child: Text('EPUB (E-book)')),
                      // â”€â”€ Archive â”€â”€
                      DropdownMenuItem(value: 'zip', child: Text('ZIP (Archive)')),
                      DropdownMenuItem(value: 'cbz', child: Text('CBZ (Comic Archive)')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _convertTarget = value;
                      });
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
                          : () => widget.controller.convert(_convertFile!, _convertTarget),
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
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Converted Files (${widget.controller.convertResults.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                            child: Icon(Icons.file_present),
                          ),
                          title: Text(result.name),
                          subtitle: Text(result.message),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: const Text('Save'),
                            onPressed: () => widget.controller.saveConvertedResult(result),
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

  // ---------------------------------------------------------------------------
  // LOGS TAB
  // ---------------------------------------------------------------------------

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
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
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
                          Icon(Icons.info_outline, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'No logs yet',
                            style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Activity will be logged here',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
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
                        final isSuccess = log.toLowerCase().contains('success') || 
                                         log.toLowerCase().contains('completed');
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          color: isError
                              ? Colors.red.withValues(alpha: 0.1)
                              : isWarning
                                  ? Colors.orange.withValues(alpha: 0.1)
                                  : isSuccess
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                      ? Colors.red
                                      : isWarning
                                          ? Colors.orange
                                          : isSuccess
                                              ? Colors.green
                                              : Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: isError ? Colors.red[700] : null,
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
