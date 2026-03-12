import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Detects video streams on web pages via JS injection and network sniffing.
class VideoDetectorService extends ChangeNotifier {
  final Set<String> _detectedUrls = LinkedHashSet<String>();

  Set<String> get detectedUrls => UnmodifiableSetView(_detectedUrls);
  bool get hasVideos => _detectedUrls.isNotEmpty;

  /// Called when a video URL is found (JS handler or network intercept).
  void notifyVideoFound(String url) {
    if (url.isEmpty) return;
    if (_detectedUrls.add(url)) {
      notifyListeners();
    }
  }

  /// Clear detected URLs — called on page navigation start.
  void clearForPage() {
    if (_detectedUrls.isNotEmpty) {
      _detectedUrls.clear();
      notifyListeners();
    }
  }

  /// Process the JSON payload from the JS handler.
  void handleJsCallback(String jsonPayload) {
    try {
      final data = jsonDecode(jsonPayload);
      if (data is Map) {
        final url = data['url'] as String?;
        if (url != null && url.length > 4) notifyVideoFound(url);
      } else if (data is List) {
        for (final item in data) {
          if (item is Map) {
            final url = item['url'] as String?;
            if (url != null && url.length > 4) notifyVideoFound(url);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('VideoDetector: failed to parse JS data: $e');
    }
  }

  /// Check if a URL looks like a video resource.
  static bool isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return RegExp(r'\.(m3u8|mp4|mpd|ts|webm|flv)(\?|$)', caseSensitive: false)
        .hasMatch(lower);
  }

  /// JavaScript to inject into pages for video detection.
  ///
  /// This scans `<video>` elements, hooks XHR/fetch, and observes DOM
  /// mutations for dynamically added players.
  static const injectionJs = r'''
(function() {
  if (window.__videoDetectorInjected) return;
  window.__videoDetectorInjected = true;

  function scanVideos() {
    var found = [];
    document.querySelectorAll('video').forEach(function(v) {
      var src = v.currentSrc || v.src;
      if (src && src.length > 4) found.push({url: src, type: 'video_tag'});
      v.querySelectorAll('source').forEach(function(s) {
        if (s.src) found.push({url: s.src, type: 'source_tag'});
      });
    });
    return found;
  }

  var _open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    if (typeof url === 'string' && /\.(m3u8|mp4|mpd|ts|webm)(\?|$)/i.test(url)) {
      window.flutter_inappwebview.callHandler('onVideoFound', JSON.stringify({url: url, type: 'xhr'}));
    }
    return _open.apply(this, arguments);
  };

  var _fetch = window.fetch;
  window.fetch = function(input, init) {
    var url = (typeof input === 'string') ? input : (input && input.url) ? input.url : '';
    if (/\.(m3u8|mp4|mpd|ts|webm)(\?|$)/i.test(url)) {
      window.flutter_inappwebview.callHandler('onVideoFound', JSON.stringify({url: url, type: 'fetch'}));
    }
    return _fetch.apply(this, arguments);
  };

  var initial = scanVideos();
  if (initial.length > 0) {
    window.flutter_inappwebview.callHandler('onVideoFound', JSON.stringify(initial[0]));
  }

  new MutationObserver(function() {
    var vids = scanVideos();
    if (vids.length > 0) {
      window.flutter_inappwebview.callHandler('onVideoFound', JSON.stringify(vids[0]));
    }
  }).observe(document.body || document.documentElement, {childList: true, subtree: true});
})();
''';

  /// JavaScript to suppress popups.
  static const popupBlockerJs = r'''
window.open = function(){ return null; };
''';
}
