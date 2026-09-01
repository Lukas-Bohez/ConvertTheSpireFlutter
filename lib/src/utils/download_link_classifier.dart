/// TrackSpire Downloads — classifies a URL the in-app browser is about to
/// navigate to as either a normal page load or something that should be
/// handed to UnifiedDownloadService instead.
///
/// Deliberately a pure, dependency-free function so it's easy to unit test
/// on its own. It is called from the EXISTING `_shouldOverrideUrlLoading`
/// method in `lib/src/screens/browser_screen.dart` — see
/// masterprompt_bitplayer_inapp_browser_downloads.md, Module 1, for the
/// exact patch. There is no new browser screen in this batch: BitPlayer
/// already has a full one (tabs, cast, adblock, history, favourites,
/// video detection) and this just teaches its existing navigation hook one
/// more thing to recognise.
library;

import '../models/unified_download_task.dart';

class DownloadLinkIntent {
  final UnifiedDownloadType type;
  final UnifiedDownloadCategory category;
  final String url;
  final String suggestedTitle;

  const DownloadLinkIntent({
    required this.type,
    required this.category,
    required this.url,
    required this.suggestedTitle,
  });
}

class DownloadLinkClassifier {
  // Keep the magnet check identical to the one in
  // lib/src/utils/browser_submission.dart (`lower.startsWith('magnet:')`).
  // That function classifies text TYPED into the address bar; this one
  // classifies a link TAPPED on a page. Same rule, two different entry
  // points into the same browser.
  static DownloadLinkIntent? classify(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return null;
    final lower = url.toLowerCase();

    if (lower.startsWith('magnet:')) {
      return DownloadLinkIntent(
        type: UnifiedDownloadType.torrent,
        category: UnifiedDownloadCategory.media,
        url: url,
        suggestedTitle: _magnetDisplayName(url) ?? 'Magnet download',
      );
    }

    final path = Uri.tryParse(url)?.path.toLowerCase() ?? lower;

    if (path.endsWith('.torrent')) {
      return DownloadLinkIntent(
        type: UnifiedDownloadType.torrent,
        category: UnifiedDownloadCategory.media,
        url: url,
        suggestedTitle: _fileNameFrom(path),
      );
    }

    if (path.endsWith('.apk')) {
      return DownloadLinkIntent(
        type: UnifiedDownloadType.directHttp,
        category: UnifiedDownloadCategory.appUpdate,
        url: url,
        suggestedTitle: _fileNameFrom(path),
      );
    }

    const archiveExt = ['.zip', '.rar', '.7z', '.tar', '.gz'];
    if (archiveExt.any(path.endsWith)) {
      return DownloadLinkIntent(
        type: UnifiedDownloadType.directHttp,
        category: UnifiedDownloadCategory.archive,
        url: url,
        suggestedTitle: _fileNameFrom(path),
      );
    }

    // Explicit "download this file" links. This is intentionally separate
    // from VideoDetectorService (lib/src/browser/video/video_detector_service.dart),
    // which already catches <video>/XHR-detected streaming URLs on the page
    // via JS injection — a different mechanism for a different situation.
    // Route BOTH into UnifiedDownloadService.enqueueHttp at the call site
    // so "grab this stream" and "tap this download link" land in the same
    // downloads dashboard.
    const mediaExt = [
      '.mp3', '.m4a', '.flac', '.wav', '.mp4', '.mkv', '.webm', '.mov'
    ];
    if (mediaExt.any(path.endsWith)) {
      return DownloadLinkIntent(
        type: UnifiedDownloadType.directHttp,
        category: UnifiedDownloadCategory.media,
        url: url,
        suggestedTitle: _fileNameFrom(path),
      );
    }

    return null; // not a download link - let the page navigate normally
  }

  static String _fileNameFrom(String path) {
    final segments = path.split('/');
    final last = segments.isNotEmpty ? segments.last : path;
    if (last.isEmpty) return 'download';
    try {
      return Uri.decodeComponent(last);
    } catch (_) {
      return last;
    }
  }

  static String? _magnetDisplayName(String magnetUri) {
    final match = RegExp(r'dn=([^&]+)').firstMatch(magnetUri);
    if (match == null) return null;
    try {
      return Uri.decodeComponent(match.group(1)!.replaceAll('+', ' '));
    } catch (_) {
      return null;
    }
  }
}
