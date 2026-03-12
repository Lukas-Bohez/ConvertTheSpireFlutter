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
import '../utils/snack.dart';

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
  final Map<String, InAppWebViewController> _controllers = {};
  VideoDetectorService _videoDetector = VideoDetectorService();

  InAppWebViewController? _webViewController;
  FindInteractionController? _findInteractionController;
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _findController = TextEditingController();
  // Missing state fields reintroduced
  late AnimationController _castBadgeController;
  bool _createWebView = false;
  String? _pendingUrl;
  bool _isLoading = false;
  double _progress = 0;
  String _pageTitle = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isSecure = false;
  bool _desktopMode = false;
  bool _showNewTabPage = true;
  bool _isFavourited = false;
  bool _isSwitchingTab = false;
  bool _showFindBar = false;
  int _findMatchCount = 0;
  int _findActiveIndex = 0;
  bool _isDownloading = false;
  String? _downloadError;
  bool get _webViewSupported => !kIsWeb;
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
    // Best-effort: stop any active controller loads before clearing map.
    try {
      for (final c in _controllers.values) {
        try {
          c.stopLoading();
        } catch (_) {}
      }
    } catch (_) {}
    _controllers.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _castBadgeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _videoDetector.addListener(_onVideoDetectorChanged);
    _castService.addListener(_onCastChanged);
    // Start cast discovery; stopDiscovery() is called in dispose().
    unawaited(_castService.startDiscovery());
    _findInteractionController = FindInteractionController();
    // Listen for tab manager changes to update active controller and UI
    _tabManager.addListener(_onTabManagerChanged);
  }

  void _releaseWebViewFocus() {
    // Forces WebView2 to release pointer capture on Windows
    FocusScope.of(context).unfocus();
    // Small delay to allow Windows message pump to process the focus change
    Future.microtask(() {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  void _onTabManagerChanged() {
    final active = _tabManager.activeTab;
    final ctrl = active != null ? _controllers[active.id] : null;
    setState(() {
      _showNewTabPage = (active?.url.isEmpty ?? true);
      _isSwitchingTab = !(_showNewTabPage);
      _webViewController = ctrl;
      if (ctrl != null && active?.url.isNotEmpty == true) {
        _addressController.text = active!.url;
        _pageTitle = active.title;
      } else if (ctrl == null && active?.url.isNotEmpty == true) {
        // Ensure a WebView is created for this tab and schedule loading.
        _pendingUrl = active!.url;
        _createWebView = true;
      }
    });
  }

  void _onVideoDetectorChanged() {
    if (mounted) setState(() {});
  }

  void _onCastChanged() {
    if (mounted) setState(() {});
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

    final active = _tabManager.activeTab;
    if (active != null) {
      _tabManager.updateTab(active.id, url: normalized, isLoading: true);
      final ctrl = _controllers[active.id];
      if (ctrl != null) {
        ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
      } else {
        // pending: stored in tab model url field
      }
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
  }

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    debugPrint('[BROWSER] onLoadStart – $url');
    _videoDetector.clearForPage();
    final urlStr = url?.toString() ?? '';
    // Ignore about:blank navigations caused by WebView initialisation.
    if (urlStr == 'about:blank') return;
    // Always mark loading state, but only update visible UI fields when
    // the event comes from the active tab's controller to avoid flashing
    // when background tabs load.
    _isLoading = true;
    final activeTab = _tabManager.activeTab;
    final activeController =
        activeTab != null ? _controllers[activeTab.id] : null;
    if (activeController == controller) {
      setState(() {
        _addressController.text = urlStr;
        _isSecure = urlStr.startsWith('https://');
        _isFavourited = false;
      });
    } else {
      // Ensure UI is refreshed for loading indicator changes.
      if (mounted) setState(() {});
    }

    if (activeTab != null) {
      _tabManager.updateTab(activeTab.id, url: urlStr, isLoading: true);
    }
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    debugPrint('[BROWSER] onLoadStop – $url');
    final urlStr = url?.toString() ?? '';
    // Ignore about:blank completions.
    if (urlStr == 'about:blank') return;
    // Only update visible UI elements if this controller belongs to the
    // active tab. Background tab loads should not steal focus or change
    // the address bar while the user is looking at another tab.
    final activeTab = _tabManager.activeTab;
    final activeController =
        activeTab != null ? _controllers[activeTab.id] : null;

    final title = await controller.getTitle() ?? '';
    if (activeController == controller) {
      _canGoBack = await controller.canGoBack();
      _canGoForward = await controller.canGoForward();
      setState(() {
        _isLoading = false;
        _isSwitchingTab = false;
        _pageTitle = title;
        _addressController.text = urlStr;
      });
    } else {
      // Background tab finished loading; still update its model.
      if (mounted) setState(() {});
    }

    if (activeTab != null && activeController == controller) {
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
    _releaseWebViewFocus();
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
        Snack.show(context, 'Removed from favourites', level: SnackLevel.info);
      }
    } else {
      final domain = Uri.tryParse(url)?.host ?? '';
      final faviconUrl = domain.isNotEmpty
          ? 'https://www.google.com/s2/favicons?sz=64&domain_url=$domain'
          : null;
      await _repo.addFavourite(url, _pageTitle, faviconUrl);
      setState(() => _isFavourited = true);
      if (mounted) {
        Snack.show(context, 'Added to favourites', level: SnackLevel.success);
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
      Snack.show(context, 'Added to queue', level: SnackLevel.success);
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
                // Old horizontal tab strip removed — toolbar + tab switcher used.

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
                  onReleaseWebViewFocus: _releaseWebViewFocus,
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
                        Positioned.fill(child: _buildWebView()),
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

            // ── Download error banner ──
            if (_downloadError != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: viewPadding.bottom + 136,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _downloadError!,
                            style: TextStyle(color: cs.onError, fontSize: 13),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: cs.onError),
                          onPressed: () =>
                              setState(() => _downloadError = null),
                        ),
                      ],
                    ),
                  ),
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
      // Build an IndexedStack of WebViews, one per tab, to keep each
      // WebView alive and avoid re-creating native resources on tab switch.
      final tabs = _tabManager.tabs;
      if (tabs.isEmpty) {
        return const SizedBox.shrink();
      }

      final active = _tabManager.activeTab;
      final activeIndex = active != null ? tabs.indexOf(active) : 0;

      return IndexedStack(
        index: activeIndex < 0 ? 0 : activeIndex,
        children: tabs.map((t) => _buildWebViewForTab(t)).toList(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('InAppWebView construction failed: $e');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            Snack.show(
              context,
              'In-app browser unavailable on this device.',
              level: SnackLevel.error,
              actionLabel: 'Open externally',
              onAction: () => launchUrl(Uri.parse('about:blank'),
                  mode: LaunchMode.externalApplication),
            );
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

  InAppWebViewSettings _buildSettingsForTab(BrowserTab tab) {
    final s = _buildSettings();
    s.incognito = tab.isIncognito;
    return s;
  }

  void _onWebViewCreatedForTab(
      InAppWebViewController controller, String tabId, BrowserTab tab) {
    debugPrint('[BROWSER] onWebViewCreated – controller ready for $tabId');
    _controllers[tabId] = controller;
    if (_tabManager.activeTab?.id == tabId) {
      _webViewController = controller;
    }

    controller.addJavaScriptHandler(
      handlerName: 'onVideoFound',
      callback: (args) {
        if (args.isNotEmpty) {
          _videoDetector.handleJsCallback(args[0].toString());
        }
      },
    );

    // If the tab already has a URL assigned, ensure it's loaded.
    final tabUrl = tab.url;
    if (tabUrl.isNotEmpty) {
      try {
        controller.loadUrl(urlRequest: URLRequest(url: WebUri(tabUrl)));
      } catch (_) {}
    }
  }

  Widget _buildWebViewForTab(BrowserTab tab) {
    // Use a stable key so Flutter preserves each WebView widget instance.
    final key = ValueKey('browser_webview_${tab.id}');
    return Positioned.fill(
      child: InAppWebView(
        key: key,
        initialSettings: _buildSettingsForTab(tab),
        initialUrlRequest:
            tab.url.isNotEmpty ? URLRequest(url: WebUri(tab.url)) : null,
        findInteractionController: _findInteractionController,
        onWebViewCreated: (controller) =>
            _onWebViewCreatedForTab(controller, tab.id, tab),
        onLoadStart: (controller, url) => _onLoadStart(controller, url),
        onLoadStop: (controller, url) => _onLoadStop(controller, url),
        onProgressChanged: _onProgressChanged,
        shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
        shouldInterceptRequest: _shouldInterceptRequest,
        onConsoleMessage: _onConsoleMessage,
        onReceivedError: _onReceivedError,
        onScrollChanged: _onScrollChanged,
        onUpdateVisitedHistory: (controller, url, androidIsReload) {
          final urlStr = url?.toString() ?? '';
          if (urlStr.isEmpty || urlStr == 'about:blank') return;
          // Update model for this tab specifically.
          _tabManager.updateTab(tab.id, url: urlStr);

          if (_controllers[tab.id] == controller) {
            if (mounted)
              setState(() {
                if (_tabManager.activeTab?.id == tab.id) {
                  _addressController.text = urlStr;
                  _isSecure = urlStr.startsWith('https://');
                }
              });

            controller.canGoBack().then((v) {
              if (mounted && _tabManager.activeTab?.id == tab.id)
                setState(() => _canGoBack = v);
            });
            controller.canGoForward().then((v) {
              if (mounted && _tabManager.activeTab?.id == tab.id)
                setState(() => _canGoForward = v);
            });
            _checkFavouriteState();
          }
        },
        onDownloadStartRequest: (controller, request) {
          launchUrl(request.url, mode: LaunchMode.externalApplication);
        },
        onCreateWindow: (controller, createWindowAction) async {
          final url = createWindowAction.request.url;
          if (url != null) {
            _navigateTo(url.toString());
          }
          return false;
        },
      ),
    );
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
          if (mounted) Snack.show(context, 'Link copied to clipboard');
        }
        break;
      case 'copy':
        final url = _addressController.text.trim();
        if (url.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: url));
          if (mounted) Snack.show(context, 'Link copied to clipboard');
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
        Snack.show(context, 'No downloadable page loaded.',
            level: SnackLevel.warning);
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
          Snack.show(context, DownloadService.translateError(e.toString()),
              level: SnackLevel.error);
        }
      }));

      if (mounted) {
        Snack.show(
            context, 'Download started: ${title.isNotEmpty ? title : url}',
            level: SnackLevel.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadError = e.toString();
          _isDownloading = false;
        });
        Snack.show(context, DownloadService.translateError(e.toString()),
            level: SnackLevel.error);
      }
    }
  }

  void _showTabSwitcher() {
    // Release WebView focus so Windows WebView2 doesn't capture clicks
    // intended for the upcoming overlay/sheet.
    _releaseWebViewFocus();
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
            if (tab != null) {
              _addressController.text = tab.url;
              _pageTitle = tab.title;
              _isSecure = tab.url.startsWith('https://');
              _canGoBack = false;
              _canGoForward = false;
            }
          });
          if (tab != null && !showNew && tab.url.isNotEmpty) {
            _addressController.text = tab.url;
            final ctrl = _controllers[tab.id];
            _webViewController = ctrl;
            if (ctrl != null) {
              ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(tab.url)));
            } else {
              _pendingUrl = tab.url;
              _createWebView = true;
            }
          }
          Navigator.pop(context);
        },
        onCloseTab: (index) {
          // Dispose mapping for the tab being closed to avoid leaking
          // controllers. Capture tab id before closing since the list
          // will be mutated by closeTab().
          try {
            final closingTab = _tabManager.tabs[index];
            final ctrl = _controllers.remove(closingTab.id);
            if (ctrl != null) {
              // Best-effort: stop loading and remove JS handlers.
              try {
                ctrl.stopLoading();
              } catch (_) {}
            }
          } catch (_) {}

          _tabManager.closeTab(index);
          final tab = _tabManager.activeTab;
          final showNew = tab?.url.isEmpty ?? true;
          setState(() {
            _showNewTabPage = showNew;
            _isSwitchingTab = !showNew && tab != null;
            _addressController.text = tab?.url ?? '';
            _pageTitle = tab?.title ?? '';
            _canGoBack = false;
            _canGoForward = false;
            _isSecure = (tab?.url ?? '').startsWith('https://');
          });
          if (!showNew && tab != null && tab.url.isNotEmpty) {
            final ctrl = _controllers[tab.id];
            _webViewController = ctrl;
            if (ctrl != null) {
              ctrl.loadUrl(urlRequest: URLRequest(url: WebUri(tab.url)));
            } else {
              _pendingUrl = tab.url;
              _createWebView = true;
            }
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
