import 'dart:io';
// 'dart:typed_data' not needed; removed to satisfy analyzer.
import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../browser/adblock/adblock_service.dart';
import '../browser/cast/cast_service.dart';
import '../browser/cast/unified_cast_service.dart';
import '../browser/tabs/tab_manager.dart';
import '../browser/video/video_detector_service.dart';
import '../data/browser_db.dart';
import '../services/download_service.dart';
import '../models/search_result.dart';
import '../models/preview_item.dart';
import '../state/app_controller.dart';
import 'browser/browser_bottom_bar.dart';
import 'browser/browser_toolbar.dart';
import 'browser/cast/cast_picker_sheet.dart';
import 'browser/cast_mini_bar.dart';
import 'browser/new_tab_page.dart';
import 'browser/history_screen.dart';
import 'browser/favourites_screen.dart';
import 'browser/browser_settings_screen.dart';

/// Full-featured browser screen with ad-blocking, video detection, and casting.
class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  final void Function(SearchResult result) onAddToQueue;

  const BrowserScreen({super.key, this.initialUrl, required this.onAddToQueue});

  static final GlobalKey<_BrowserScreenState> browserKey = GlobalKey();

  static void navigate(String url) {
    browserKey.currentState?._navigateTo(url);
  }

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  // ── Services ──
  final BrowserRepository _repo = BrowserRepository();
  final AdBlockService _adBlock = AdBlockService();
  final UnifiedCastService _castService = UnifiedCastService();
  final TabManager _tabManager = TabManager();
  VideoDetectorService _videoDetector = VideoDetectorService();

  InAppWebViewController? _webViewController;
  FindInteractionController? _findInteractionController;
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _findController = TextEditingController();

  bool _isLoading = false;
  double _progress = 0;
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isSecure = false;
  bool _desktopMode = false;
  bool _showNewTabPage = true;
  bool _isFavourited = false;
  String _searchEngine = 'DuckDuckGo';
                // Horizontal tab strip removed — the toolbar tab button
                // and the tab switcher sheet provide a consistent UX.
  @override
  void dispose() {
    _castBadgeController.dispose();
    _videoDetector.removeListener(_onVideoDetectorChanged);
    _castService.removeListener(_onCastChanged);
    _castService.stopDiscovery();
    _addressController.dispose();
    _findController.dispose();
    _castService.dispose();
    _videoDetector.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // ── URL helpers ──

  String _normalizeInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final domainPattern = RegExp(r'^[^\s]+\.[a-zA-Z]{2,}(:\d+)?([/?#].*)?$');
    if (domainPattern.hasMatch(trimmed)) return 'https://$trimmed';
    final ipPattern =
        RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(/.*)?$');
    if (ipPattern.hasMatch(trimmed)) return 'https://$trimmed';
    if (trimmed.startsWith('localhost')) return 'http://$trimmed';

    final encoded = Uri.encodeComponent(trimmed);
    return switch (_searchEngine) {
      'Google' => 'https://www.google.com/search?q=$encoded',
      'Bing' => 'https://www.bing.com/search?q=$encoded',
      'Brave' => 'https://search.brave.com/search?q=$encoded',
      _ => 'https://duckduckgo.com/?q=$encoded',
    };
  }

  void _navigateTo(String urlStr) {
    final normalized = _normalizeInput(urlStr);
    if (normalized.isEmpty) return;
    setState(() {
      _showNewTabPage = false;
      _isFavourited = false;
    });
    _addressController.text = normalized;
    // Ensure the WebView is created when the user navigates.
    _createWebView = true;

    if (_webViewController != null) {
      _webViewController!
          .loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
    } else {
      _pendingUrl = normalized;
    }
  }

  void _onNewTabPageNavigate(String url) => _navigateTo(url);

  // ── Favourite state helper ──

  Future<void> _checkFavouriteState() async {
    final url = _addressController.text.trim();
    if (url.isEmpty) {
      if (_isFavourited) setState(() => _isFavourited = false);
      return;
    }
    final fav = await _repo.isFavourite(url);
    if (mounted && fav != _isFavourited) {
      setState(() => _isFavourited = fav);
    }
  }

  // ── WebView callbacks ──

  InAppWebViewSettings _buildSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      useHybridComposition: true,
      transparentBackground: false,
      useShouldInterceptRequest: true,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      useWideViewPort: true,
      loadWithOverviewMode: true,
      allowContentAccess: true,
      allowFileAccess: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      incognito: _tabManager.activeTab?.isIncognito ?? false,
      userAgent: _desktopMode
          ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
          : null,
    );
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    debugPrint('[BROWSER] onWebViewCreated – controller ready');
    _webViewController = controller;

    controller.addJavaScriptHandler(
      handlerName: 'onVideoFound',
      callback: (args) {
        if (args.isNotEmpty) {
          _videoDetector.handleJsCallback(args[0].toString());
        }
      },
    );

    // Load any URL that was requested before the controller was ready.
    final urlToLoad = _pendingUrl;
    _pendingUrl = null;
    if (urlToLoad != null && urlToLoad.isNotEmpty) {
      controller.loadUrl(urlRequest: URLRequest(url: WebUri(urlToLoad)));
    }
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    debugPrint('[BROWSER] onLoadStart – $url');
    _videoDetector.clearForPage();
    final urlStr = url?.toString() ?? '';
    // Ignore about:blank navigations caused by WebView initialisation.
    if (urlStr == 'about:blank') return;
    setState(() {
      _isLoading = true;
      _addressController.text = urlStr;
      _isSecure = urlStr.startsWith('https://');
      _isFavourited = false;
    });
    final activeTab = _tabManager.activeTab;
    if (activeTab != null) {
      _tabManager.updateTab(activeTab.id, url: urlStr, isLoading: true);
    }
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    debugPrint('[BROWSER] onLoadStop – $url');
    final urlStr = url?.toString() ?? '';
    // Ignore about:blank completions.
    if (urlStr == 'about:blank') return;
    _addressController.text = urlStr;

    final title = await controller.getTitle() ?? '';
    _canGoBack = await controller.canGoBack();
    _canGoForward = await controller.canGoForward();

    setState(() {
      _isLoading = false;
      _isSwitchingTab = false;
      _pageTitle = title;
    });

    final activeTab = _tabManager.activeTab;
    if (activeTab != null) {
      _tabManager.updateTab(activeTab.id,
          url: urlStr, title: title, isLoading: false);
    }

    // Check favourite state.
    _checkFavouriteState();

    // Record in history (unless incognito).
    if (!(_tabManager.activeTab?.isIncognito ?? false) && urlStr.isNotEmpty) {
      final domain = Uri.tryParse(urlStr)?.host ?? '';
      final faviconUrl = domain.isNotEmpty
          ? 'https://www.google.com/s2/favicons?sz=64&domain_url=$domain'
          : null;
      _repo.addHistory(urlStr, title, faviconUrl);
      _repo.upsertRecentSite(urlStr, title, faviconUrl);
    }

    // Inject video detection JS.
    controller.evaluateJavascript(source: VideoDetectorService.injectionJs);

    // Inject popup blocker when ad-block is on.
    if (_adBlock.adBlockEnabled) {
      controller.evaluateJavascript(
          source: VideoDetectorService.popupBlockerJs);
    }
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    setState(() => _progress = progress / 100.0);
  }

  Future<NavigationActionPolicy?> _shouldOverrideUrlLoading(
      InAppWebViewController controller, NavigationAction action) async {
    final url = action.request.url?.toString() ?? '';
    // Handle external protocols (tel:, mailto:, etc.).
    if (url.startsWith('tel:') ||
        url.startsWith('mailto:') ||
        url.startsWith('intent:') ||
        url.startsWith('market:')) {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {}
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<WebResourceResponse?> _shouldInterceptRequest(
      InAppWebViewController controller, WebResourceRequest request) async {
    final url = request.url.toString();

    // Ad-block (skip on YouTube/Google sites whose players depend on Google ad
    // domains like doubleclick.net and googlesyndication.com).
    if (_adBlock.adBlockEnabled && _adBlock.shouldBlock(url)) {
      final pageHost =
          Uri.tryParse(_addressController.text)?.host.toLowerCase() ?? '';
      final isGoogleSite = pageHost.endsWith('youtube.com') ||
          pageHost.endsWith('.youtube.com') ||
          pageHost.endsWith('google.com') ||
          pageHost.endsWith('.google.com') ||
          pageHost.contains('.google.');
      if (!isGoogleSite) {
        return WebResourceResponse(data: Uint8List(0));
      }
    }

    // Video detection via network sniffing.
    if (VideoDetectorService.isVideoUrl(url)) {
      _videoDetector.notifyVideoFound(url);
    }

    return null;
  }

  void _onConsoleMessage(
      InAppWebViewController controller, ConsoleMessage message) {
    if (kDebugMode) {
      debugPrint('WebView Console: ${message.message}');
    }
  }

  void _onReceivedError(InAppWebViewController controller,
      WebResourceRequest request, WebResourceError error) {
    debugPrint(
        '[BROWSER] onReceivedError – ${request.url} | ${error.type} | ${error.description}');
    if (request.isForMainFrame ?? false) {
      setState(() => _isLoading = false);
    }
  }

  void _onScrollChanged(InAppWebViewController controller, int x, int y) {
    controller.evaluateJavascript(source: VideoDetectorService.injectionJs);
  }

  // ── Actions ──

  void _goBack() async {
    if (_webViewController != null && await _webViewController!.canGoBack()) {
      _webViewController!.goBack();
    }
  }

  void _goForward() async {
    if (_webViewController != null &&
        await _webViewController!.canGoForward()) {
      _webViewController!.goForward();
    }
  }

  void _reload() {
    if (_showNewTabPage) return;
    final currentUrl = _addressController.text.trim();
    if (_isLoading) {
      _webViewController?.stopLoading();
      setState(() => _isLoading = false);
    } else if (currentUrl.isNotEmpty && currentUrl != 'about:blank') {
      _webViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(currentUrl)));
    }
  }

  void _openCastSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CastPickerSheet(
        detectedUrls: _videoDetector.detectedUrls,
        castService: _castService,
        onCast: (device, url) {
          _castService.castUrl(device, url,
              title: _pageTitle.isNotEmpty ? _pageTitle : null);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _goHome() {
    setState(() {
      _showNewTabPage = true;
      _isFavourited = false;
    });
    _addressController.clear();
  }

  void _toggleIncognito() {
    final tab = _tabManager.activeTab;
    if (tab == null) return;
    _tabManager.addTab(incognito: !tab.isIncognito);
    setState(() => _showNewTabPage = true);
  }

  void _toggleFavourite() async {
    final url = _addressController.text.trim();
    if (url.isEmpty || _showNewTabPage) return;
    if (_isFavourited) {
      await _repo.removeFavourite(url);
      setState(() => _isFavourited = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Removed from favourites'),
              duration: Duration(seconds: 1)),
        );
      }
    } else {
      final domain = Uri.tryParse(url)?.host ?? '';
      final faviconUrl = domain.isNotEmpty
          ? 'https://www.google.com/s2/favicons?sz=64&domain_url=$domain'
          : null;
      await _repo.addFavourite(url, _pageTitle, faviconUrl);
      setState(() => _isFavourited = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Added to favourites'),
              duration: Duration(seconds: 1)),
        );
      }
    }
  }

  void _addCurrentToQueue() {
    final url = _addressController.text.trim();
    if (url.isEmpty) return;
    Uri? uri;
    String? id;
    try {
      uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host.contains('youtube.com') ||
          host.contains('youtu.be') ||
          host.contains('music.youtube.com')) {
        id = uri.queryParameters['v'];
        if (id == null && host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
          id = uri.pathSegments[0];
        }
        if (id == null &&
            uri.pathSegments.length >= 2 &&
            uri.pathSegments[0] == 'shorts') {
          id = uri.pathSegments[1];
        }
        if (id == null &&
            uri.pathSegments.length >= 2 &&
            uri.pathSegments[0] == 'embed') {
          id = uri.pathSegments[1];
        }
      }
    } catch (_) {}

    if (id != null) {
      widget.onAddToQueue(SearchResult(
        id: id,
        title: _pageTitle.isNotEmpty ? _pageTitle : url,
        artist: 'YouTube',
        duration: Duration.zero,
        thumbnailUrl: 'https://img.youtube.com/vi/$id/default.jpg',
        source: 'youtube',
      ));
    } else {
      widget.onAddToQueue(SearchResult(
        id: url,
        title: _pageTitle.isNotEmpty ? _pageTitle : (uri?.host ?? url),
        artist: uri?.host ?? 'Web',
        duration: Duration.zero,
        thumbnailUrl: '',
        source: 'generic',
      ));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Added to queue'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _openInExternal() async {
    final url = _addressController.text.trim();
    if (url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _toggleDesktopMode() async {
    _desktopMode = !_desktopMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('browser_desktop_mode', _desktopMode);
    _webViewController?.setSettings(settings: _buildSettings());
    _webViewController?.reload();
    setState(() {});
  }

  // ── Find-in-page ──

  void _openFindInPage() {
    setState(() => _showFindBar = true);
    _findController.clear();
    _findMatchCount = 0;
    _findActiveIndex = 0;
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoryScreen(
          repo: _repo,
          onNavigate: (url) {
            Navigator.pop(context);
            _navigateTo(url);
          },
        ),
      ),
    );
  }

  void _openFavourites() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavouritesScreen(
          repo: _repo,
          onNavigate: (url) {
            Navigator.pop(context);
            _navigateTo(url);
          },
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserSettingsScreen(
          adBlockService: _adBlock,
          repo: _repo,
        ),
      ),
    );
  }

  void _closeFindInPage() {
    _findInteractionController?.clearMatches();
    setState(() {
      _showFindBar = false;
      _findMatchCount = 0;
      _findActiveIndex = 0;
    });
  }

  void _performFind(String query) async {
    if (query.isEmpty) {
      _findInteractionController?.clearMatches();
      setState(() {
        _findMatchCount = 0;
        _findActiveIndex = 0;
      });
      return;
    }
    await _findInteractionController?.findAll(find: query);
  }

  void _findNext() {
    _findInteractionController?.findNext(forward: true);
    if (_findMatchCount > 0) {
      setState(() {
        _findActiveIndex = (_findActiveIndex + 1) % _findMatchCount;
      });
    }
  }

  void _findPrevious() {
    _findInteractionController?.findNext(forward: false);
    if (_findMatchCount > 0) {
      setState(() {
        _findActiveIndex =
            (_findActiveIndex - 1 + _findMatchCount) % _findMatchCount;
      });
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncognito = _tabManager.activeTab?.isIncognito ?? false;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // ── Tab row (old-style browser tabs) ──
                if (_tabManager.tabCount > 1)
                  SizedBox(
                    height: 40,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: _tabManager.tabs.asMap().entries.map((e) {
                          final idx = e.key;
                          final tab = e.value;
                          final isActive = idx == _tabManager.activeIndex;
                          return GestureDetector(
                            onTap: () {
                              _tabManager.switchToTab(idx);
                              final showNew = tab.url.isEmpty;
                              setState(() => _showNewTabPage = showNew);
                              if (!showNew && tab.url.isNotEmpty) {
                                _webViewController?.loadUrl(
                                    urlRequest:
                                        URLRequest(url: WebUri(tab.url)));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.1)
                                    : null,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isActive
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                  width: isActive ? 2 : 1,
                                ),
                              ),
                              width: 120,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (tab.screenshot != null) ...[
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 24,
                                        maxWidth: 24,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.memory(
                                          tab.screenshot!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  Text(
                                    tab.title.isNotEmpty
                                        ? tab.title
                                        : (Uri.tryParse(tab.url)?.host ?? ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                // ── Top toolbar ──
                BrowserToolbar(
                  addressController: _addressController,
                  isLoading: _isLoading,
                  isSecure: _isSecure,
                  isIncognito: isIncognito,
                  canGoBack: _canGoBack,
                  canGoForward: _canGoForward,
                  hasVideos: _videoDetector.hasVideos,
                  castBadgeAnimation: _castBadgeController,
                  desktopMode: _desktopMode,
                  adBlockEnabled: _adBlock.adBlockEnabled,
                  pageTitle: _pageTitle,
                  onBack: _goBack,
                  onForward: _goForward,
                  onReload: _reload,
                  onSubmitted: _navigateTo,
                  onCastTap: _openCastSheet,
                  onDownload: _handleDownload,
                  isDownloading: _isDownloading,
                  downloadEnabled: true,
                  isKnownDifficultSite:
                      DownloadService.isDifficultSite(_addressController.text),
                  isCastConnected: _castService.activeDevice != null,
                  onMenuAction: _handleMenuAction,
                  onTabs: _showTabSwitcher,
                  tabCount: _tabManager.tabCount,
                ),

                // ── Progress bar ──
                if (_isLoading)
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 2,
                  ),

                // ── WebView + NewTabPage (Stack: WebView persists) ──
                Expanded(
                  child: Stack(
                    children: [
                      // WebView always in tree (texture-based on
                      // Windows — no HWND overlay issues). NewTabPage
                      // is placed on top when active.
                      if (_webViewSupported && _createWebView)
                        Positioned.fill(child: _buildWebView())
                      // Tab-switch overlay — appears while a tab switch triggers
                      // a webview load so the previous content doesn't flash.
                      if (_isSwitchingTab)
                        Positioned.fill(
                          child: ColoredBox(
                            color: cs.surface,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: cs.primary,
                                  ),
                                  const SizedBox(height: 12),
                                  Text('Loading tab…',
                                      style: TextStyle(
                                        color: cs.onSurfaceVariant,
                                        fontSize: 13,
                                      )),
                                ],
                              ),
                            ),
                          ),
                        )
                      else if (_webViewSupported && !_createWebView)
                        // Show the NewTabPage when the webview is not yet created.
                        Positioned.fill(
                          child: NewTabPage(
                            repo: _repo,
                            onNavigate: _onNewTabPageNavigate,
                          ),
                        )
                      else
                        _buildPlatformUnavailable(),

                      // NewTabPage overlay.
                      if (_showNewTabPage)
                        Positioned.fill(
                          child: NewTabPage(
                            repo: _repo,
                            onNavigate: _onNewTabPageNavigate,
                          ),
                        ),

                      // Find-in-page bar.
                      if (_showFindBar)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _buildFindBar(),
                        ),
                    ],
                  ),
                ),

                // ── Bottom bar ──
                BrowserBottomBar(
                  tabCount: _tabManager.tabCount,
                  isFavourited: _isFavourited,
                  onHome: _goHome,
                  onTabs: _showTabSwitcher,
                  onFavourite: _toggleFavourite,
                  bottomPadding: viewPadding.bottom,
                ),
              ],
            ),

            // ── Cast mini bar ──
            if (_castService.activeDevice != null)
              Positioned(
                bottom: viewPadding.bottom + 56,
                left: 0,
                right: 0,
                child: CastMiniBar(
                  deviceName: _castService.activeDevice!.name,
                  isPlaying:
                      _castService.playbackState == CastPlaybackState.playing,
                  onPlayPause: () {
                    if (_castService.playbackState ==
                        CastPlaybackState.playing) {
                      _castService.pause();
                    } else {
                      _castService.resume();
                    }
                  },
                  onStop: () => _castService.stop(),
                ),
              ),

            // ── Extract & Download FAB for difficult sites ──
            if (!_showNewTabPage &&
                DownloadService.isDifficultSite(_addressController.text))
              Positioned(
                bottom: viewPadding.bottom + 72,
                right: 16,
                child: FloatingActionButton.extended(
                  heroTag: 'extract_download',
                  onPressed: _addCurrentToQueue,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Extract & Download'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    try {
      return InAppWebView(
        key: const ValueKey('browser_webview'),
        initialSettings: _buildSettings(),
        findInteractionController: _findInteractionController,
        onWebViewCreated: _onWebViewCreated,
        onLoadStart: _onLoadStart,
        onLoadStop: _onLoadStop,
        onProgressChanged: _onProgressChanged,
        shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
        shouldInterceptRequest: _shouldInterceptRequest,
        onConsoleMessage: _onConsoleMessage,
        onReceivedError: _onReceivedError,
        onScrollChanged: _onScrollChanged,
        onUpdateVisitedHistory: (controller, url, androidIsReload) {
          final urlStr = url?.toString() ?? '';
          if (urlStr.isEmpty || urlStr == 'about:blank') return;
          setState(() {
            _addressController.text = urlStr;
            _isSecure = urlStr.startsWith('https://');
          });
          final activeTab = _tabManager.activeTab;
          if (activeTab != null) {
            _tabManager.updateTab(activeTab.id, url: urlStr);
          }
          controller.canGoBack().then((v) {
            if (mounted) setState(() => _canGoBack = v);
          });
          controller.canGoForward().then((v) {
            if (mounted) setState(() => _canGoForward = v);
          });
          _checkFavouriteState();
        },
        onDownloadStartRequest: (controller, request) {
          launchUrl(request.url, mode: LaunchMode.externalApplication);
        },
        onCreateWindow: (controller, createWindowAction) async {
          // Open new-window requests in the same WebView.
          final url = createWindowAction.request.url;
          if (url != null) {
            _navigateTo(url.toString());
          }
          return false;
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('InAppWebView construction failed: $e');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('In-app browser unavailable on this device.'),
              action: SnackBarAction(
                label: 'Open externally',
                onPressed: () => launchUrl(Uri.parse('about:blank'),
                    mode: LaunchMode.externalApplication),
              ),
            ));
          } catch (_) {}
        });
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                  'Browser unavailable. Microsoft Edge WebView2 Runtime is required.'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => launchUrl(Uri.parse(
                    'https://developer.microsoft.com/microsoft-edge/webview2/')),
                child: const Text('Download WebView2'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildPlatformUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text(
              'In-app browser is not available on this platform.\n'
              'Use the button below to open in your default browser.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openInExternal,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in External Browser'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFindBar() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _findController,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Find in page',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                onChanged: _performFind,
                onSubmitted: (_) => _findNext(),
              ),
            ),
            if (_findMatchCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_findActiveIndex + 1}/$_findMatchCount',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: _findPrevious,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: _findNext,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: _closeFindInPage,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'new_tab':
        _tabManager.addTab();
        setState(() => _showNewTabPage = true);
        break;
      case 'incognito':
        _toggleIncognito();
        break;
      case 'add_favourite':
        _toggleFavourite();
        break;
      case 'share':
        final url = _addressController.text.trim();
        if (url.isNotEmpty) {
          // ignore: deprecated_member_use
          Share.share(url);
        }
        break;
      case 'desktop_mode':
        _toggleDesktopMode();
        break;
      case 'adblock':
        _adBlock.toggleAdBlock();
        setState(() {});
        break;
      case 'download':
        _addCurrentToQueue();
        break;
      case 'external':
      case 'openExternal':
        _openInExternal();
        break;
      case 'find':
        _openFindInPage();
        break;
      case 'history':
        _openHistory();
        break;
      case 'favourites':
        _openFavourites();
        break;
      case 'settings':
      case 'addCookies':
        _openSettings();
        break;
      case 'cast':
        _openCastSheet();
        break;
      case 'copyLink':
        final url = _addressController.text.trim();
        if (url.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: url));
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied to clipboard')));
        }
        break;
      case 'copy':
        final url = _addressController.text.trim();
        if (url.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: url));
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied to clipboard')));
        }
        break;
      default:
        break;
    }
  }

  Future<void> _handleDownload() async {
    // Obtain fresh URL from the WebView controller to avoid stale state
    final uri = await _webViewController?.getUrl();
    final url = uri?.toString() ?? _addressController.text.trim();
    if (url.isEmpty ||
        url == 'about:blank' ||
        url.startsWith('chrome:') ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No downloadable page loaded.')));
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadError = null;
    });

    try {
      final title = _pageTitle.isNotEmpty ? _pageTitle : '';
      final previewItem = PreviewItem(
        id: url,
        title: title.isNotEmpty ? title : url,
        url: url,
        uploader: '',
        duration: null,
        thumbnailUrl: null,
      );

      final app = context.read<AppController>();
      // Default to mp4 for generic page media
      const format = 'mp4';
      app.addToQueue(previewItem, format);

      // Find the queued item
      final queued =
          app.queue.firstWhere((q) => q.url == url && q.format == format);

      // Start download (don't await fully — show immediate feedback)
      unawaited(app.downloadSingle(queued).then((_) {
        if (mounted) setState(() => _isDownloading = false);
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _downloadError = e.toString();
            _isDownloading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(DownloadService.translateError(e.toString()))));
        }
      }));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Download started: ${title.isNotEmpty ? title : url}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadError = e.toString();
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DownloadService.translateError(e.toString()))));
      }
    }
  }

  void _showTabSwitcher() {
    // remove focus from URL/search field first, otherwise taps in the sheet
    // can be swallowed by the still‑focused TextField and only clear focus.
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TabSwitcherSheet(
        tabManager: _tabManager,
        onSelectTab: (index) {
          _tabManager.switchToTab(index);
          final tab = _tabManager.activeTab;
          final showNew = tab?.url.isEmpty ?? true;
          setState(() {
            _showNewTabPage = showNew;
            _isSwitchingTab = !showNew;
          });
          if (!showNew && tab != null && tab.url.isNotEmpty) {
            _addressController.text = tab.url;
            _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri(tab.url)));
          }
          Navigator.pop(context);
        },
        onCloseTab: (index) {
          _tabManager.closeTab(index);
          final tab = _tabManager.activeTab;
          final showNew = tab?.url.isEmpty ?? true;
          setState(() {
            _showNewTabPage = showNew;
            _isSwitchingTab = !showNew && tab != null;
          });
          if (!showNew && tab != null && tab.url.isNotEmpty) {
            _addressController.text = tab.url;
            _pageTitle = tab.title;
            _webViewController?.loadUrl(
                urlRequest: URLRequest(url: WebUri(tab.url)));
          } else {
            _addressController.clear();
            _pageTitle = '';
          }
        },
        onNewTab: () {
          _tabManager.addTab();
          setState(() {
            _showNewTabPage = true;
            _isSwitchingTab = false;
            _addressController.clear();
            _pageTitle = '';
            _isSecure = false;
            _canGoBack = false;
            _canGoForward = false;
          });
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ── Tab Switcher Sheet ──

class _TabSwitcherSheet extends StatelessWidget {
  final TabManager tabManager;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onCloseTab;
  final VoidCallback onNewTab;

  const _TabSwitcherSheet({
    required this.tabManager,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text('Tabs (${tabManager.tabCount})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: onNewTab,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: tabManager.tabCount,
                itemBuilder: (context, index) {
                  final tab = tabManager.tabs[index];
                  final isActive = index == tabManager.activeIndex;
                  return GestureDetector(
                    onTap: () => onSelectTab(index),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive ? cs.primary : cs.outlineVariant,
                          width: isActive ? 2 : 1,
                        ),
                        color: tab.isIncognito
                            ? cs.surface
                            : cs.surfaceContainerLow,
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                if (tab.isIncognito)
                                  Icon(Icons.visibility_off,
                                      size: 14, color: cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    tab.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tab.isIncognito
                                          ? cs.onSurfaceVariant
                                          : null,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => onCloseTab(index),
                                  child: Icon(Icons.close,
                                      size: 16,
                                      color: tab.isIncognito
                                          ? cs.onSurfaceVariant
                                          : cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: tab.screenshot != null
                                ? ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(11),
                                      bottomRight: Radius.circular(11),
                                    ),
                                    child: Image.memory(
                                      tab.screenshot!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                                  )
                                : Center(
                                    child: Icon(Icons.web,
                                        size: 32, color: cs.outlineVariant),
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
