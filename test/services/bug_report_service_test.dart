import 'package:convert_the_spire_reborn/src/services/bug_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the prefilled bug report.
///
/// A solo maintainer cannot chase people for version numbers and platforms
/// (issue #7), so the report has to arrive complete - and it has to arrive at
/// all, which means the URL must stay inside what GitHub accepts.
void main() {
  test('the issue URL points at this repository', () {
    final url = BugReportService.issueUrl(title: 'Bug: x', body: 'body');

    expect(url.host, 'github.com');
    expect(url.path, '/${BugReportService.repository}/issues/new');
    expect(url.queryParameters['title'], 'Bug: x');
    expect(url.queryParameters['body'], 'body');
  });

  test('a very long log is trimmed rather than dropped', () {
    final huge = List.filled(5000, 'a line of log').join('\n');

    final url = BugReportService.issueUrl(title: 'Bug', body: huge);
    final body = url.queryParameters['body']!;

    expect(body.length, lessThan(huge.length));
    expect(body, contains('log truncated'));
    expect(url.toString().length, lessThan(8000),
        reason: 'GitHub rejects very long query strings');
  });

  test('a short body is left exactly as written', () {
    const body = '## What happened\n\nIt broke.';

    final url = BugReportService.issueUrl(title: 'Bug', body: body);

    expect(url.queryParameters['body'], body);
  });

  test('the description the user typed ends up in the report', () async {
    final body =
        await BugReportService.buildBody(description: 'Downloads stopped');

    expect(body, contains('Downloads stopped'));
    expect(body, contains('## Environment'));
  });

  test('an empty description leaves a prompt instead of a blank', () async {
    final body = await BugReportService.buildBody(description: '   ');

    expect(body, contains('Describe what you did'));
  });
}
