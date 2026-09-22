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

  @override
  Widget build(BuildContext context) {
    // ErrorWidget.builder can run outside a MaterialApp, so nothing here may
    // depend on Theme or Directionality being set up already.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF1C1B1F),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, color: Color(0xFFFFB4AB)),
                    SizedBox(width: 8),
                    Text(
                      'Something broke here',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      details.exceptionAsString(),
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
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: buildReport()));
                          final messenger =
                              ScaffoldMessenger.maybeOf(buttonContext);
                          messenger?.showSnackBar(
                            const SnackBar(
                                content: Text('Details copied to clipboard')),
                          );
                        },
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy details'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final url = await BugReportService.buildIssueUrl(
                            title: 'Bug: app error screen',
                            description: details.exceptionAsString(),
                          );
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        },
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
