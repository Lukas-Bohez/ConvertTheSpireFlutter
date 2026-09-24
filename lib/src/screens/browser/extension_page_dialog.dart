import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../../browser/platform/webview2_environment.dart';

/// Shows an extension's own page - its toolbar popup or its options page.
///
/// WebView2 has no browser chrome, so nothing opens these by itself; the app
/// hosts them in a webview of its own. Popups size themselves to their
/// content, the way a browser shows them; options pages get a large window
/// (issue #10).
class ExtensionPageDialog extends StatefulWidget {
  const ExtensionPageDialog({
    super.key,
    required this.url,
    required this.title,
    this.isOptionsPage = false,
  });

  final String url;
  final String title;
  final bool isOptionsPage;

  static Future<void> show(
    BuildContext context, {
    required String url,
    required String title,
    bool isOptionsPage = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ExtensionPageDialog(
          url: url, title: title, isOptionsPage: isOptionsPage),
    );
  }

  @override
  State<ExtensionPageDialog> createState() => _ExtensionPageDialogState();
}

class _ExtensionPageDialogState extends State<ExtensionPageDialog> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<LoadingState>? _loading;
  bool _ready = false;
  String? _error;

  /// The popup page's preferred size, once measured. Until then popups show
  /// at a typical size.
  Size? _content;

  static const Size _defaultPopup = Size(380, 520);
  static const Size _optionsPage = Size(900, 640);
  static const Size _minPopup = Size(240, 160);
  static const Size _maxPopup = Size(800, 600);

  /// Room for a vertical scrollbar, so a popup that has to scroll does not
  /// also grow a horizontal one.
  static const double _scrollbarAllowance = 18;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await WebView2Environment.ensure();
      await _controller.initialize();
      // A popup's "open settings" link opens a tab; keep it in this dialog
      // rather than a bare window outside the app.
      await _controller
          .setPopupWindowPolicy(WebviewPopupWindowPolicy.sameWindow);
      _loading = _controller.loadingState.listen((state) {
        if (state != LoadingState.navigationCompleted) return;
        // Popups often build their UI with script after "loaded" fires, so
        // measure again as the page settles; the last measurement wins.
        unawaited(_fit());
        for (final delay in const [400, 1200]) {
          Future<void>.delayed(Duration(milliseconds: delay), () {
            if (mounted) unawaited(_fit());
          });
        }
      });
      await _controller.loadUrl(widget.url);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open this page: $e');
    }
  }

  /// Sizes a popup to its content, within the limits browsers use.
  Future<void> _fit() async {
    if (widget.isOptionsPage || !mounted) return;
    try {
      // The page's preferred width, the way a browser sizes a popup: lay the
      // document out at max-content for a moment and read it back.
      // documentElement.scrollWidth also counted panels a popup keeps off to
      // the side, which opened Dark Reader's 410px popup 800px wide.
      final measured = await _controller.executeScript('''
          (() => {
            const html = document.documentElement, body = document.body;
            if (!body) return [0, 0];
            const previous = html.style.width;
            html.style.width = 'max-content';
            const width = Math.ceil(html.getBoundingClientRect().width);
            const height = Math.ceil(Math.max(body.scrollHeight,
                                              html.scrollHeight));
            html.style.width = previous;
            return [width, height];
          })()''');
      if (measured is! List || measured.length != 2) return;
      final width = (measured[0] as num).toDouble();
      final height = (measured[1] as num).toDouble();
      if (width <= 0 || height <= 0 || !mounted) return;
      setState(() => _content = Size(width, height));
    } catch (_) {
      // Keep the default size; a page we cannot measure still works.
    }
  }

  @override
  void dispose() {
    unawaited(_loading?.cancel());
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// The size to show the page at, given the screen.
  ///
  /// The height limit is whichever is smaller, the 600px popup cap or what
  /// fits in the window, and a popup taller than that scrolls. The scrollbar
  /// allowance is decided against that real limit: checking only the 600px
  /// cap missed popups that scroll because the window is short, and gave them
  /// a horizontal scrollbar as well.
  (double, double) _displaySize(Size screen) {
    final maxWidth =
        (screen.width - 48).clamp(_minPopup.width, double.infinity);
    final maxHeight =
        (screen.height - 140).clamp(_minPopup.height, double.infinity);

    if (widget.isOptionsPage) {
      return (
        _optionsPage.width.clamp(_minPopup.width, maxWidth),
        _optionsPage.height.clamp(_minPopup.height, maxHeight),
      );
    }
    final content = _content ?? _defaultPopup;
    final heightLimit =
        _maxPopup.height < maxHeight ? _maxPopup.height : maxHeight;
    final widthLimit = _maxPopup.width < maxWidth ? _maxPopup.width : maxWidth;
    final scrolls = _content != null && content.height > heightLimit;
    return (
      (content.width + (scrolls ? _scrollbarAllowance : 0))
          .clamp(_minPopup.width, widthLimit),
      content.height.clamp(_minPopup.height, heightLimit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (width, height) = _displaySize(MediaQuery.sizeOf(context));

    return Dialog(
      clipBehavior: Clip.antiAlias,
      // The title bar follows the page's width instead of stretching the
      // dialog past it.
      child: SizedBox(
        width: width,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).maybePop(),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: scheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        // First in focus order, so Back/Escape and a remote's OK
                        // on the close button always get out of the popup.
                        autofocus: true,
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                height: height,
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : !_ready
                        ? const Center(child: CircularProgressIndicator())
                        : Webview(_controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
