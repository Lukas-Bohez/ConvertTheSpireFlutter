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

  /// The full issue body, including the last [logLimit] log lines.
  static Future<String> buildBody({
    String? description,
    int logLimit = logLines,
  }) async {
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

    final log = logLimit > 0
        ? SessionLogService.instance.recent(limit: logLimit)
        : const <String>[];
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

  /// The longest URL handed to the browser. GitHub rejects very long query
  /// strings, and the limit applies after percent-encoding, which roughly
  /// triples every bracket, colon and slash in a log line.
  static const int maxUrlLength = 7500;

  static Uri _issueUri(String title, String body) =>
      Uri.https('github.com', '/$repository/issues/new', {
        'title': title,
        'body': body,
      });

  /// The GitHub URL that opens a new issue with [title] and [body] filled in.
  ///
  /// A body too long for [maxUrlLength] is cut to the longest prefix that
  /// fits, measured on the encoded URL rather than on characters.
  static Uri issueUrl({required String title, required String body}) {
    final full = _issueUri(title, body);
    if (full.toString().length <= maxUrlLength) return full;

    const marker = '\n\n<!-- log truncated -->';
    var low = 0;
    var high = body.length;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final candidate = _issueUri(title, '${body.substring(0, mid)}$marker');
      if (candidate.toString().length <= maxUrlLength) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return _issueUri(title, '${body.substring(0, low)}$marker');
  }

  /// Convenience: the URL for a report about [title].
  ///
  /// When the report is too long, the oldest log lines go first: the lines
  /// just before a failure are the ones worth reading.
  static Future<Uri> buildIssueUrl({
    String title = 'Bug: ',
    String? description,
  }) async {
    for (var limit = logLines; limit > 0; limit -= 10) {
      final body = await buildBody(description: description, logLimit: limit);
      final url = _issueUri(title, body);
      if (url.toString().length <= maxUrlLength) return url;
    }
    return issueUrl(
      title: title,
      body: await buildBody(description: description, logLimit: 0),
    );
  }
}
