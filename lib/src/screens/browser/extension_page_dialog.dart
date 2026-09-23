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

  /// Popups start at a typical size and then fit their content.
  Size _size = const Size(380, 520);

  static const Size _minPopup = Size(240, 160);
  static const Size _maxPopup = Size(800, 600);
  static const double _scrollbarAllowance = 18;

  @override
  void initState() {
    super.initState();
    if (widget.isOptionsPage) _size = const Size(900, 640);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await WebView2Environment.ensure();
      await _controller.initialize();
      _loading = _controller.loadingState.listen((state) {
        if (state == LoadingState.navigationCompleted) unawaited(_fit());
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
      // A popup taller than the cap scrolls, and the vertical scrollbar
      // takes width from the content; leave room so no horizontal bar appears.
      final scrolls = height > _maxPopup.height;
      setState(() {
        _size = Size(
          (width + (scrolls ? _scrollbarAllowance : 0))
              .clamp(_minPopup.width, _maxPopup.width),
          height.clamp(_minPopup.height, _maxPopup.height),
        );
      });
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final width = _size.width.clamp(200.0, screen.width - 48);
    final height = _size.height.clamp(120.0, screen.height - 140);

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
