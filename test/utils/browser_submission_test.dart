import 'package:convert_the_spire_reborn/src/utils/browser_submission.dart';
import 'package:convert_the_spire_reborn/src/widgets/quick_links_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves internal routes by keyword and title', () {
    final keyword = resolveBrowserSubmission(
      'browser',
      routeToIndex: QuickLinksService.routeToIndex,
      indexToRoute: QuickLinksService.indexToRoute,
      indexToTitle: QuickLinksService.indexToTitle,
    );
    expect(keyword.kind, BrowserSubmissionKind.internalRoute);
    expect(keyword.value, 'browser.tab');

    final title = resolveBrowserSubmission(
      'Player',
      routeToIndex: QuickLinksService.routeToIndex,
      indexToRoute: QuickLinksService.indexToRoute,
      indexToTitle: QuickLinksService.indexToTitle,
    );
    expect(title.kind, BrowserSubmissionKind.internalRoute);
    expect(title.value, 'player.tab');
  });

  test('normalizes open URL requests and search text', () {
    final url = resolveBrowserSubmission(
      'example.com',
      routeToIndex: QuickLinksService.routeToIndex,
      indexToRoute: QuickLinksService.indexToRoute,
      indexToTitle: QuickLinksService.indexToTitle,
    );
    expect(url.kind, BrowserSubmissionKind.openUrl);
    expect(url.value, 'https://example.com');

    final search = resolveBrowserSubmission(
      'lofi beats',
      routeToIndex: QuickLinksService.routeToIndex,
      indexToRoute: QuickLinksService.indexToRoute,
      indexToTitle: QuickLinksService.indexToTitle,
    );
    expect(search.kind, BrowserSubmissionKind.openUrl);
    expect(search.value, contains('google.com/search'));
  });

  test('passes magnet links through untouched', () {
    final magnet = resolveBrowserSubmission(
      'magnet:?xt=urn:btih:abc123',
      routeToIndex: QuickLinksService.routeToIndex,
      indexToRoute: QuickLinksService.indexToRoute,
      indexToTitle: QuickLinksService.indexToTitle,
    );
    expect(magnet.kind, BrowserSubmissionKind.magnet);
    expect(magnet.value, 'magnet:?xt=urn:btih:abc123');
  });
}
