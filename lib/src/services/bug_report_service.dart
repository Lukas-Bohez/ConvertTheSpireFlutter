import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../config/build_flags.dart';
import 'session_log_service.dart';

/// Builds a prefilled GitHub issue so a report arrives with enough to act on.
///
/// A solo maintainer cannot chase people for version numbers and platforms
/// (issue #7). The user still sees and can edit everything before submitting:
/// this only opens GitHub's new-issue form with the fields filled in.
class BugReportService {
  BugReportService._();

  static const String repository = 'Lukas-Bohez/ConvertTheSpireFlutter';

  /// How many log lines to attach. Enough for the run-up to a failure, short
  /// enough that nobody has to scroll past it to write their report.
  static const int logLines = 50;

  /// The environment block that goes at the top of a report.
  static Future<String> environmentSummary() async {
    final buffer = StringBuffer();
    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // A missing plugin must not stop somebody reporting a bug.
    }
    buffer.writeln('- App version: $version');
    buffer.writeln('- Build: ${kPlayStoreBuild ? 'Play Store' : 'GitHub'}');
    if (kIsWeb) {
      buffer.writeln('- Platform: web');
    } else {
      buffer.writeln('- Platform: ${Platform.operatingSystem}');
      buffer.writeln('- OS version: ${Platform.operatingSystemVersion}');
    }
    return buffer.toString().trimRight();
  }

  /// The full issue body, including the recent log.
  static Future<String> buildBody({String? description}) async {
    final buffer = StringBuffer()
      ..writeln('## What happened')
      ..writeln()
      ..writeln(description?.trim().isNotEmpty == true
          ? description!.trim()
          : '<!-- Describe what you did and what happened instead. -->')
      ..writeln()
      ..writeln('## Environment')
      ..writeln()
      ..writeln(await environmentSummary())
      ..writeln();

    final log = SessionLogService.instance.recent(limit: logLines);
    if (log.isNotEmpty) {
      buffer
        ..writeln('## Recent log')
        ..writeln()
        ..writeln('<details><summary>Last ${log.length} lines</summary>')
        ..writeln()
        ..writeln('```')
        ..writeln(log.join('\n'))
        ..writeln('```')
        ..writeln()
        ..writeln('</details>');
    }
    return buffer.toString();
  }

  /// The GitHub URL that opens a new issue with [title] and [body] filled in.
  ///
  /// GitHub rejects very long query strings, so the body is trimmed to stay
  /// within a length that works in practice.
  static Uri issueUrl({required String title, required String body}) {
    const maxBody = 6000;
    final trimmed = body.length <= maxBody
        ? body
        : '${body.substring(0, maxBody)}\n\n<!-- log truncated -->';
    return Uri.https('github.com', '/$repository/issues/new', {
      'title': title,
      'body': trimmed,
    });
  }

  /// Convenience: the URL for a report about [title].
  static Future<Uri> buildIssueUrl({
    String title = 'Bug: ',
    String? description,
  }) async =>
      issueUrl(title: title, body: await buildBody(description: description));
}
