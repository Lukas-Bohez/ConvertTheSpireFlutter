import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/search_result.dart';

/// A simple full‑page browser that starts on YouTube and remembers its
/// internal navigation state while it lives in memory.  Switching away from
/// the tab does not rebuild the widget, so history is preserved.  The
/// browser also supports a crude "incognito" mode which clears cookies/cache
/// on enter/exit and does not persist any state between toggles.
///
/// The widget exposes a small toolbar with a URL entry field, back/forward
/// buttons, reload, and an incognito toggle.  On startup it always navigates
/// to the YouTube homepage as requested by the user.
class BrowserScreen extends StatefulWidget {
  /// Optional URL to navigate to as soon as the controller is ready.
  final String? initialUrl;

  /// Callback invoked when the user presses the download button.
  final void Function(SearchResult result) onAddToQueue;

  BrowserScreen({Key? key, this.initialUrl, required this.onAddToQueue}) : super(key: key);

  /// Global key that allows other widgets (e.g. search screen) to access the
  /// state and call `_navigateTo` without relying on the tab widget being in
  /// the current route.  HomeScreen attaches this key when constructing the
  /// browser page.
  static final GlobalKey<_BrowserScreenState> browserKey = GlobalKey();

  /// Convenience method that other classes can call instead of reaching for
  /// the key directly.
  static void navigate(String url) {
    browserKey.currentState?._navigateTo(url);
  }

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with AutomaticKeepAliveClientMixin {
  WebViewController? _normalController;
  WebViewController? _incognitoController;

  // Windows-specific controllers (uses webview_windows package)
  WebviewController? _winController;
  WebviewController? _winIncognitoController;

  bool _winInitError = false; // set true if Windows webview fails to init
  bool _isIncognito = false;

  /// Whether we should attempt to create a WebView controller.  After
  /// installing the proper federated plugins this will be true on every
  /// platform except pure web; the only remaining case where the widget
  /// should fall back to a placeholder is when running in the browser itself.
  bool get _webViewSupported => !kIsWeb;

  bool get _usingWindows => !kIsWeb && Platform.isWindows;

  final List<String> _bookmarks = [];

  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // On Android we would normally set the platform implementation for
    // performance.  Removing this reference keeps the file compiling on
    // Windows where `WebView` and `SurfaceAndroidWebView` are unavailable.
    // The default implementation works fine on other platforms.
    //
    // if (!kIsWeb && Platform.isAndroid) {
    //   WebView.platform = SurfaceAndroidWebView();
    // }

    // delay async work
    _setupControllers();

    // if the user provided an initial URL, navigate once the controller is
    // ready.  We can't do this synchronously here because controllers are
    // created asynchronously; instead our _setupControllers callback uses
    // _activeController or _winController, so we simply schedule a post frame
    // check.
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateTo(widget.initialUrl!);
      });
    }
  }

  Future<void> _setupControllers() async {
    if (_usingWindows) {
      try {
        // initialize with timeout in case WebView2 hang occurs
        final ctrl = await _createWindowsController()
            .timeout(const Duration(seconds: 15));
        setState(() {
          _winController = ctrl;
          _winInitError = false;
        });
      } catch (e) {
        debugPrint('Windows webview init error: $e');
        setState(() {
          _winInitError = true;
          _addressController.text = 'https://www.youtube.com/';
        });
      }
    } else if (_webViewSupported) {
      try {
        await _createNormalController();
        setState(() {});
      } catch (_) {
        _addressController.text = 'https://www.youtube.com/';
      }
    } else {
      _addressController.text = 'https://www.youtube.com/';
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _createNormalController() async {
    _normalController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          _addressController.text = url.toString();
        },
        onPageFinished: (url) {
          _addressController.text = url.toString();
        },
      ))
      ..loadRequest(Uri.parse('https://www.youtube.com/'));
    _addressController.text = 'https://www.youtube.com/';
  }

  /// Creates a Windows WebView controller.
  ///
  /// If [userDataPath] is provided, we pass it to the environment initializer
  /// so that each controller can use an isolated profile (used for incognito).
  Future<WebviewController> _createWindowsController({String? userDataPath}) async {
    // initialize env once (throws if already initialized)
    try {
      await WebviewController.initializeEnvironment(
          userDataPath: userDataPath);
    } catch (_) {}
    final ctrl = WebviewController();
    await ctrl.initialize();
    // subscribe early for url changes
    ctrl.url.listen((u) {
      setState(() { _addressController.text = u; });
    });
    await ctrl.loadUrl('https://www.youtube.com/');
    _addressController.text = 'https://www.youtube.com/';
    return ctrl;
  }

  Future<void> _enterIncognito() async {
    // mark as incognito immediately so UI updates
    setState(() { _isIncognito = true; });

    if (_usingWindows) {
      try {
        final ctrl = await _createWindowsController()
            .timeout(const Duration(seconds: 15));
        // clean session
        await ctrl.clearCookies();
        await ctrl.clearCache();
        setState(() {
          _winIncognitoController = ctrl;
        });
      } catch (e) {
        debugPrint('Windows incognito init failed: $e');
        // revert the incognito toggle so user doesn't end up looking at
        // a permanent spinner; they can try again if they wish.
        setState(() {
          _isIncognito = false;
        });
      }
      return;
    }

    if (!_webViewSupported) return;
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) {
            _addressController.text = url.toString();
          },
          onPageFinished: (url) {
            _addressController.text = url.toString();
          },
        ))
        ..loadRequest(Uri.parse('https://www.youtube.com/'));
      // clear cookies using new API
      try {
        await WebViewCookieManager().clearCookies();
      } catch (_) {}
      setState(() {
        _incognitoController = controller;
      });
      _addressController.text = 'https://www.youtube.com/';
    } catch (_) {}
  }

  Future<void> _exitIncognito() async {
    if (_usingWindows) {
      // dispose controller if desired
      _winIncognitoController = null;
      setState(() {
        _isIncognito = false;
      });
      return;
    }

    if (!_webViewSupported) return;
    _incognitoController = null;
    setState(() {
      _isIncognito = false;
    });
    // update address bar to whatever normal controller has
    _normalController?.currentUrl().then((uri) {
      if (uri != null) {
        _addressController.text = uri.toString();
      }
    });
  }

  WebViewController? get _activeController {
    if (_usingWindows) return null;
    if (!_webViewSupported) return null;
    return (_isIncognito ? _incognitoController : _normalController);
  }

  void _navigateTo(String urlStr) {
    final uri = Uri.parse(urlStr);
    _addressController.text = urlStr;
    if (_usingWindows) {
      final ctrl = _isIncognito ? _winIncognitoController : _winController;
      ctrl?.loadUrl(urlStr);
    } else {
      _activeController?.loadRequest(uri);
    }
  }

  Widget _buildToolbar() {
    if (!_webViewSupported) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Theme.of(context).colorScheme.surfaceVariant,
        child: const Center(child: Text('WebView unsupported')),
      );
    }

    final bgColor = _isIncognito
        ? Colors.grey.shade900
        : Theme.of(context).colorScheme.surface;
    final iconColor = _isIncognito
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    return Container(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: IconTheme(
          data: IconThemeData(color: iconColor),
          child: Row(
            children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (_usingWindows) {
                final ctrl = _isIncognito ? _winIncognitoController : _winController;
                if (ctrl != null) {
                  ctrl.goBack();
                }
              } else {
                if (_activeController != null && await _activeController!.canGoBack()) {
                  _activeController!.goBack();
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () async {
              if (_usingWindows) {
                final ctrl = _isIncognito ? _winIncognitoController : _winController;
                if (ctrl != null) {
                  ctrl.goForward();
                }
              } else {
                if (_activeController != null && await _activeController!.canGoForward()) {
                  _activeController!.goForward();
                }
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _addressController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (str) {
                final uri = Uri.parse(str);
                if (_usingWindows) {
                  final ctrl = _isIncognito ? _winIncognitoController : _winController;
                  ctrl?.loadUrl(uri.toString());
                } else {
                  _activeController?.loadRequest(uri);
                }
              },
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_usingWindows) {
                final ctrl = _isIncognito ? _winIncognitoController : _winController;
                ctrl?.reload();
              } else {
                _activeController?.reload();
              }
            },
          ),
          IconButton(
            icon: Icon(_isIncognito ? Icons.visibility_off : Icons.visibility),
            tooltip: _isIncognito ? 'Exit incognito' : 'Enter incognito',
            onPressed: () {
              if (_isIncognito) {
                _exitIncognito();
              } else {
                _enterIncognito();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.bookmark),
            tooltip: 'Bookmarks',
            onPressed: _showBookmarksDialog,
          ),
          IconButton(
            icon: const Icon(Icons.coffee),
            tooltip: 'Support me',
            onPressed: () async {
              final uri = Uri.parse('https://buymeacoffee.com/orokaconner');
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                // handle failure silently
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.quiz),
            tooltip: 'Quiz the Spire',
            onPressed: () {
              _navigateTo('https://quizthespire.com/');
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download current',
            onPressed: _addCurrentToQueue,
          ),
        ],
          ), // close Row
        ), // close IconTheme
      ), // close Padding
    );
  }


  /// Enqueue the current URL (if it is a YouTube video) for download.
  void _addCurrentToQueue() {
    final url = _addressController.text.trim();
    if (url.isEmpty) return;
    String? id;
    Uri? uri;
    try {
      uri = Uri.parse(url);
      if (uri.host.contains('youtube.com')) {
        id = uri.queryParameters['v'];
      } else if (uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments[0];
      }
    } catch (_) {}
    if (id == null) return;

    final result = SearchResult(
      id: id,
      title: uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : url,
      artist: 'YouTube',
      duration: Duration.zero,
      thumbnailUrl: 'https://img.youtube.com/vi/$id/default.jpg',
      source: 'youtube',
    );
    widget.onAddToQueue(result);
  }

  void _showBookmarksDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Bookmarks'),
          content: SizedBox(
            width: 300,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final bm in _bookmarks)
                  ListTile(
                    title: Text(bm),
                    onTap: () {
                      Navigator.pop(ctx);
                      _navigateTo(bm);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() => _bookmarks.remove(bm));
                        Navigator.pop(ctx);
                        _showBookmarksDialog();
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add current'),
                  onTap: () {
                    Navigator.pop(ctx);
                    final current = _addressController.text;
                    if (current.isNotEmpty && !_bookmarks.contains(current)) {
                      setState(() => _bookmarks.add(current));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // from AutomaticKeepAliveClientMixin
    return Column(
      children: [
        _buildToolbar(),
        const Divider(height: 1),
        Expanded(
          child: _usingWindows
              ? (_isIncognito
                  ? (_winIncognitoController == null
                      ? const Center(child: CircularProgressIndicator())
                      : KeyedSubtree(
                          key: const ValueKey('win-incognito'),
                          child: Webview(_winIncognitoController!),
                        ))
                  : (_winController == null
                      ? (_winInitError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Failed to initialize WebView'),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _setupControllers,
                                  child: const Text('Retry'),
                                ),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator()))
                      : KeyedSubtree(
                          key: const ValueKey('win-normal'),
                          child: Webview(_winController!),
                        )))
              : (!_webViewSupported || _activeController == null)
                  ? const Center(
                      child: Text('WebView not supported in this environment'),
                    )
                  : WebViewWidget(controller: _activeController!),
        ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}
