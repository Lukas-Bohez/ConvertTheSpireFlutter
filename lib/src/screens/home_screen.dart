import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/preview_item.dart';
import '../models/queue_item.dart';
import '../services/android_saf.dart';
import '../state/app_controller.dart';
import 'bulk_import_screen.dart';
import 'playlist_screen.dart';
import 'search_screen.dart';
import 'guide_screen.dart';
import 'statistics_screen.dart';
import 'watched_playlists_screen.dart';
import 'browser_screen.dart';
import 'player.dart';  // player player screen


class HomeScreen extends StatefulWidget {
  final AppController controller;

  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static final Uri _buyMeCoffeeUri = Uri.parse('https://buymeacoffee.com/orokaconner');
  static final Uri _websiteUri = Uri.parse('https://quizthespire.com/');
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _downloadDirController = TextEditingController();
  final TextEditingController _workersController = TextEditingController();
  final TextEditingController _retryCountController = TextEditingController();
  final TextEditingController _retryBackoffController = TextEditingController();
  final TextEditingController _rangeFromController = TextEditingController();
  final TextEditingController _rangeToController = TextEditingController();
  final AndroidSaf _androidSaf = AndroidSaf();

  bool _expandPlaylist = false;
  String _downloadFormat = 'mp3';
  bool _settingsInitialized = false;
  late final TabController _mainTabController;
  late final TabController _playlistTabController;
  File? _convertFile;
  String _convertTarget = 'mp4';
  String _androidDownloadUri = '';
  int _selectedPageIndex = 0;

  /// Playlist preview amount: '10', '25', '50', '100', 'all', 'custom'
  String _previewPreset = '25';
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool _isNarrowLayout(BuildContext context) => MediaQuery.of(context).size.width < 600;

  // Range selector for adding subset of preview results to queue
  int _addRangeFrom = 1;
  int _addRangeTo = 1;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 12, vsync: this);
    _mainTabController.addListener(() {
      if (!_mainTabController.indexIsChanging) {
        setState(() => _selectedPageIndex = _mainTabController.index);
      }
    });
    _playlistTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _playlistTabController.dispose();
    _urlController.dispose();
    _downloadDirController.dispose();
    _workersController.dispose();
    _retryCountController.dispose();
    _retryBackoffController.dispose();
    _rangeFromController.dispose();
    _rangeToController.dispose();
    super.dispose();
  }

  static const _navItems = <_NavItem>[
    _NavItem(0, Icons.search, 'Search', 'Search & Discovery'),
    _NavItem(1, Icons.travel_explore, 'Multi-Search', 'Search & Discovery'),
    _NavItem(2, Icons.open_in_browser, 'Browser', 'Tools'),
    _NavItem(3, Icons.queue_music, 'Queue', 'Downloads'),
    _NavItem(4, Icons.playlist_play, 'Playlists', 'Downloads'),
    _NavItem(5, Icons.upload_file, 'Bulk Import', 'Downloads'),
    _NavItem(6, Icons.bar_chart, 'Stats', 'Tools'),
    _NavItem(7, Icons.settings, 'Settings', null),
    _NavItem(8, Icons.transform, 'Convert', 'Tools'),
    _NavItem(9, Icons.list_alt, 'Logs', 'Tools'),
    _NavItem(10, Icons.menu_book, 'Guide', null),
    _NavItem(11, Icons.music_note, 'Player', 'Tools'),
  ];

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
        return _buildConvertTab(settings);
      case 9:
        return _buildLogsTab();
      case 10:
        return const GuideScreen(key: ValueKey('guide'));
      case 11:
        return const playerPlayerPage(key: ValueKey('player-player'));
      default:
        return _buildSearchTab(settings);
    }
  }

  Widget _buildNavigationDrawer() {
    final cs = Theme.of(context).colorScheme;
    String? lastGroup;
    final children = <Widget>[
      DrawerHeader(
        decoration: BoxDecoration(color: cs.primaryContainer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.music_note, size: 48, color: cs.onPrimaryContainer),
            const SizedBox(height: 8),
            Text('Convert the Spire',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer)),
          ],
        ),
      ),
    ];

    for (final item in _navItems) {
      if (item.group != lastGroup) {
        if (lastGroup != null) children.add(const Divider());
        if (item.group != null) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(item.group!,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                    letterSpacing: 0.5)),
          ));
        }
        lastGroup = item.group;
      }
      final selected = _selectedPageIndex == item.index;
      children.add(ListTile(
        leading: Icon(item.icon, color: selected ? cs.primary : null),
        title: Text(item.label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? cs.primary : null)),
        selected: selected,
        selectedTileColor: cs.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          setState(() {
            _selectedPageIndex = item.index;
            _mainTabController.index = item.index;
          });
          Navigator.pop(context);
        },
      ));
    }

    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.only(bottom: bottomPad + 16),
        children: children,
      ),
    );
  }

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

        if (_isNarrowLayout(context)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Convert the Spire')),
            drawer: _buildNavigationDrawer(),
            body: SafeArea(
              top: false,
              child: _buildPageContent(_selectedPageIndex, settings),
            ),
          );
        }

        return Scaffold(
            appBar: AppBar(
              title: const Text('Convert the Spire'),
              bottom: TabBar(
                controller: _mainTabController,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.search), text: 'Search'),
                  Tab(icon: Icon(Icons.travel_explore), text: 'Multi-Search'),
                  Tab(icon: Icon(Icons.open_in_browser), text: 'Browser'),
                  Tab(icon: Icon(Icons.queue_music), text: 'Queue'),
                  Tab(icon: Icon(Icons.playlist_play), text: 'Playlists'),
                  Tab(icon: Icon(Icons.upload_file), text: 'Bulk Import'),
                  Tab(icon: Icon(Icons.bar_chart), text: 'Stats'),
                  Tab(icon: Icon(Icons.settings), text: 'Settings'),
                  Tab(icon: Icon(Icons.transform), text: 'Convert'),
                  Tab(icon: Icon(Icons.list_alt), text: 'Logs'),
                  Tab(icon: Icon(Icons.menu_book), text: 'Guide'),
                  Tab(icon: Icon(Icons.music_note), text: 'player'),
                ],
              ),
            ),
            body: TabBarView(
              controller: _mainTabController,
              children: [
                _buildSearchTab(settings),
                SearchScreen(
                  key: const ValueKey('multi-search'),
                  searchService: widget.controller.searchService,
                  previewPlayer: widget.controller.previewPlayer,
                  onDownload: (result, format) => widget.controller.addSearchResultToQueue(result, format: format),
                ),
                BrowserScreen(
                  key: BrowserScreen.browserKey,
                  onAddToQueue: widget.controller.addSearchResultToQueue,
                ),
                _buildQueueTab(),
                _buildPlaylistsTab(),
                BulkImportScreen(
                  key: const ValueKey('bulk-import'),
                  importService: widget.controller.bulkImportService,
                  onProcess: (queries, format) => widget.controller.processBulkImport(queries, format: format),
                ),
                StatisticsScreen(
                  key: const ValueKey('statistics'),
                  statisticsService: widget.controller.statisticsService,
                ),
                _buildSettingsTab(settings),
                _buildConvertTab(settings),
                _buildLogsTab(),
                const GuideScreen(key: ValueKey('guide')),
                const playerPlayerPage(key: ValueKey('player-player')),
              ],
            ),
        );
      },
    );
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
      _expandPlaylist = settings.previewExpandPlaylist;
      _downloadFormat = settings.defaultAudioFormat;
      _settingsInitialized = true;
    });
  }

  /// Programmatically switch to the browser tab and navigate it.
  void openBrowserWith(String url) {
    setState(() {
      _selectedPageIndex = 2;
      _mainTabController.index = 2;
    });
    // schedule navigation after the tab switch has taken effect so that the
    // BrowserScreen widget tree is mounted and its controller may be created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BrowserScreen.navigate(url);
    });
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
                        const SizedBox(width: 16),
                        Expanded(
                          child: CheckboxListTile(
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
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'YouTube Mix playlists (IDs starting with RD) cannot be expanded.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.orange),
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
                        : () {
                            final url = _urlController.text.trim();
                            if (url.isEmpty) return;
                            final item = widget.controller.previewItems.isNotEmpty
                                ? widget.controller.previewItems.firstWhere(
                                    (p) => p.url == url,
                                    orElse: () => widget.controller.previewItems.first,
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
                          },
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
                        : () {
                            final url = _urlController.text.trim();
                            if (url.isEmpty) return;
                            final item = widget.controller.previewItems.isNotEmpty
                                ? widget.controller.previewItems.firstWhere(
                                    (p) => p.url == url,
                                    orElse: () => widget.controller.previewItems.first,
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
                          },
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
          final from = int.tryParse(_rangeFromController.text.trim()) ?? 1;
          final to = int.tryParse(_rangeToController.text.trim()) ?? 50;
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

    // Ensure range sliders stay in bounds (computed locally, not mutating state)
    final clampedFrom = _addRangeFrom.clamp(1, items.length);
    final clampedTo = _addRangeTo.clamp(clampedFrom, items.length);
    if (clampedFrom != _addRangeFrom || clampedTo != _addRangeTo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _addRangeFrom = clampedFrom;
            _addRangeTo = clampedTo;
          });
        }
      });
    }

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
            color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
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
                        Text(item.uploader),
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
    final isNarrow = _isNarrowLayout(context);
    final items = widget.controller.queue;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.queue_music, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No items in queue',
              style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Add items from the Search tab',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final completedCount = items.where((i) => i.status == DownloadStatus.completed).length;
    final inProgressCount = items.where((i) => i.status == DownloadStatus.downloading).length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Queue Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${items.length} total \u2022 $inProgressCount downloading \u2022 $completedCount completed',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DropdownButton<String>(
                          value: _downloadFormat,
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
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_for_offline),
                          label: const Text('Download All'),
                          onPressed: items.isEmpty ? null : () => widget.controller.downloadAll(),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear Queue'),
                          onPressed: items.isEmpty
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Clear Queue'),
                                      content: const Text('Are you sure you want to clear all items from the queue?'),
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
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Queue Status',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${items.length} total \u2022 $inProgressCount downloading \u2022 $completedCount completed',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        DropdownButton<String>(
                          value: _downloadFormat,
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
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_for_offline),
                          label: const Text('Download All'),
                          onPressed: items.isEmpty ? null : () => widget.controller.downloadAll(),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear Queue'),
                          onPressed: items.isEmpty
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Clear Queue'),
                                      content: const Text('Are you sure you want to clear all items from the queue?'),
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
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final statusColor = _getStatusColor(item.status);
              final statusIcon = _getStatusIcon(item.status);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.2),
                        child: Icon(statusIcon, color: statusColor),
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  item.status.name.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text('${item.progress}%'),
                              DropdownButton<String>(
                                value: item.format,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(value: 'mp3', child: Text('MP3')),
                                  DropdownMenuItem(value: 'm4a', child: Text('M4A')),
                                  DropdownMenuItem(value: 'mp4', child: Text('MP4')),
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
                            ],
                          ),
                        ],
                      ),
                      trailing: isNarrow
                          ? null
                          : Wrap(
                              spacing: 4,
                              children: [
                                if (item.status == DownloadStatus.queued ||
                                    item.status == DownloadStatus.failed ||
                                    item.status == DownloadStatus.cancelled)
                                  IconButton(
                                    icon: const Icon(Icons.download),
                                    onPressed: () => widget.controller.downloadSingle(item),
                                    tooltip: 'Download',
                                    color: Colors.blue,
                                  ),
                                if (item.status == DownloadStatus.downloading ||
                                    item.status == DownloadStatus.converting)
                                  IconButton(
                                    icon: const Icon(Icons.pause_circle),
                                    onPressed: () => widget.controller.cancelDownload(item),
                                    tooltip: 'Cancel',
                                    color: Colors.orange,
                                  ),
                                if (item.status == DownloadStatus.cancelled ||
                                    item.status == DownloadStatus.failed)
                                  IconButton(
                                    icon: const Icon(Icons.play_circle),
                                    onPressed: () => widget.controller.resumeDownload(item),
                                    tooltip: 'Resume',
                                    color: Colors.green,
                                  ),
                                if (item.status != DownloadStatus.downloading &&
                                    item.status != DownloadStatus.converting)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => widget.controller.removeFromQueue(item),
                                    tooltip: 'Remove',
                                    color: Colors.red,
                                  ),
                              ],
                            ),
                    ),
                    if (isNarrow)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (item.status == DownloadStatus.queued ||
                                item.status == DownloadStatus.failed ||
                                item.status == DownloadStatus.cancelled)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('Download'),
                                onPressed: () => widget.controller.downloadSingle(item),
                              ),
                            if (item.status == DownloadStatus.downloading ||
                                item.status == DownloadStatus.converting)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.pause_circle, size: 18),
                                label: const Text('Cancel'),
                                onPressed: () => widget.controller.cancelDownload(item),
                              ),
                            if (item.status == DownloadStatus.cancelled ||
                                item.status == DownloadStatus.failed)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.play_circle, size: 18),
                                label: const Text('Resume'),
                                onPressed: () => widget.controller.resumeDownload(item),
                              ),
                            if (item.status != DownloadStatus.downloading &&
                                item.status != DownloadStatus.converting)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: const Text('Remove'),
                                onPressed: () => widget.controller.removeFromQueue(item),
                              ),
                          ],
                        ),
                      ),
                    if (item.progress > 0 && item.progress < 100)
                      LinearProgressIndicator(
                        value: item.progress / 100,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      ),
                    if (item.error != null && item.status == DownloadStatus.failed)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: Colors.red.withValues(alpha: 0.1),
                        child: Text(
                          item.error!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
          
          // FFmpeg Settings
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.code),
                      const SizedBox(width: 8),
                      Text('FFmpeg', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: Icon(
                      settings.ffmpegPath != null && settings.ffmpegPath!.isNotEmpty
                          ? Icons.check_circle
                          : Icons.info_outline,
                      color: settings.ffmpegPath != null && settings.ffmpegPath!.isNotEmpty
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text(
                      settings.ffmpegPath != null && settings.ffmpegPath!.isNotEmpty
                          ? 'FFmpeg installed'
                          : 'FFmpeg not configured',
                    ),
                    subtitle: Text(
                      settings.ffmpegPath != null && settings.ffmpegPath!.isNotEmpty
                          ? settings.ffmpegPath!
                          : 'Will be installed automatically on Windows when needed',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
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
                      labelText: 'Retry count',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.repeat),
                      hintText: 'Number of retry attempts',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _retryBackoffController,
                    decoration: const InputDecoration(
                      labelText: 'Retry backoff (seconds)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timelapse),
                      hintText: 'Wait time between retries',
                    ),
                    keyboardType: TextInputType.number,
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
                  const SizedBox(height: 6),
                  const Text('Copyright (c) 2026 Oroka Conner. Licensed under GPLv3.'),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 4),
                  SelectableText(
                    _buyMeCoffeeUri.toString(),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                  SelectableText(
                    _websiteUri.toString(),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Save Button
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Settings'),
              onPressed: () {
                final next = settings.copyWith(
                  downloadDir: _isAndroid ? _androidDownloadUri : _downloadDirController.text.trim(),
                  maxWorkers: int.tryParse(_workersController.text.trim()) ?? settings.maxWorkers,
                  retryCount: int.tryParse(_retryCountController.text.trim()) ?? settings.retryCount,
                  retryBackoffSeconds: int.tryParse(_retryBackoffController.text.trim()) ?? settings.retryBackoffSeconds,
                );
                widget.controller.saveSettings(next);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Settings saved successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
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

  Future<void> _openWebsite() async {
    final launched = await launchUrl(_websiteUri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the website.')),
      );
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
                      DropdownMenuItem(value: 'mp3', child: Text('MP3 (Audio)')),
                      DropdownMenuItem(value: 'm4a', child: Text('M4A (Audio)')),
                      DropdownMenuItem(value: 'mp4', child: Text('MP4 (Video)')),
                      DropdownMenuItem(value: 'png', child: Text('PNG (Image)')),
                      DropdownMenuItem(value: 'jpg', child: Text('JPG (Image)')),
                      DropdownMenuItem(value: 'pdf', child: Text('PDF (Document)')),
                      DropdownMenuItem(value: 'txt', child: Text('TXT (Text)')),
                      DropdownMenuItem(value: 'zip', child: Text('ZIP (Archive)')),
                      DropdownMenuItem(value: 'epub', child: Text('EPUB (E-book)')),
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

  Future<String?> _promptForUrl(BuildContext context, String title) async {
    final controller = TextEditingController();
    String? result;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'https://...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                result = controller.text.trim();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    return result;
  }
}

class _NavItem {
  final int index;
  final IconData icon;
  final String label;
  final String? group;

  const _NavItem(this.index, this.icon, this.label, this.group);
}
