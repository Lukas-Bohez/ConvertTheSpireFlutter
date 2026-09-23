import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../services/bug_report_service.dart';
import '../services/session_log_service.dart';

/// What the app shows when a widget fails to build.
///
/// Release builds used to render a bare grey rectangle, which told the user
/// nothing and told the maintainer even less - the Watch Together bug looked
/// exactly like that for a whole release (issue #7). This shows what broke and
/// hands over a block of text that can be pasted straight into a bug report.
class AppErrorScreen extends StatelessWidget {
  final FlutterErrorDetails details;

  const AppErrorScreen({super.key, required this.details});

  /// How much of the error to show on screen. The full text goes into the
  /// copied report; this only has to say what went wrong.
  static const int _shownErrorLength = 400;

  /// Everything worth pasting into an issue: the error, where it happened, and
  /// the breadcrumbs leading up to it.
  String buildReport() {
    final buffer = StringBuffer()
      ..writeln('Error: ${details.exceptionAsString()}');
    final context = details.context;
    if (context != null) buffer.writeln('While: $context');
    final stack = details.stack?.toString().split('\n').take(12).join('\n');
    if (stack != null && stack.isNotEmpty) {
      buffer
        ..writeln('Stack:')
        ..writeln(stack);
    }
    final log = SessionLogService.instance.recent();
    if (log.isNotEmpty) {
      buffer
        ..writeln('Recent log:')
        ..writeln(log.join('\n'));
    }
    return buffer.toString();
  }

  String _shownError() {
    final text = details.exceptionAsString();
    if (text.length <= _shownErrorLength) return text;
    return '${text.substring(0, _shownErrorLength)}…';
  }

  Future<void> _copyDetails(BuildContext buttonContext) async {
    final messenger = ScaffoldMessenger.maybeOf(buttonContext);
    try {
      await Clipboard.setData(ClipboardData(text: buildReport()));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Details copied to clipboard')),
      );
    } catch (e, st) {
      SessionLogService.instance.logSwallowed(e, st, 'error_screen_copy');
    }
  }

  Future<void> _report() async {
    try {
      final url = await BugReportService.buildIssueUrl(
        title: 'Bug: app error screen',
        description: details.exceptionAsString(),
      );
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e, st) {
      SessionLogService.instance.logSwallowed(e, st, 'error_screen_report');
    }
  }

  @override
  Widget build(BuildContext context) {
    // This replaces whatever widget failed, so it can land anywhere: filling
    // a route, inside one list tile, in a Row slot, above or below
    // MaterialApp. It must lay out under any constraints, including unbounded
    // ones inside scrolling lists, and must not depend on Theme, MediaQuery or
    // Directionality - an exception thrown while building the error screen
    // would only produce another error screen.
    //
    // Hence a min-sized Column with a loose Flexible (valid when the height is
    // unbounded, unlike Expanded), maybe-lookups instead of SafeArea, and a
    // ClipRect so a cramped slot is cut off rather than painted over its
    // neighbours.
    final safePadding = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ClipRect(
        child: Material(
          color: const Color(0xFF1C1B1F),
          child: Padding(
            padding: safePadding + const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: Color(0xFFFFB4AB)),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Something broke here',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      _shownError(),
                      style: const TextStyle(
                        color: Color(0xFFE6E1E5),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (buttonContext) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _copyDetails(buttonContext),
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy details'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _report,
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('Report this'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
